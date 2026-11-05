#!/usr/bin/env bash
set -euo pipefail

baseline=$1
candidate=$2
package=com.briskers.briskers_app
state=/data/user/0/$package
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

case "$(basename "$baseline")" in
  Briskers-v0.10.9-b2565.apk) expected=d23e5d325db3e0470a07ea6b1d43973ea592c5f77246960da4d74d1d6d496342 ;;
  Briskers-v0.10.9-b2566.apk) expected=62cb4723999c8767a9af128828837d297d0add476c899f7505ebbdde58c174d9 ;;
  Briskers-v0.10.9-b2567.apk) expected=e92e6d3884aac51d579550acbd0cd13713aa9d17381e5b327be6d7cb1eeee952 ;;
  Briskers-v0.10.9-b2568.apk) expected=b2e86c27dbd822127f74d2e75e56c0828bce85dc95efa88d9c19b2e0d1a51a88 ;;
  *) echo "Unknown signed upgrade baseline" >&2; exit 1 ;;
esac
printf '%s  %s\n' "$expected" "$baseline" | sha256sum -c
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
echo "Verified signed install-over retained the app UID, SQLite data and preferences."
