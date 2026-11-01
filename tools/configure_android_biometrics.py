"""Configure generated Flutter Android hosts for local_auth biometrics.

The repository's CI jobs run flutter create, so editing a generated Android
directory on a developer machine would not persist. Keep this transformation
in source control and apply it after generation in every Android workflow.
"""
from pathlib import Path

manifest = Path("android/app/src/main/AndroidManifest.xml")
text = manifest.read_text()
permission = '<uses-permission android:name="android.permission.USE_BIOMETRIC" />'
if permission not in text:
    if "<application" not in text:
        raise SystemExit("Android manifest does not contain application node")
    text = text.replace("<application", permission + "\n    <application", 1)
    manifest.write_text(text)

activities = list(Path("android/app/src/main").rglob("MainActivity.kt"))
if len(activities) != 1:
    raise SystemExit(f"Expected exactly one MainActivity.kt, found {len(activities)}")
activity = activities[0]
original = activity.read_text()
changed = original.replace("FlutterActivity", "FlutterFragmentActivity")
if "FlutterFragmentActivity" not in changed:
    raise SystemExit("Unable to configure FlutterFragmentActivity")
activity.write_text(changed)
print("Configured Android biometric permission and FragmentActivity")
