#!/bin/sh
# SNAPSHOT_NAME HOST_APP_ID HOST_DLL ORIGINAL_MAIN_OPERATION_APP ORIGINAL_HOME_APP ORIGINAL_STARTUP_APP
# HOST_DLL must be the exact filename passed to install-launcher.sh for this
# snapshot. Read all three original IDs from that TV's saved records; do not
# guess them.
set -eu
test "$(id -u)" = 0
name=${1:?}; app_id=${2:?}; dll=${3:?}; operation=${4:?}; home=${5:?}; startup=${6:?}
case "$name" in ''|*[!A-Za-z0-9_-]*) exit 1;; esac
for app in "$app_id" "$operation" "$home" "$startup"; do
    case "$app" in ''|*[!A-Za-z0-9_.-]*) exit 1;; esac
done
case "$dll" in *.dll) ;; *) echo 'Host dll filename must end in .dll' >&2; exit 1;; esac
case "$dll" in ''|*[!A-Za-z0-9_.-]*) exit 1;; esac
D=/opt/usr/share/quiet-tizen-backups/$name
A=/opt/usr/apps/$app_id
test -s "$D/Probe.dll"
test -d "$D/host-original/bin"
test -s "$D/.pkgmgr_parser.db"
sha256sum -c "$D/installed-home.sha256"
test -s "$D/host-original/bin/$dll"
runtimeconfig=${dll%.dll}.runtimeconfig.json
/usr/bin/dotnet "$D/Probe.dll" set-home "$operation"
vconftool set -f -t string db/appfw/home_appid "$home"
vconftool set -f -t string db/appfw/startup_appid "$startup"
app_launcher -u 5001 -k "$app_id" || true
cp -a "$D/host-original/bin/$dll" "$A/bin/$dll"
chsmack -a "User::Pkg::$app_id::RO" "$A/bin/$dll"
if [ -s "$D/host-original/bin/$runtimeconfig" ]; then
    cp -a "$D/host-original/bin/$runtimeconfig" "$A/bin/$runtimeconfig"
    chsmack -a "User::Pkg::$app_id::RO" "$A/bin/$runtimeconfig"
fi
if [ -d "$D/home-native-image" ]; then
    test ! -e "$A/bin/.native_image"
    cp -a "$D/home-native-image" "$A/bin/.native_image"
fi
sqlite3 -bail /opt/dbspace/.pkgmgr_parser.db <<SQL
ATTACH '$D/.pkgmgr_parser.db' AS before;
BEGIN IMMEDIATE;
CREATE TEMP TABLE guard(ok INTEGER CHECK(ok=1));
INSERT INTO guard SELECT count(*)=1 FROM before.package_app_info WHERE app_id='$app_id';
INSERT INTO guard SELECT count(*)=1 FROM package_app_info WHERE app_id='$app_id';
UPDATE package_app_info SET
app_disable=(SELECT app_disable FROM before.package_app_info WHERE app_id='$app_id'),
app_onboot=(SELECT app_onboot FROM before.package_app_info WHERE app_id='$app_id'),
app_autorestart=(SELECT app_autorestart FROM before.package_app_info WHERE app_id='$app_id')
WHERE app_id='$app_id';
DROP TABLE guard;
COMMIT;
SQL
app_launcher -u 5001 -s "$home"
echo 'Original launcher routing and assembly restored. Extra Quiet Home resources remain inert for recovery.'
