#!/bin/sh
# Install only. Home/startup routing is changed AFTER manual launch is verified.
# Input: snapshot name, host app_id, host dll filename (its own app_exec,
# e.g. BixbyPromotion.dll or com.samsung.tv.AccountNudgeService.dll -- read
# it from this TV's own package_app_info, never assumed from another model).
# Stage .local/package.tar.gz as quiet-tizen/package.tar.gz first.
set -eu
test "$(id -u)" = 0
name=${1:?Snapshot name required}
app_id=${2:?Host app_id required}
dll=${3:?Host dll filename required}
case "$name" in ''|*[!A-Za-z0-9_-]*) exit 1;; esac
case "$app_id" in ''|*[!A-Za-z0-9_.-]*) exit 1;; esac
case "$dll" in *.dll) ;; *) echo 'Host dll filename must end in .dll' >&2; exit 1;; esac
case "$dll" in ''|*[!A-Za-z0-9_.-]*) exit 1;; esac
runtimeconfig=${dll%.dll}.runtimeconfig.json
D=/opt/usr/share/quiet-tizen-backups/$name
A=/opt/usr/apps/$app_id
S=/home/owner/share/tmp/sdk_tools/quiet-tizen
test -s "$D/.pkgmgr_parser.db"
test -s "$S/package.tar.gz"
test -s "$A/bin/$dll"
test "$(stat -c %u:%g "$A/bin/$dll")" = 201:0
test ! -e "$D/host-original"
test ! -e "$A/res/quiet-home" # First install only; do not silently overwrite an existing custom launcher.
test ! -e "$S/unpacked"
# The archive is generated from our local build, not downloaded from an unknown party.
mkdir "$S/unpacked"
tar -xzf "$S/package.tar.gz" -C "$S/unpacked"
test -s "$S/unpacked/$dll"
test -s "$S/unpacked/$runtimeconfig"
test -s "$S/unpacked/Probe.dll"
test -s "$S/unpacked/quiet-home/apps.json"
cp -a "$A" "$D/host-original"
cp "$S/unpacked/Probe.dll" "$D/Probe.dll"
/usr/bin/dotnet "$D/Probe.dll" > "$D/operation-and-sources-before.txt"
app_launcher -u 5001 -k "$app_id" || true
if [ -d "$A/bin/.native_image" ]; then mv "$A/bin/.native_image" "$D/home-native-image"; fi
cp "$S/unpacked/$dll" "$A/bin/$dll"
cp "$S/unpacked/$runtimeconfig" "$A/bin/$runtimeconfig"
cp -R "$S/unpacked/quiet-home" "$A/res/"
chown 201:0 "$A/bin/$dll" "$A/bin/$runtimeconfig"
chmod 644 "$A/bin/$dll" "$A/bin/$runtimeconfig"
chsmack -a "User::Pkg::$app_id::RO" "$A/bin/$dll" "$A/bin/$runtimeconfig"
sha256sum "$A/bin/$dll" > "$D/installed-home.sha256"
find "$A/res/quiet-home" -type d -exec chmod 755 {} \;
find "$A/res/quiet-home" -type f -exec chmod 644 {} \;
find "$A/res/quiet-home" -exec chown 201:0 {} \;
find "$A/res/quiet-home" -exec chsmack -a "User::Pkg::$app_id::RO" {} \;
sqlite3 -bail /opt/dbspace/.pkgmgr_parser.db <<SQL
BEGIN IMMEDIATE;
CREATE TEMP TABLE guard(ok INTEGER CHECK(ok=1));
INSERT INTO guard SELECT count(*)=1 FROM package_app_info WHERE app_id='$app_id';
UPDATE package_app_info SET app_disable='false',app_onboot='false',app_autorestart='false' WHERE app_id='$app_id';
DROP TABLE guard;
COMMIT;
SQL
app_launcher -u 5001 -s "$app_id"
echo 'Installed and launch requested. Verify the visible UI, remote, sound, apps and HDMI before changing Home routing.'
echo "Original package and operation/source record: $D"
