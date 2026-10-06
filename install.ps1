# irm https://raw.githubusercontent.com/NikaGeospatial/nika-planet-downloader/main/install.ps1 | iex
#
# Windows counterpart of install.sh: downloads the release .exe, verifies it
# against SHA256SUMS.txt, installs it under %LOCALAPPDATA%\Programs and puts
# that folder on the user PATH. No administrator rights needed.
#
# `iex` runs this inside the caller's own session, which shapes two things.
# Nothing here may call `exit` - it would close their window - so failures
# throw instead. And the PATH change can be applied to this session as well,
# so the command works in the same window rather than only in new ones.
# Execution policy does not apply to `iex`, which is why this is the route the
# docs lead with: a stock Windows client is `Restricted` and runs no .ps1 file.
#
# Each release also carries a copy as an asset, run as a file with
# `powershell -ExecutionPolicy Bypass -File .\install.ps1`. Right-click > Run
# with PowerShell is no substitute: on Windows 11 that verb is a bare `-File`,
# which `Restricted` refuses before a line of the script runs. For a
# double-click, release.yml also builds install.cmd, which is
# scripts/install.cmd.header followed by this file.
#
# Written to run on Windows PowerShell 5.1, which is what a stock Windows ships,
# as well as PowerShell 7: no ternaries, no `??`, no `&&`, and ASCII only.
#
# Options, as environment variables: NIKA_VERSION (e.g. v0.1.1),
# NIKA_INSTALL_DIR, NIKA_NO_MODIFY_PATH=1.
#
# NOTE: this file is maintained in nika-planet-downloader-internal, synced to
# the root of the public repo by scripts/sync-public-repo.sh and attached to
# each release by .github/workflows/release.yml. Edit it there.

& {
    $ErrorActionPreference = 'Stop'
    # Invoke-WebRequest's progress bar makes 5.1 downloads many times slower.
    $ProgressPreference = 'SilentlyContinue'
    # Windows PowerShell 5.1 can default to TLS 1.0, which GitHub refuses.
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    $repo = 'NikaGeospatial/nika-planet-downloader'
    $binName = 'nika-planet-downloader'

    # Every request goes through here so that a failure names its URL. Neither
    # cmdlet's own errors do, and 5.1 can report a missing asset (a mistyped
    # NIKA_VERSION, say) as "the connection was closed unexpectedly".
    function Invoke-Fetch($url, $outFile) {
        try {
            if ($outFile) { Invoke-WebRequest -UseBasicParsing $url -OutFile $outFile }
            else { Invoke-RestMethod -UseBasicParsing $url }
        }
        catch { throw "could not download $url ($($_.Exception.Message))" }
    }

    # release.yml stamps the tag in here on the copy it attaches to a release,
    # so a file downloaded from a release page installs that release. Empty, as
    # it is everywhere else, means the latest.
    $releaseTag = ''

    # A 32-bit PowerShell on 64-bit Windows reports x86 here and the real
    # architecture in PROCESSOR_ARCHITEW6432.
    $arch = $env:PROCESSOR_ARCHITEW6432
    if (-not $arch) { $arch = $env:PROCESSOR_ARCHITECTURE }
    if ($arch -eq 'ARM64') {
        Write-Host 'Windows on Arm: installing the x64 build, which runs under emulation.'
    }
    elseif ($arch -ne 'AMD64') {
        throw "unsupported Windows architecture: $arch (64-bit Windows is required)"
    }

    $version = $env:NIKA_VERSION
    if (-not $version) { $version = $releaseTag }
    if (-not $version) {
        Write-Host 'Finding the latest release...'
        $latest = Invoke-Fetch "https://api.github.com/repos/$repo/releases/latest"
        $version = $latest.tag_name
    }
    if (-not $version) { throw 'could not determine the latest version' }
    if ($version -notlike 'v*') { $version = "v$version" }

    $asset = "$binName-$($version.Substring(1))-windows-x86_64.exe"
    $base = "https://github.com/$repo/releases/download/$version"

    $installDir = $env:NIKA_INSTALL_DIR
    if (-not $installDir) {
        $installDir = Join-Path $env:LOCALAPPDATA "Programs\$binName"
    }
    $target = Join-Path $installDir "$binName.exe"
    # The same path as a PowerShell literal, for the commands printed below: an
    # apostrophe in it (C:\Users\O'Brien) would otherwise end the quote.
    $targetLiteral = "'" + $target.Replace("'", "''") + "'"

    $tmp = Join-Path ([IO.Path]::GetTempPath()) ([IO.Path]::GetRandomFileName())
    New-Item -ItemType Directory -Path $tmp | Out-Null
    try {
        Write-Host "Downloading $asset..."
        $download = Join-Path $tmp $asset
        Invoke-Fetch "$base/$asset" $download

        # Required, unlike install.sh: every release ships the file, and a
        # binary nobody could verify is not worth installing silently. Saved
        # to disk rather than read from .Content, which is a string on some
        # PowerShell versions and a byte array on others.
        $sumsPath = Join-Path $tmp 'SHA256SUMS.txt'
        Invoke-Fetch "$base/SHA256SUMS.txt" $sumsPath
        $expected = $null
        foreach ($line in Get-Content $sumsPath) {
            $parts = $line.Trim() -split '\s+', 2
            # sha256sum marks binary-mode lines "<hash> *<file>".
            if ($parts.Count -eq 2 -and $parts[1].TrimStart('*') -eq $asset) {
                $expected = $parts[0].ToLowerInvariant()
            }
        }
        if (-not $expected) { throw "no checksum for $asset in SHA256SUMS.txt" }
        $actual = (Get-FileHash -Algorithm SHA256 -Path $download).Hash.ToLowerInvariant()
        if ($actual -ne $expected) { throw "checksum mismatch for $asset" }
        Write-Host 'Checksum verified.'

        New-Item -ItemType Directory -Force -Path $installDir | Out-Null
        Move-Item -Force -Path $download -Destination $target
    }
    finally {
        Remove-Item -Recurse -Force -Path $tmp -ErrorAction SilentlyContinue
    }

    Write-Host ''
    Write-Host "Installed $binName $version to $installDir"

    # -contains is case-insensitive, matching how Windows compares paths.
    if (($env:Path -split ';') -contains $installDir) {
        Write-Host "Next: $binName login"
        return
    }

    if ($env:NIKA_NO_MODIFY_PATH) {
        Write-Host "$installDir is not on your PATH. Add it under Settings > System > About >"
        Write-Host 'Advanced system settings > Environment Variables, or run it by its full path:'
        Write-Host "  & $targetLiteral login"
        return
    }

    # The user-scope PATH, so no elevation is needed. Read and written as raw
    # registry data: [Environment]::GetEnvironmentVariable hands entries like
    # %USERPROFILE%\... back already expanded, and SetEnvironmentVariable
    # stores the result as a plain string, freezing every variable the user's
    # PATH refers to at today's value.
    $rawPath = (Get-Item -Path 'HKCU:\Environment').GetValue('Path', '', 'DoNotExpandEnvironmentNames')
    $entries = @($rawPath -split ';' | Where-Object { $_ })
    $expanded = @($entries | ForEach-Object { [Environment]::ExpandEnvironmentVariables($_) })
    if ($expanded -notcontains $installDir) {
        Set-ItemProperty -Path 'HKCU:\Environment' -Name 'Path' -Type ExpandString -Value (($entries + $installDir) -join ';')
        # Writing the registry directly skips the broadcast that tells Explorer,
        # and so every window opened from now on, to reload the environment.
        # Any SetEnvironmentVariable call sends one; clearing a variable that
        # was never set changes nothing else.
        [Environment]::SetEnvironmentVariable('NIKA_INSTALLER_NOTIFY', $null, 'User')
        Write-Host "Added $installDir to your user PATH."
    }

    # Already-open windows keep the PATH they started with, but this session
    # ran the installer, so it can be brought up to date directly.
    $env:Path = "$env:Path;$installDir"

    # Run as a file, though, this session is usually a powershell.exe started
    # just for the script, whose PATH goes when it exits - not the window the
    # user typed into. install.cmd's window closes once this has been read.
    if ($env:NIKA_INSTALLER_CMD) {
        Write-Host "Next, open a terminal window and run: $binName login"
    }
    elseif ($PSCommandPath) {
        Write-Host "Open a new terminal window, then run: $binName login"
        Write-Host "Or use it in this window right away: & $targetLiteral login"
    }
    else {
        Write-Host "Next: $binName login"
    }
}
