import pathlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]

class BackupBridgeTest(unittest.TestCase):
    def test_production_shell_wiring_and_idempotence(self):
        text = (ROOT / '.github/workflows/android-debug.yml').read_text()
        kotlin = text.split("<<'KOTLIN'",1)[1].split('\n          KOTLIN',1)[0]
        kotlin = '\n'.join(line[10:] if line.startswith(' '*10) else line for line in kotlin.splitlines())
        with tempfile.TemporaryDirectory() as tmp:
            folder = pathlib.Path(tmp) / 'android/app/src/main/kotlin/com/briskers/briskers_app'
            folder.mkdir(parents=True)
            activity=folder/'MainActivity.kt'; activity.write_text(kotlin)
            script=ROOT/'tools/build/configure_backup_bridge.py'
            subprocess.run(['python3',str(script),tmp],check=True)
            first=activity.read_text()
            subprocess.run(['python3',str(script),tmp],check=True)
            self.assertEqual(first,activity.read_text())
            self.assertIn('backupBridge = BriskersBackupBridge',first)
            self.assertIn('backupBridge?.onActivityResult',first)
            self.assertIn('com.briskers/expenseiq',first)
            self.assertIn('com.briskers/pdf',first)
            self.assertTrue((folder/'BriskersBackupBridge.kt').exists())

if __name__=='__main__': unittest.main()
