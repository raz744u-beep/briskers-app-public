"""Wire the folder backup channel into the generated Android application."""
from pathlib import Path
import sys

root = Path(sys.argv[1]) / 'android/app/src/main/kotlin/com/briskers/briskers_app'
activity = root / 'MainActivity.kt'
if '--production-activity' in sys.argv[2:]:
    workflow = Path(__file__).resolve().parents[2] / '.github/workflows/android-debug.yml'
    heredoc = workflow.read_text().split("<<'KOTLIN'\n", 1)[1].split('\n          KOTLIN', 1)[0]
    activity.write_text('\n'.join(line.removeprefix(' ' * 10) for line in heredoc.splitlines()) + '\n')
text = activity.read_text()
if 'private var backupBridge:' not in text:
    marker = 'private val channelName ='
    if marker not in text:
        raise SystemExit('Expected production MainActivity bridge is missing')
    text = text.replace(marker, 'private var backupBridge: BriskersBackupBridge? = null\n              ' + marker, 1)
    text = text.replace('super.configureFlutterEngine(flutterEngine)',
                        'super.configureFlutterEngine(flutterEngine)\n                  backupBridge = BriskersBackupBridge(this, flutterEngine.dartExecutor.binaryMessenger)', 1)
    text = text.replace('super.onActivityResult(requestCode, resultCode, data)',
                        'super.onActivityResult(requestCode, resultCode, data)\n                  if (backupBridge?.onActivityResult(requestCode, resultCode, data) == true) return', 1)
activity.write_text(text)
for filename in ('BriskersBackupBridge.kt', 'BriskersBackupTransfer.kt'):
    (root / filename).write_text((Path(__file__).parent / 'native' / filename).read_text())
