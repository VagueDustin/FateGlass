#!/usr/bin/env bash
# Builds the FateGlass app for Apple Silicon: ~/Library/Caches/FateGlass-build/FateGlass.app
#
#   bash source/__assets/mac/fateglass/build-fateglass.sh [--install] [--dmg] [--version 10.0.7]
#
#   --install   copies the app into /Applications and registers it with Launch Services
#   --dmg       also makes the download: __artifacts/bundle/FateGlass_<version>_osx-arm64.dmg
#   --version   app version (10.0.7 or 10.0.7.1200) instead of IgVersion in Directory.Build.props
#
# Signs ad hoc, which is all a build made and run on this Mac needs. To sign for other Macs, set
# SIGN_IDENTITY to a "Developer ID Application: ..." identity (notarizing is a separate step).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$(cd "$HERE/../../.." && pwd)"
PUBLISH_DIR="$SRC/__artifacts/publish/fateglass-osx-arm64"
# outside the repo: iCloud Drive re-tags any .app under ~/Documents with Finder info, which codesign refuses
APP_DIR="${FATEGLASS_APP_DIR:-$HOME/Library/Caches/FateGlass-build/FateGlass.app}"
CONTENTS_DIR="$APP_DIR/Contents"
INSTALL_DIR="/Applications/FateGlass.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
INSTALL=false
DMG=false
VERSION=""
while [[ $# -gt 0 ]]; do
	case "$1" in
		--install) INSTALL=true ;;
		--dmg) DMG=true ;;
		--version) VERSION="${2:-}"; shift ;;
		*) echo "Error: unknown option $1" >&2; exit 1 ;;
	esac
	shift
done

read_prop() { sed -n "s:.*<$1>\(.*\)</$1>.*:\1:p" "$SRC/Directory.Build.props" | head -n 1; }
if [[ -n "$VERSION" ]]; then
	[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || { echo "Error: version '$VERSION' must look like 10.0.7 or 10.0.7.1200" >&2; exit 1; }
	IG_VERSION="$VERSION"
	IG_SHORT_VERSION="$(cut -d. -f1-3 <<< "$VERSION")"
	IG_BUILD="$(cut -d. -f4 <<< "$VERSION")"
	[[ -n "$IG_BUILD" ]] || IG_BUILD="$IG_SHORT_VERSION"
else
	IG_VERSION="$(read_prop IgVersion)"
	IG_SHORT_VERSION="$(read_prop IgBundleShortVersion)"
	IG_BUILD="$(read_prop IgBundleBuild)"
	[[ -n "$IG_SHORT_VERSION" ]] || IG_SHORT_VERSION="${IG_VERSION%.*}"
	[[ -n "$IG_BUILD" ]] || IG_BUILD="${IG_VERSION##*.}"
fi

echo "==> FateGlass $IG_VERSION (osx-arm64, signing: $([[ "$SIGN_IDENTITY" == "-" ]] && echo "ad hoc" || echo "$SIGN_IDENTITY"))"

# 1. publish: one Native AOT executable plus the native libraries it loads
rm -rf "$PUBLISH_DIR"
dotnet publish "$SRC/ImageGlass.Mac/ImageGlass.Mac.csproj" -c Release -r osx-arm64 -p:Platform=ARM64 \
	"-p:IgVersion=$IG_VERSION" -o "$PUBLISH_DIR"

# 2. bundle: the publish output, minus debug symbols, plus the Info.plist and app icon
rm -rf "$APP_DIR"
mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"
cp -R "$PUBLISH_DIR/." "$CONTENTS_DIR/MacOS/"
rm -rf "$CONTENTS_DIR/MacOS/"*.dSYM
find "$CONTENTS_DIR/MacOS" \( -name '*.pdb' -o -name '.DS_Store' -o -name '._*' \) -delete

sed -e "s/\${IG_SHORT_VERSION}/$IG_SHORT_VERSION/g" -e "s/\${IG_BUILD}/$IG_BUILD/g" \
	"$HERE/Info.plist" > "$CONTENTS_DIR/Info.plist"
cp "$HERE/FateGlass.icns" "$CONTENTS_DIR/Resources/"

# 3. payload: themes, languages and transitions (not the Windows-only _ext_icons), and the shared default settings
for item in "$SRC/__assets/__app/"* "$SRC/__assets/win/fateglass/igconfig.default.json"; do
	[[ "$(basename "$item")" == "_ext_icons" ]] && continue
	cp -R "$item" "$CONTENTS_DIR/MacOS/"
done

# the Mac build keeps the toolbar and gallery in full screen by default
DEFAULTS_FILE="$CONTENTS_DIR/MacOS/igconfig.default.json"
sed -i '' -E 's/("Show(Toolbar|Gallery)InFullscreen": *)false/\1true/' "$DEFAULTS_FILE"
if [[ "$(grep -c -E '"Show(Toolbar|Gallery)InFullscreen": *true' "$DEFAULTS_FILE")" != 2 ]]; then
	echo "Error: could not turn on the full screen toolbar and gallery in $DEFAULTS_FILE" >&2
	exit 1
fi

# codesign accepts only Mach-O files in Contents/MacOS, so data moves to Resources and is linked back for BaseDir()
for item in "$CONTENTS_DIR/MacOS/"*; do
	[[ -L "$item" ]] && continue
	if [[ -d "$item" ]] || ! file -b "$item" | grep -q '^Mach-O'; then
		mv "$item" "$CONTENTS_DIR/Resources/"
		ln -s "../Resources/$(basename "$item")" "$item"
	fi
done

# 4. sign inside out: every native library, then the app
if [[ "$SIGN_IDENTITY" == "-" ]]; then
	lib_args=(--force --sign -)
	app_args=(--force --sign -)
else
	lib_args=(--force --timestamp --options runtime --sign "$SIGN_IDENTITY")
	app_args=("${lib_args[@]}" --entitlements "$SRC/__assets/mac/ImageGlass.entitlements")
fi
xattr -cr "$APP_DIR"
find "$CONTENTS_DIR/MacOS" -type f -name '*.dylib' -exec codesign "${lib_args[@]}" {} \;
codesign "${app_args[@]}" "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
echo "==> $APP_DIR"

# 5. disk image: the app beside an Applications shortcut to drag it onto
if $DMG; then
	DMG_PATH="$SRC/__artifacts/bundle/FateGlass_${IG_VERSION}_osx-arm64.dmg"
	STAGE_DIR="$(mktemp -d)"
	ditto "$APP_DIR" "$STAGE_DIR/FateGlass.app"
	ln -s /Applications "$STAGE_DIR/Applications"
	mkdir -p "$(dirname "$DMG_PATH")"

	# hdiutil now and then fails with "Resource busy" on hosted runners
	for attempt in 1 2 3; do
		hdiutil create -volname FateGlass -srcfolder "$STAGE_DIR" -format UDZO -ov "$DMG_PATH" && break
		[[ $attempt -lt 3 ]] || exit 1
		sleep 5
	done
	rm -rf "$STAGE_DIR"
	echo "==> $DMG_PATH"
fi

# 6. install: replace the copy in /Applications, and forget this build copy so Finder offers only the installed one
if $INSTALL; then
	rm -rf "$INSTALL_DIR"
	ditto "$APP_DIR" "$INSTALL_DIR"
	"$LSREGISTER" -f "$INSTALL_DIR"
	# fails with -10814 when the build copy was never opened, so there is nothing to forget
	"$LSREGISTER" -u "$APP_DIR" 2>/dev/null || true
	echo "==> Installed $INSTALL_DIR"
fi
