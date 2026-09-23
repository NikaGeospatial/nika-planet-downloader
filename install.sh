#!/usr/bin/env sh
#
# curl -fsSL https://raw.githubusercontent.com/NikaGeospatial/nika-planet-downloader/main/install.sh | sh
#
# Downloads with curl rather than a browser, which matters on macOS: curl does
# not set com.apple.quarantine, so Gatekeeper never gate-checks the binary.
# The release artifacts are Developer ID signed and notarized regardless — this
# path just avoids the first-run prompt entirely.
#
# NOTE: this file is maintained in nika-planet-downloader-internal and synced to
# the root of the public repo by scripts/sync-public-repo.sh. Edit it there.

set -eu

# Releases are published to the public repo; the source lives in the internal
# one. Release assets on a private/internal repo need an authenticated token to
# download, which would defeat a one-line installer.
REPO="NikaGeospatial/nika-planet-downloader"
BIN_NAME="nika-planet-downloader"
INSTALL_DIR="${NIKA_INSTALL_DIR:-$HOME/.local/bin}"

log() { printf '%s\n' "$*" >&2; }
die() { log "error: $*"; exit 1; }

command -v curl >/dev/null 2>&1 || die "curl is required"
command -v tar >/dev/null 2>&1 || die "tar is required"

os="$(uname -s)"
arch="$(uname -m)"

case "$os" in
    Darwin) asset_os="macos-universal" ;;
    Linux)
        case "$arch" in
            x86_64) asset_os="linux-x86_64" ;;
            *) die "unsupported Linux architecture: $arch" ;;
        esac
        ;;
    *) die "unsupported platform: $os (on Windows, download the .exe from the releases page)" ;;
esac

log "Finding the latest release…"
version="${NIKA_VERSION:-}"
if [ -z "$version" ]; then
    version="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
        | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1)"
fi
[ -n "$version" ] || die "could not determine the latest version"

plain_version="${version#v}"
asset="${BIN_NAME}-${plain_version}-${asset_os}.tar.gz"
url="https://github.com/$REPO/releases/download/$version/$asset"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

log "Downloading $asset…"
curl -fsSL "$url" -o "$tmp/$asset" || die "download failed: $url"

# Verify against the published checksums when they are available; a silent
# mismatch is worse than a noisy failure.
if curl -fsSL "https://github.com/$REPO/releases/download/$version/SHA256SUMS.txt" -o "$tmp/SHA256SUMS.txt" 2>/dev/null; then
    expected="$(grep " $asset\$" "$tmp/SHA256SUMS.txt" | awk '{print $1}' || true)"
    if [ -n "$expected" ]; then
        if command -v shasum >/dev/null 2>&1; then
            actual="$(shasum -a 256 "$tmp/$asset" | awk '{print $1}')"
        else
            actual="$(sha256sum "$tmp/$asset" | awk '{print $1}')"
        fi
        [ "$expected" = "$actual" ] || die "checksum mismatch for $asset"
        log "Checksum verified."
    fi
fi

tar -xzf "$tmp/$asset" -C "$tmp"
mkdir -p "$INSTALL_DIR"
mv "$tmp/$BIN_NAME" "$INSTALL_DIR/$BIN_NAME"
chmod +x "$INSTALL_DIR/$BIN_NAME"

log ""
log "Installed $BIN_NAME $version to $INSTALL_DIR"

case ":$PATH:" in
    *":$INSTALL_DIR:"*)
        log "Next: $BIN_NAME login"
        exit 0
        ;;
esac

# ~/.local/bin is on PATH out of the box on most Linux desktops but not on
# macOS, so printing a line to paste meant the install "succeeded" and the very
# next command was `command not found`. Append to the login shell's profile
# once instead, the way rustup and uv do. NIKA_NO_MODIFY_PATH=1 opts out.
path_line="export PATH=\"$INSTALL_DIR:\$PATH\""
profile=""
case "${SHELL##*/}" in
    zsh) profile="${ZDOTDIR:-$HOME}/.zshrc" ;;
    bash)
        # macOS Terminal starts bash as a login shell, which reads
        # .bash_profile and never .bashrc.
        if [ "$os" = Darwin ]; then
            profile="$HOME/.bash_profile"
        else
            profile="$HOME/.bashrc"
        fi
        ;;
    fish)
        profile="$HOME/.config/fish/config.fish"
        path_line="fish_add_path \"$INSTALL_DIR\""
        ;;
esac

log ""
if [ -n "${NIKA_NO_MODIFY_PATH:-}" ] || [ -z "$profile" ]; then
    log "$INSTALL_DIR is not on your PATH. Add this to your shell profile:"
    log "  $path_line"
else
    if ! grep -qsF "$path_line" "$profile"; then
        mkdir -p "$(dirname "$profile")"
        printf '\n# Added by the Nika Planet Downloader installer\n%s\n' "$path_line" >>"$profile"
        log "Added $INSTALL_DIR to your PATH in $profile"
    fi
    # A piped installer runs in a child process, so it cannot change the PATH
    # of the terminal that launched it — only new ones pick the profile up.
    log "Open a new terminal window, then run: $BIN_NAME login"
fi
log "Or use it in this window right away: $INSTALL_DIR/$BIN_NAME login"
