#!/bin/bash
#
# Build the github-tools Slackware package (.txz) for Unraid.
#
# The package bundles the static `gh` binary plus the WebGUI files. It does NOT
# include git — Unraid 7 already ships it. The resulting .txz is what gets
# attached to a GitHub Release and referenced (with its SHA256) by github-tools.plg.
#
# Usage:
#   ./build/make-package.sh [VERSION]
# Env:
#   GH_VERSION   GitHub CLI version to bundle (default below)
#   VERSION      package version (default: today, YYYY.MM.DD). Positional arg wins.
#
# Runs on any Linux with bash, curl, tar(xz) and sha256sum — no Slackware needed
# (a Slackware .txz is just an xz-compressed tarball of the install tree).

set -euo pipefail

GH_VERSION="${GH_VERSION:-2.74.2}"
VERSION="${1:-${VERSION:-$(date +%Y.%m.%d)}}"
ARCH="x86_64"
BUILD="1"
PKGNAME="github-tools"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$REPO_ROOT/src"
DIST="$REPO_ROOT/dist"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$DIST"

TARBALL="gh_${GH_VERSION}_linux_amd64.tar.gz"
BASEURL="https://github.com/cli/cli/releases/download/v${GH_VERSION}"

echo ">> Downloading GitHub CLI ${GH_VERSION}"
curl -fsSL -o "$WORK/$TARBALL"        "$BASEURL/$TARBALL"
curl -fsSL -o "$WORK/checksums.txt"   "$BASEURL/gh_${GH_VERSION}_checksums.txt"

echo ">> Verifying upstream checksum"
expected="$(awk -v f="$TARBALL" '$2==f {print $1}' "$WORK/checksums.txt")"
actual="$(sha256sum "$WORK/$TARBALL" | awk '{print $1}')"
if [ -z "$expected" ]; then echo "!! no checksum for $TARBALL in checksums.txt" >&2; exit 1; fi
if [ "$expected" != "$actual" ]; then
  echo "!! checksum mismatch for $TARBALL" >&2
  echo "   expected $expected" >&2
  echo "   actual   $actual"   >&2
  exit 1
fi

echo ">> Assembling package tree"
tar -C "$WORK" -xzf "$WORK/$TARBALL"
GHDIR="$WORK/gh_${GH_VERSION}_linux_amd64"

PKG="$WORK/pkg"
mkdir -p "$PKG/usr/bin" "$PKG/usr/local/emhttp/plugins" "$PKG/install"
install -m0755 "$GHDIR/bin/gh" "$PKG/usr/bin/gh"
cp -a "$SRC/usr/local/emhttp/plugins/$PKGNAME" "$PKG/usr/local/emhttp/plugins/"

# Normalize perms and strip any CRLF that crept into scripts (CRLF breaks .plg/shell).
find "$PKG/usr/local/emhttp/plugins/$PKGNAME" -type d -exec chmod 0755 {} +
find "$PKG/usr/local/emhttp/plugins/$PKGNAME" -type f -exec chmod 0644 {} +
chmod 0755 "$PKG/usr/local/emhttp/plugins/$PKGNAME/scripts/setup.sh"
find "$PKG/usr/local/emhttp/plugins/$PKGNAME" \( -name '*.sh' -o -name '*.php' -o -name '*.page' \) \
  -exec sed -i 's/\r$//' {} +

cat > "$PKG/install/slack-desc" <<'DESC'
# HOW TO EDIT THIS FILE:
# The "handy ruler" below makes it easier to edit a package description.
# Line up the first '|' above the ':' following the base package name, and
# the '|' on the right side marks the last column you can put a character in.

   |-----handy-ruler------------------------------------------------------|
github-tools: github-tools (git + GitHub CLI for Unraid)
github-tools:
github-tools: Installs the GitHub CLI (gh) and persists git and gh
github-tools: configuration across reboots. git itself ships with Unraid 7.
github-tools:
github-tools: Includes a WebGUI page to set your git identity and to
github-tools: authenticate gh with a GitHub personal access token.
github-tools:
github-tools: Homepage: https://github.com/netarcx/unraid-github-tools
github-tools:
DESC

OUT="$DIST/${PKGNAME}-${VERSION}-${ARCH}-${BUILD}.txz"
echo ">> Building $OUT"
# Deterministic flags (sorted names, fixed mtime/owner) so identical inputs
# produce an identical SHA256 across rebuilds.
( cd "$PKG" && tar --sort=name --mtime='@0' --owner=0 --group=0 --numeric-owner -cJf "$OUT" . )

sha="$(sha256sum "$OUT" | awk '{print $1}')"
echo ""
echo "PACKAGE=$OUT"
echo "VERSION=$VERSION"
echo "GH_VERSION=$GH_VERSION"
echo "SHA256=$sha"
