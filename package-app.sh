#!/bin/zsh
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$(dirname "$PROJECT_DIR")/Docklet.app"
STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/docklet-package.XXXXXX")"
trap 'rm -rf "$STAGE_DIR"' EXIT
cd "$PROJECT_DIR"
swift build -c release
.build/release/Docklet --generate-icons "$STAGE_DIR/artwork"
mkdir -p "$STAGE_DIR/manager.iconset"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$STAGE_DIR/artwork/manager.png" --out "$STAGE_DIR/manager.iconset/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$STAGE_DIR/artwork/manager.png" --out "$STAGE_DIR/manager.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$STAGE_DIR/manager.iconset" -o "$STAGE_DIR/AppIcon.icns"
python3 - "$PROJECT_DIR" "$STAGE_DIR" <<'PY'
import pathlib, plistlib, shutil, sys
project, stage = map(pathlib.Path, sys.argv[1:])
contents = stage / 'Docklet.app/Contents'
(contents / 'MacOS').mkdir(parents=True)
(contents / 'Resources').mkdir()
shutil.copy2(project / '.build/release/Docklet', contents / 'MacOS/Docklet')
shutil.copy2(stage / 'AppIcon.icns', contents / 'Resources/AppIcon.icns')
info = {
    'CFBundleExecutable': 'Docklet', 'CFBundleIdentifier': 'app.personal.docklet',
    'CFBundleName': 'Docklet', 'CFBundleDisplayName': 'Docklet', 'CFBundlePackageType': 'APPL',
    'CFBundleShortVersionString': '0.5.1', 'CFBundleVersion': '10', 'CFBundleIconFile': 'AppIcon',
    'LSMinimumSystemVersion': '14.0', 'NSHighResolutionCapable': True, 'NSPrincipalClass': 'NSApplication',
    'NSAppleEventsUsageDescription': 'Docklet reads track details and sends playback controls only to the music app you select.',
    'NSCalendarsFullAccessUsageDescription': 'Docklet uses calendar access only when you connect Calendar.',
    'NSRemindersFullAccessUsageDescription': 'Docklet uses reminders access only when you connect Reminders.'
}
info['CFBundleURLTypes'] = [{'CFBundleURLName': 'Docklet Widgets', 'CFBundleURLSchemes': ['docklet']}]
with (contents / 'Info.plist').open('wb') as f: plistlib.dump(info, f)
PY
xattr -cr "$STAGE_DIR/Docklet.app"
if [[ -n "${DOCKLET_SIGN_IDENTITY:-}" ]]; then
    codesign --force --sign "$DOCKLET_SIGN_IDENTITY" "$STAGE_DIR/Docklet.app"
else
    python3 "$PROJECT_DIR/local-signing.py" "$STAGE_DIR/Docklet.app"
fi
rm -rf "$APP_DIR"
mv "$STAGE_DIR/Docklet.app" "$APP_DIR"
printf 'Created single app: %s\n' "$APP_DIR"
