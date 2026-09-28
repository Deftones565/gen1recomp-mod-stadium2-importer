#!/bin/sh
# Build the release ZIP from the committed tree, with the Stadium-2-UI
# submodule (ui/) included: git archive leaves submodules out.
#
#   sh tools/build_release.sh [out.zip]
#
# Excluded, as in earlier releases: tests/, install-local.sh, .gitignore,
# baseroms/.gitkeep (never a ROM), and from ui/ its tests and standalone
# entry files (main.lua, manifest.json): only its lib/, assets/ and README
# are part of this mod.
set -eu
mod_root=$(cd "$(dirname "$0")/.." && pwd)
cd "$mod_root"
version=$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' manifest.json | head -n 1)
out=${1:-"$mod_root/build/STADIUM2_IMPORTER-$version.zip"}
case "$out" in /*) ;; *) out="$PWD/$out" ;; esac
[ -f ui/lib/embed.lua ] || { echo "ERROR: ui/ submodule missing; run: git submodule update --init" >&2; exit 2; }
if ! git -C ui diff --quiet HEAD || ! git diff --quiet HEAD -- ui; then
  echo "ERROR: ui/ has changes not committed to the pinned submodule commit" >&2; exit 2
fi
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
git ls-tree -r --name-only HEAD | grep -v -e '^tests/' -e '^install-local\.sh$' \
  -e '^\.gitignore$' -e '^\.gitmodules$' -e '^baseroms/\.gitkeep$' -e '^ui$' > "$stage/files"
git archive --format=tar HEAD $(cat "$stage/files") | tar -x -C "$stage"
mkdir -p "$stage/ui"
git -C ui archive --format=tar HEAD lib assets README.md | tar -x -C "$stage/ui"
rm -f "$stage/files"
mkdir -p "$(dirname "$out")"
rm -f "$out"
(cd "$stage" && zip -qr -X "$out" .)
echo "$out"
