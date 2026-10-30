#!/bin/sh
# Writes tool/icon/app_icon_1024.png into every iOS, Android and web icon
# slot, flattened to opaque RGB (App Store Connect rejects alpha). macOS only
# (uses sips). Run from the repository root.
set -e
SRC=tool/icon/app_icon_1024.png
TMP=$(mktemp -d)
sips -s format jpeg -s formatOptions 100 "$SRC" --out "$TMP/flat.jpg" >/dev/null
sips -s format png "$TMP/flat.jpg" --out "$TMP/flat.png" >/dev/null

ICONSET=ios/Runner/Assets.xcassets/AppIcon.appiconset
python3 -I - "$ICONSET" <<'PY' > "$TMP/ios_sizes"
import json, sys
d = json.load(open(sys.argv[1] + '/Contents.json'))
seen = set()
for i in d['images']:
    f = i.get('filename')
    if not f or f in seen: continue
    seen.add(f)
    px = round(float(i['size'].split('x')[0]) * int(i['scale'].rstrip('x')))
    print(f, px)
PY
while read -r file px; do
  sips -z "$px" "$px" "$TMP/flat.png" --out "$ICONSET/$file" >/dev/null
done < "$TMP/ios_sizes"

for pair in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
  dir=android/app/src/main/res/mipmap-${pair%%:*}
  [ -d "$dir" ] && sips -z "${pair##*:}" "${pair##*:}" "$TMP/flat.png" --out "$dir/ic_launcher.png" >/dev/null
done

sips -z 192 192 "$TMP/flat.png" --out web/icons/Icon-192.png >/dev/null
sips -z 512 512 "$TMP/flat.png" --out web/icons/Icon-512.png >/dev/null
sips -z 32 32 "$TMP/flat.png" --out web/favicon.png >/dev/null
rm -rf "$TMP"
echo "icons written"
