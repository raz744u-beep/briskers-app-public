#!/usr/bin/env bash
set -euo pipefail

baseline=$1
candidate=$2
package=com.briskers.briskers_app
state=/data/user/0/$package
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

printf '%s  %s\n' d23e5d325db3e0470a07ea6b1d43973ea592c5f77246960da4d74d1d6d496342 "$baseline" | sha256sum -c
adb install "$baseline"
adb root
adb wait-for-device
test "$(adb shell id -u | tr -d '\r')" = 0
uid=$(adb shell stat -c %u "$state" | tr -d '\r')
[[ "$uid" =~ ^[0-9]+$ && "$uid" -gt 10000 ]]

python3 - "$tmp/probe.sqlite" <<'PY'
import sqlite3
import sys
with sqlite3.connect(sys.argv[1]) as db:
    db.execute("create table marker(value text not null)")
    db.execute("insert into marker values ('b2565 upgrade retention')")
PY
printf '%s\n' '<map><string name="bootstrap_upgrade_marker">b2565</string></map>' > "$tmp/probe.xml"
adb shell "mkdir -p '$state/databases' '$state/shared_prefs'"
adb push "$tmp/probe.sqlite" "$state/databases/bootstrap_probe.sqlite"
adb push "$tmp/probe.xml" "$state/shared_prefs/bootstrap_probe.xml"
adb shell "chown -R '$uid:$uid' '$state/databases' '$state/shared_prefs'; restorecon -R '$state'"

adb install -r "$candidate"
test "$(adb shell stat -c %u "$state" | tr -d '\r')" = "$uid"
adb shell am force-stop "$package"
adb pull "$state/databases/bootstrap_probe.sqlite" "$tmp/upgraded.sqlite"
adb pull "$state/shared_prefs/bootstrap_probe.xml" "$tmp/upgraded.xml"
cmp "$tmp/probe.xml" "$tmp/upgraded.xml"
python3 - "$tmp/upgraded.sqlite" <<'PY'
import sqlite3
import sys
with sqlite3.connect(sys.argv[1]) as db:
    assert db.execute("select value from marker").fetchall() == [('b2565 upgrade retention',)]
PY
echo "Verified signed b2565 install-over retained the app UID, SQLite data and preferences."
