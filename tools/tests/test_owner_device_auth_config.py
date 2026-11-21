import plistlib
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / 'build/configure_owner_device_auth.py'
ANDROID = '{http://schemas.android.com/apk/res/android}'

class OwnerDeviceAuthConfigTest(unittest.TestCase):
    def test_preserves_package_and_app_settings_and_is_idempotent(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            android = root / 'android/app/src/main'
            kotlin = android / 'kotlin/com/briskers/briskers_app/MainActivity.kt'
            kotlin.parent.mkdir(parents=True)
            kotlin.write_text('package com.briskers.briskers_app\n'
                              'import io.flutter.embedding.android.FlutterActivity\n'
                              'class MainActivity: FlutterActivity() {}')
            (android / 'AndroidManifest.xml').write_text(
                '<manifest xmlns:android="http://schemas.android.com/apk/res/android">'
                '<application android:label="Briskers" android:allowBackup="true">'
                '<activity android:name=".MainActivity"/></application></manifest>')
            styles = android / 'res/values/styles.xml'
            styles.parent.mkdir(parents=True)
            styles.write_text('<resources><style name="LaunchTheme" parent="old">'
                              '<item name="android:windowBackground">@drawable/launch_background</item>'
                              '</style></resources>')
            ios = root / 'ios/Runner/Info.plist'
            ios.parent.mkdir(parents=True)
            with ios.open('wb') as stream:
                plistlib.dump({'CFBundleIdentifier': 'com.briskers.app'}, stream)
            for _ in range(2):
                subprocess.run([sys.executable, str(SCRIPT), str(root)], check=True)
            activity = kotlin.read_text()
            self.assertIn('package com.briskers.briskers_app', activity)
            self.assertIn('FlutterFragmentActivity()', activity)
            manifest = ET.parse(android / 'AndroidManifest.xml').getroot()
            self.assertEqual(len(manifest.findall('uses-permission')), 1)
            self.assertEqual(manifest.find('application').get(ANDROID + 'allowBackup'), 'true')
            self.assertEqual(manifest.find('application').get(ANDROID + 'label'), 'Briskers')
            self.assertEqual(ET.parse(styles).find('.//item').text, '@drawable/launch_background')
            backup = ET.parse(android / 'res/xml/briskers_backup_rules.xml')
            self.assertEqual(backup.find('exclude').get('path'), 'FlutterSecureStorage.xml')
            self.assertEqual(len(backup.findall('exclude')), 1)
            with ios.open('rb') as stream:
                info = plistlib.load(stream)
            self.assertEqual(info['CFBundleIdentifier'], 'com.briskers.app')
            self.assertIn('NSFaceIDUsageDescription', info)

if __name__ == '__main__':
    unittest.main()
