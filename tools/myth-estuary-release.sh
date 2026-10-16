#!/bin/bash
# Build the Myth Estuary skin (addons/skin.estuary) into an installable zip, with
# its textures packed the way Kodi's own build packs them, and optionally release
# it on GitHub, where the b-pass Kodi repository (b-pass/kodi-repo) picks it up.
#
#   tools/myth-estuary-release.sh            only build build-myth-estuary/<id>-<version>.zip
#   tools/myth-estuary-release.sh --beta     build it and release it as a GitHub pre-release
#   tools/myth-estuary-release.sh --release  build it and release it as a full GitHub release
#
# The version comes from addon.xml; bump it first, Kodi only updates when it goes
# up. Pre-releases only go to the dev repository. A version with a "~" in it
# (4.0.1~beta1) sorts below the plain one in Kodi, so it can only be a beta.
# To promote a beta to a full release later, without a new version:
#   gh release edit skin.myth-estuary-v<version> -R b-pass/xbmc --prerelease=false
#
# Needs kodi-TexturePacker (package kodi-tools-texturepacker) and zip; releasing
# also needs gh, logged in.
set -euo pipefail

repo=b-pass/xbmc
mode=
case "${1-}" in
  '') ;;
  --beta|--release) mode=${1#--} ;;
  *) echo "usage: $0 [--beta|--release]" >&2; exit 2 ;;
esac

root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
skin=$root/addons/skin.estuary
out=$root/build-myth-estuary

texturepacker=${TEXTUREPACKER:-$(command -v kodi-TexturePacker || command -v TexturePacker)} || {
  echo 'TexturePacker not found: install kodi-tools-texturepacker, or set TEXTUREPACKER' >&2
  exit 1
}

read -r id version < <(python3 -c '
import sys, xml.etree.ElementTree as ET
addon = ET.parse(sys.argv[1]).getroot()
print(addon.get("id"), addon.get("version"))' "$skin/addon.xml")
tag=$id-v${version//\~/-}  # git tags can't have a "~"

if [[ $mode == release && $version == *~* ]]; then
  echo "$version sorts below ${version%%~*} in Kodi, so it can only be released with --beta" >&2
  exit 1
fi

# Before building, make sure the release would match what's on GitHub.
if [[ $mode ]]; then
  if [[ $(git -C "$root" status --porcelain -- addons/skin.estuary) ]]; then
    echo 'addons/skin.estuary has uncommitted changes; commit them first' >&2
    exit 1
  fi
  branch=$(git -C "$root" branch --show-current)
  git -C "$root" fetch -q origin "$branch" "+refs/tags/$id-v*:refs/tags/$id-v*"
  if ! git -C "$root" merge-base --is-ancestor HEAD FETCH_HEAD; then
    echo "HEAD isn't on origin/$branch; push it first" >&2
    exit 1
  fi
  if gh release view "$tag" -R "$repo" >/dev/null 2>&1; then
    echo "$tag is already released; bump the version in addon.xml" >&2
    exit 1
  fi
fi

echo "Building $id $version"
stage=$out/$id
rm -rf "$stage"
mkdir -p "$out"
cp -r "$skin" "$stage"
rm -rf "$stage/media" "$stage/themes"
mkdir "$stage/media"
"$texturepacker" -dupecheck -input "$skin/media" -output "$stage/media/Textures.xbt" >"$out/texturepacker.log"
for theme in "$skin"/themes/*/; do
  theme=$(basename "$theme")
  "$texturepacker" -dupecheck -input "$skin/themes/$theme" -output "$stage/media/$theme.xbt" >>"$out/texturepacker.log"
done

zip=$out/$id-$version.zip
rm -f "$zip"
(cd "$out" && zip -qrX "$zip" "$id")
echo "Built $zip"

[[ $mode ]] || exit 0

previous=$(git -C "$root" describe --tags --abbrev=0 --match "$id-v*" HEAD 2>/dev/null) || true
{
  echo "Myth Estuary $version, for Kodi 21 (Omega)."
  echo
  if [[ $previous ]]; then
    echo "Changes since $previous:"
    git -C "$root" log --reverse --format='- %s' "$previous..HEAD" -- addons/skin.estuary
  fi
} >"$out/notes.md"

flags=()
[[ $mode == beta ]] && flags+=(--prerelease)
gh release create "$tag" "$zip" -R "$repo" --target "$(git -C "$root" rev-parse HEAD)" \
  --title "Myth Estuary $version" --notes-file "$out/notes.md" "${flags[@]}"
