#!/bin/zsh
#
# Publishes the app built by build-release.sh as a GitHub release.
#
#   ./distribution/build-release.sh
#   ./distribution/publish-release.sh
#
# Every release carries the zip under the same file name, so the download link
# in README.md (releases/latest/download/<name>) always serves the newest one.

set -euo pipefail
cd "$(dirname "$0")/.."

REPO="lafluc/MangoAccounting"
BRANCH="main"
BUILD_DIR="build"
APP="$BUILD_DIR/export/MangoAccounting.app"
SOURCE_RECORD="$BUILD_DIR/source-commit"
# Must stay the same across releases: README.md links to it by this name.
ASSET_NAME="MangoAccounting.zip"

die() { print -u2 "$1"; exit 1 }

[[ -d "$APP" && -f "$SOURCE_RECORD" ]] \
  || die "No finished build found. Run ./distribution/build-release.sh first."

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
tag="v$version"

# The published app has to match the code on GitHub: built from a clean tree,
# at the commit that is currently the tip of origin/main.
read -r built_commit built_state < "$SOURCE_RECORD"
[[ "$built_state" == "clean" ]] \
  || die "The build was made with uncommitted changes. Commit them and rebuild."
git fetch --quiet origin "$BRANCH"
remote_commit="$(git rev-parse "origin/$BRANCH")"
[[ "$built_commit" == "$remote_commit" ]] \
  || die "The build is from $built_commit, but origin/$BRANCH is at $remote_commit. Push, then rebuild."

gh release view "$tag" --repo "$REPO" >/dev/null 2>&1 \
  && die "Release $tag already exists. Bump MARKETING_VERSION for a new release."

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
ditto -c -k --keepParent "$APP" "$stage/$ASSET_NAME"

print "Publishing MangoAccounting $version (build $build) as $tag, from $built_commit"
gh release create "$tag" "$stage/$ASSET_NAME" \
  --repo "$REPO" \
  --target "$built_commit" \
  --title "MangoAccounting $version" \
  --notes "Download $ASSET_NAME below. For installation, including the one-time macOS security prompt, see https://github.com/$REPO#download-and-install"

print "\nLatest download: https://github.com/$REPO/releases/latest/download/$ASSET_NAME"
