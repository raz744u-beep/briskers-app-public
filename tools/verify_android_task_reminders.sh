#!/usr/bin/env bash
set -euo pipefail
# Operates only on the isolated CI emulator. The target APK is already installed;
# this test APK is never shipped and never changes the target's database.
apk=$1
request=$2
signing=$3
evidence=$4
sdk=${ANDROID_HOME:-${ANDROID_SDK_ROOT:?Android SDK required}}
build_tools=$(find "$sdk/build-tools" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -1)
platform=$(find "$sdk/platforms" -name android.jar | sort -V | tail -1)
package=$("$build_tools/aapt" dump badging "$apk" | sed -n "s/^package: name='\([^']*\)'.*/\1/p")
[[ "$package" == com.briskers.briskers_app || "$package" == com.example.briskers_app ]]
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$evidence" "$work/classes" "$work/assets" "$work/dex"
cp "$request" "$work/assets/request.json"
cat > "$work/AndroidManifest.xml" <<EOF
<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="com.briskers.reminderprobe">
  <uses-sdk android:minSdkVersion="26" android:targetSdkVersion="35" />
  <application android:label="Briskers CI reminder probe" />
  <instrumentation android:name="com.briskers.reminderprobe.ReminderProbe" android:targetPackage="$package" />
</manifest>
EOF
javac -source 11 -target 11 -classpath "$platform" -d "$work/classes" tools/android_reminder_probe/ReminderProbe.java
"$build_tools/d8" --lib "$platform" --min-api 26 --output "$work/dex" "$work/classes/com/briskers/reminderprobe/ReminderProbe.class"
"$build_tools/aapt" package -f -M "$work/AndroidManifest.xml" -I "$platform" -A "$work/assets" -F "$work/probe.apk"
(cd "$work/dex" && zip -q "$work/probe.apk" classes.dex)
"$build_tools/zipalign" -f 4 "$work/probe.apk" "$work/aligned.apk"
if [[ "$signing" == debug ]]; then
  # AGP/SDK versions can relocate the generated debug keystore. Ask the same
  # Gradle project that built this APK instead of assuming a home directory.
  debug_store=$(cd android && ./gradlew :app:signingReport --console=plain -q | awk '
    /^Variant: / { selected=($0=="Variant: debug") }
    selected && /^Store: / { sub(/^Store: /,""); print; selected=0 }
  ')
  test -f "$debug_store"
  "$build_tools/apksigner" sign --ks "$debug_store" --ks-key-alias androiddebugkey --ks-pass pass:android --key-pass pass:android "$work/aligned.apk"
else
  # Keystore values stay in environment/stdin; never print them or pass passwords
  # on a command line. This uses the existing permanent release identity.
  export BRISKERS_PROBE_STORE_PASS BRISKERS_PROBE_KEY_PASS
  BRISKERS_PROBE_STORE_PASS=$(sed -n 's/^storePassword=//p' "$signing/key.properties")
  BRISKERS_PROBE_KEY_PASS=$(sed -n 's/^keyPassword=//p' "$signing/key.properties")
  alias_name=$(sed -n 's/^keyAlias=//p' "$signing/key.properties")
  "$build_tools/apksigner" sign --ks "$signing/app/briskers-release.jks" --ks-key-alias "$alias_name" --ks-pass env:BRISKERS_PROBE_STORE_PASS --key-pass env:BRISKERS_PROBE_KEY_PASS "$work/aligned.apk"
  unset BRISKERS_PROBE_STORE_PASS BRISKERS_PROBE_KEY_PASS
fi
"$build_tools/aapt" dump resources "$apk" > "$evidence/resources.txt"
grep -F 'drawable/ic_task_reminder' "$evidence/resources.txt"
adb shell svc wifi disable
adb shell svc data disable
adb shell pm grant "$package" android.permission.POST_NOTIFICATIONS
adb shell am force-stop "$package"
adb install -r "$work/aligned.apk"
adb shell am instrument -w com.briskers.reminderprobe/com.briskers.reminderprobe.ReminderProbe | tee "$evidence/notification-probe.txt"
grep -F 'REMINDER_PROBE_PASS' "$evidence/notification-probe.txt"
adb logcat -d -s ScheduledNotifReceiver AndroidRuntime > "$evidence/notification-logcat.txt"
printf 'target=%s\napk_sha256=%s\noffline_wifi_disabled=true\noffline_mobile_data_disabled=true\n' "$package" "$(sha256sum "$apk" | cut -d ' ' -f1)" > "$evidence/notification-identity.txt"
