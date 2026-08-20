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
    *":$INSTALL_DIR:"*) log "Run: $BIN_NAME --help" ;;
    *)
        log ""
        log "$INSTALL_DIR is not on your PATH. Add it:"
        log "  echo 'export PATH=\"$INSTALL_DIR:\$PATH\"' >> ~/.zshrc && exec zsh"
        ;;
esac
