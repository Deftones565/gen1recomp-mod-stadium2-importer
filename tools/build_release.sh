#!/bin/sh
# Build the release ZIP from the committed tree.
#
#   sh tools/build_release.sh [out.zip]
#
# Excluded, as in earlier releases: tests/, install-local.sh, .gitignore,
# baseroms/.gitkeep (never a ROM). The Stadium UI is not in this ZIP: it is
# the STADIUM2_UI mod, a dependency the game offers to install.
set -eu
mod_root=$(cd "$(dirname "$0")/.." && pwd)
cd "$mod_root"
version=$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' manifest.json | head -n 1)
out=${1:-"$mod_root/build/STADIUM2_IMPORTER-$version.zip"}
case "$out" in /*) ;; *) out="$PWD/$out" ;; esac
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
git ls-tree -r --name-only HEAD | grep -v -e '^tests/' -e '^install-local\.sh$' \
  -e '^\.gitignore$' -e '^baseroms/\.gitkeep$' > "$stage/files"
git archive --format=tar HEAD $(cat "$stage/files") | tar -x -C "$stage"
rm -f "$stage/files"
mkdir -p "$(dirname "$out")"
rm -f "$out"
(cd "$stage" && zip -qr -X "$out" .)
echo "$out"
