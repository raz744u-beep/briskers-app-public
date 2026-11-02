"""Apply native local-auth requirements to the generated regular app shell."""
import plistlib
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

root = Path(sys.argv[1])
android = root / 'android/app/src/main'
if android.exists():
    for activity in android.glob('kotlin/**/MainActivity.kt'):
        text = activity.read_text().replace('io.flutter.embedding.android.FlutterActivity',
                                           'io.flutter.embedding.android.FlutterFragmentActivity')
        text = text.replace(': FlutterActivity()', ': FlutterFragmentActivity()')
        activity.write_text(text)
    ns = 'http://schemas.android.com/apk/res/android'
    ET.register_namespace('android', ns)
    manifest = android / 'AndroidManifest.xml'
    tree = ET.parse(manifest)
    document = tree.getroot()
    permission = 'android.permission.USE_BIOMETRIC'
    if not any(item.get(f'{{{ns}}}name') == permission for item in document.findall('uses-permission')):
        ET.SubElement(document, 'uses-permission', {f'{{{ns}}}name': permission})
    app = document.find('application')
    # Secure enrollment must never be restored to another device. Other app
    # preferences and the shop database retain the shell's existing backup policy.
    app.set(f'{{{ns}}}fullBackupContent', '@xml/briskers_backup_rules')
    app.set(f'{{{ns}}}dataExtractionRules', '@xml/briskers_data_extraction_rules')
    tree.write(manifest, encoding='unicode', xml_declaration=True)
    xml = android / 'res/xml'
    xml.mkdir(parents=True, exist_ok=True)
    exclusions = '<exclude domain="sharedpref" path="FlutterSecureStorage.xml"/>'
    (xml / 'briskers_backup_rules.xml').write_text(
        f'<full-backup-content>{exclusions}</full-backup-content>')
    (xml / 'briskers_data_extraction_rules.xml').write_text(
        f'<data-extraction-rules><cloud-backup>{exclusions}</cloud-backup>'
        f'<device-transfer>{exclusions}</device-transfer></data-extraction-rules>')
    for styles in (android / 'res').glob('values*/styles.xml'):
        tree = ET.parse(styles)
        for style in tree.getroot().findall('style'):
            if style.get('name') in ('LaunchTheme', 'NormalTheme'):
                style.set('parent', 'Theme.AppCompat.DayNight.NoActionBar')
        tree.write(styles, encoding='unicode', xml_declaration=True)

ios = root / 'ios/Runner/Info.plist'
if ios.exists():
    with ios.open('rb') as stream:
        config = plistlib.load(stream)
    config['NSFaceIDUsageDescription'] = 'Unlock Owner access to delete Briskers records.'
    with ios.open('wb') as stream:
        plistlib.dump(config, stream)
