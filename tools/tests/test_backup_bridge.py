import pathlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]

class BackupBridgeTest(unittest.TestCase):
    def test_production_shell_wiring_and_idempotence(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = pathlib.Path(tmp) / 'android/app/src/main/kotlin/com/briskers/briskers_app'
            folder.mkdir(parents=True)
            activity = folder / 'MainActivity.kt'
            script=ROOT/'tools/build/configure_backup_bridge.py'
            subprocess.run(['python3', str(script), tmp, '--production-activity'], check=True)
            first=activity.read_text()
            subprocess.run(['python3',str(script),tmp],check=True)
            self.assertEqual(first,activity.read_text())
            self.assertIn('backupBridge = BriskersBackupBridge',first)
            self.assertIn('backupBridge?.onActivityResult',first)
            self.assertIn('com.briskers/expenseiq',first)
            self.assertIn('com.briskers/pdf',first)
            self.assertTrue((folder / 'BriskersBackupBridge.kt').exists())
            self.assertTrue((folder / 'BriskersBackupTransfer.kt').exists())

if __name__=='__main__': unittest.main()
