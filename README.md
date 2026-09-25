# Nika Planet Downloader

Download large Nika Planet workspace folders straight to a local drive, with
resume — for exports too big to pull through a browser.

A single command-line program. No installer, no background service, no account
beyond the Nika Planet login you already have.

---

## Why you were sent here

Browser downloads become unreliable somewhere past a couple of gigabytes: the
archive has to be built and held in memory before your browser can save it. Nika
Planet routes folders over **2 GB or 2,000 files** to this tool instead, which
writes each file directly to the drive you pick and picks up where it left off
if the connection drops.

## Install

### macOS (Homebrew)

```bash
brew install nikageospatial/nika-planet-downloader/nika-planet-downloader
```

Ready to use as soon as it finishes. `brew upgrade` picks up new releases.
If you already installed the downloader, run `brew upgrade nika-planet-downloader`
to get version 0.1.4. `whoami` now shows the signed-in email or username even
when the session was cached. It also includes the 0.1.3 fix that shows control
characters in server-provided names as visible text.

### macOS and Linux (install script)

```bash
curl -fsSL https://raw.githubusercontent.com/NikaGeospatial/nika-planet-downloader/main/install.sh | sh
```

Installs to `~/.local/bin` and adds it to your shell profile, so **open a new
terminal window** before running the downloader (or call it by the full path
the installer prints). Set `NIKA_INSTALL_DIR` to install somewhere else, or
`NIKA_NO_MODIFY_PATH=1` to leave your profile alone.
Re-run the installer to update an existing copy to version 0.1.4.

### Windows

Download the `.exe` from [Releases](https://github.com/NikaGeospatial/nika-planet-downloader/releases)
and put it somewhere on your `PATH`.

### Manual download

Every release ships a `SHA256SUMS.txt`. To check what you downloaded:

```bash
shasum -a 256 -c SHA256SUMS.txt        # macOS
sha256sum -c SHA256SUMS.txt            # Linux
```

## Getting your files

**1. Sign in.** Opens your browser once; the session is then remembered in your
system keychain.

```bash
nika-planet-downloader login
```

**2. Start the download.** Point it at a folder with a `nikafs://` address —
your project id plus the path you copied from the file browser.

```bash
nika-planet-downloader export nikafs://<project-id>/data/stac/cogs --output /Volumes/ClientDrive
```

`--output` is the **parent** directory: the folder structure is recreated inside
it, so the example above lands in `/Volumes/ClientDrive/stac/cogs`.

Pass several addresses to fetch them in one run. Addresses do not expire — keep
one in a script and it keeps working for as long as you have access.

Run `export` with no address to pick from whatever the web app has queued for
you.

That's it. Progress appears in the terminal, and also on the Nika Planet page
you started from.

## Commands

| Command | What it does |
| --- | --- |
| `export --output <dir>` | Redeem a code and download its folders |
| `login` | Sign in and remember the session |
| `logout` | Forget the session on this machine |
| `whoami` | Show who is currently signed in |

### Options for `export`

| Option | Default | What it does |
| --- | --- | --- |
| `--output`, `-o` | required | Where to save. Created if it does not exist |
| `--concurrency` | `4` | How many files to fetch at once |
| `--dry-run` | off | List what would be downloaded, then stop |
| `--force` | off | Re-download files even if a copy is already there |

## Pausing and resuming

Press `Ctrl-C` at any time. Nothing is lost — half-finished files are kept as
`.nikapart` and the transfer continues from that byte when you run the same
command again:

```bash
nika-planet-downloader export --output /Volumes/ClientDrive
```

Re-running also skips files already downloaded, so it is safe to repeat.

An export stays available for **72 hours**. After that, create a new one from
Nika Planet.

## Every file is checked

Each file is verified against the checksum Google Cloud Storage reports before
it is moved into place. A file that appears at its final path is complete and
correct; anything that fails verification is discarded and retried.

If a file was deleted from the workspace while you were downloading, it is
reported as skipped — your local copies are never removed.

## Troubleshooting

**macOS: "cannot be opened because the developer cannot be verified"**

You downloaded through a browser rather than the install command above. Either
re-install with the `curl` command, or clear the quarantine flag:

```bash
xattr -d com.apple.quarantine ./nika-planet-downloader
```

**"Your session has expired"** — run `nika-planet-downloader login` again.

**"This export has expired"** — codes last 72 hours. Request a new export from
Nika Planet.

**"You do not have permission to download from this workspace"** — your Nika
Planet account needs Contributor access or above on that workspace. Whoever
shared the export can grant it.

**Downloads are slow** — raise `--concurrency`. Past about 8 the bottleneck is
usually your connection or the drive rather than the tool.

## Privacy and access

The tool signs in as *you*. It can only download what your own Nika Planet
account is already allowed to download, and access is re-checked on every
request — so if your workspace permissions change, an in-progress download stops
too, and the export disappears from your list.

## Support

Full guide: <https://docs.nikaplanet.com/guides/manage-file-lake-per-workspace/large-folder-downloads>

Problems: contact your Nika Planet workspace administrator, or open an issue on
this repository.
