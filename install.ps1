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
#
# Written to run on Windows PowerShell 5.1, which is what a stock Windows ships,
# as well as PowerShell 7: no ternaries, no `??`, no `&&`, and ASCII only.
#
# Options, as environment variables: NIKA_VERSION (e.g. v0.1.1),
# NIKA_INSTALL_DIR, NIKA_NO_MODIFY_PATH=1.
#
# NOTE: this file is maintained in nika-planet-downloader-internal and synced to
# the root of the public repo by scripts/sync-public-repo.sh. Edit it there.

& {
    $ErrorActionPreference = 'Stop'
    # Invoke-WebRequest's progress bar makes 5.1 downloads many times slower.
    $ProgressPreference = 'SilentlyContinue'
    # Windows PowerShell 5.1 can default to TLS 1.0, which GitHub refuses.
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    $repo = 'NikaGeospatial/nika-planet-downloader'
    $binName = 'nika-planet-downloader'

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

    Write-Host 'Finding the latest release...'
    $version = $env:NIKA_VERSION
    if (-not $version) {
        $latest = Invoke-RestMethod -UseBasicParsing "https://api.github.com/repos/$repo/releases/latest"
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

    $tmp = Join-Path ([IO.Path]::GetTempPath()) ([IO.Path]::GetRandomFileName())
    New-Item -ItemType Directory -Path $tmp | Out-Null
    try {
        Write-Host "Downloading $asset..."
        $download = Join-Path $tmp $asset
        Invoke-WebRequest -UseBasicParsing "$base/$asset" -OutFile $download

        # Required, unlike install.sh: every release ships the file, and a
        # binary nobody could verify is not worth installing silently. Saved
        # to disk rather than read from .Content, which is a string on some
        # PowerShell versions and a byte array on others.
        $sumsPath = Join-Path $tmp 'SHA256SUMS.txt'
        Invoke-WebRequest -UseBasicParsing "$base/SHA256SUMS.txt" -OutFile $sumsPath
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
        Write-Host "  & '$target' login"
        return
    }

    # The user-scope PATH, so no elevation is needed. SetEnvironmentVariable
    # also broadcasts the change, so windows opened from now on see it.
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $entries = @()
    if ($userPath) { $entries = @($userPath -split ';' | Where-Object { $_ }) }
    if ($entries -notcontains $installDir) {
        [Environment]::SetEnvironmentVariable('Path', (($entries + $installDir) -join ';'), 'User')
        Write-Host "Added $installDir to your user PATH."
    }

    # Already-open windows keep the PATH they started with, but this one ran
    # the installer, so it can be brought up to date directly.
    $env:Path = "$env:Path;$installDir"
    Write-Host "Next: $binName login"
}
