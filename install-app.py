#!/usr/bin/env python3
"""Install a clean, persistently signed copy of this personal app."""
import pathlib
import plistlib
import subprocess
import sys
import tempfile
import time
import uuid

project = pathlib.Path(__file__).resolve().parent
source = project.parent / 'Docklet.app'
applications = pathlib.Path.home() / 'Applications'
applications.mkdir(exist_ok=True)
target = applications / 'Docklet.app'
if source.is_symlink() and source.resolve() == target.resolve():
    sys.exit('Docklet is already installed. Run package-app.sh first if you want to build an update.')
if target.exists():
    info = plistlib.loads((target / 'Contents/Info.plist').read_bytes())
    if info.get('CFBundleIdentifier') != 'app.personal.docklet':
        sys.exit('A different app already occupies ~/Applications/Docklet.app. It was not changed.')
subprocess.run(['/usr/bin/osascript', '-e', 'if application id "app.personal.docklet" is running then tell application id "app.personal.docklet" to quit'], check=True)
for attempt in range(40):
    if subprocess.run(['/usr/bin/pgrep', '-f', '/Docklet.app/Contents/MacOS/Docklet'], stdout=subprocess.DEVNULL).returncode == 1:
        break
    time.sleep(0.1)
else:
    sys.exit('Docklet is still running. Quit it before installing the update.')
with tempfile.TemporaryDirectory(prefix='.docklet-install-', dir=applications) as temporary:
    staged = pathlib.Path(temporary) / 'Docklet.app'
    subprocess.run(['/usr/bin/ditto', '--norsrc', '--noextattr', str(source), str(staged)], check=True)
    signature = subprocess.run(['/usr/bin/codesign', '-d', '--verbose=4', str(staged)], capture_output=True, text=True)
    if signature.returncode or 'Signature=adhoc' in signature.stderr or 'Authority=' not in signature.stderr:
        subprocess.run([sys.executable, str(project / 'local-signing.py'), str(staged)], check=True)
    else:
        # Keep the persistent personal or developer certificate selected during packaging.
        subprocess.run(['/usr/bin/codesign', '--verify', '--strict', str(staged)], check=True)
    if target.exists():
        backups = pathlib.Path.home() / 'Library/Application Support/Docklet/Previous Builds'
        backups.mkdir(parents=True, exist_ok=True)
        target.rename(backups / f'Docklet-{uuid.uuid4()}.app')
    staged.rename(target)
subprocess.run(['/usr/bin/codesign', '--verify', '--strict', str(target)], check=True)
subprocess.run(['/usr/bin/swift', str(project / 'install-dock-entry.swift'), str(source), str(target)], check=True)
backups = pathlib.Path.home() / 'Library/Application Support/Docklet/Previous Builds'
backups.mkdir(parents=True, exist_ok=True)
source.rename(backups / f'Docklet-workspace-{uuid.uuid4()}.app')
source.symlink_to(target, target_is_directory=True)
print(f'Installed one Docklet app: {target}')
