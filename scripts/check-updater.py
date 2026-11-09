"""Compile the production updater into disposable, signed old/new app bundles."""
from pathlib import Path
import functools
import http.server
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import xml.etree.ElementTree as ET

binary, identity = Path(sys.argv[1]), sys.argv[2]
Path('.local/update-integration').mkdir(parents=True, exist_ok=True)
root = Path(tempfile.mkdtemp(prefix='run.', dir='.local/update-integration')).resolve()
payload = root / 'server'; payload.mkdir()
handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=str(payload))
server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
base = 'http://127.0.0.1:' + str(server.server_port)
framework = next(Path('.build/artifacts/sonoskope/Sparkle').rglob('macos-arm64_x86_64/Sparkle.framework'))
modules = binary / 'Modules'
if not modules.exists(): modules = binary
library = binary / 'libSonoskopeCore.a'
objects = [str(library)] if library.exists() else list(map(str, (binary / 'SonoskopeCore.build').glob('*.o')))
run = functools.partial(subprocess.run, check=True)
exe = root / 'UpdateTest'
run(['xcrun', 'swiftc', '-parse-as-library', '-swift-version', '5', '-target', 'arm64-apple-macos14.2',
     '-I', str(modules), '-F', str(framework.parent), '-framework', 'Sparkle',
     '-Xlinker', '-rpath', '-Xlinker', '@executable_path/../Frameworks',
     'Sources/Sonoskope/SoftwareUpdater.swift', 'Sources/Sonoskope/UpdatePackage.swift',
     'Sources/Sonoskope/VerifiedUpdateServer.swift', 'Tools/UpdateIntegration.swift', *objects, '-o', str(exe)])
with open('App/Info.plist', 'rb') as f: info = plistlib.load(f)
info.update(CFBundleIdentifier='lab.kuraudo.Sonoskope.UpdateTest', CFBundleExecutable='UpdateTest',
            CFBundleName='Sonoskope Update Test', SUFeedURL=base + '/appcast.xml',
            SonoskopeUpdateTest=True, TestDirectory=str(root))
apps = []
for version in ['8', '9']:
    app = root / version / 'SonoskopeUpdateTest.app'
    (app / 'Contents/MacOS').mkdir(parents=True)
    shutil.copy2(exe, app / 'Contents/MacOS/UpdateTest')
    info.update(CFBundleVersion=version, CFBundleShortVersionString='0.0.' + version)
    with (app / 'Contents/Info.plist').open('wb') as f: plistlib.dump(info, f)
    resources = app / 'Contents/Resources'; resources.mkdir()
    for bundle in binary.glob('*.bundle'): shutil.copytree(bundle, resources / bundle.name)
    run(['bash', 'scripts/embed-sparkle.sh', str(app), str(framework), identity])
    run(['codesign', '--force', '--sign', identity, '--options', 'runtime', '--timestamp', str(app)])
    apps.append(app)
archive = payload / 'update.zip'
run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(apps[1]), str(archive)])
signer = framework.parents[2] / 'bin/sign_update'
signature = subprocess.check_output([str(signer), '--account', 'lab.kuraudo.Sonoskope', '-p', str(archive)], text=True).strip()
sparkle = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', sparkle)

def feed(sig):
    rss = ET.Element('rss', version='2.0'); channel = ET.SubElement(rss, 'channel')
    ET.SubElement(channel, 'title').text = 'Disposable updater test'
    item = ET.SubElement(channel, 'item'); ET.SubElement(item, 'title').text = 'Test 9'
    ET.SubElement(item, '{'+sparkle+'}version').text = '9'
    ET.SubElement(item, '{'+sparkle+'}shortVersionString').text = '0.0.9'
    ET.SubElement(item, '{'+sparkle+'}minimumSystemVersion').text = '14.2'
    ET.SubElement(item, 'enclosure', url=base+'/update.zip', length=str(archive.stat().st_size),
                  type='application/octet-stream', attrib={'{'+sparkle+'}edSignature': sig})
    ET.ElementTree(rss).write(payload / 'appcast.xml', encoding='utf-8', xml_declaration=True)

def command(value):
    (root / 'state').unlink(missing_ok=True)
    (root / 'command').write_text(value)
def wait_state(expected, timeout=45):
    deadline = time.monotonic()+timeout
    while time.monotonic() < deadline:
        state = (root / 'state').read_text() if (root / 'state').exists() else ''
        if state.startswith(expected): return state
        if ' failed ' in state and 'failed' not in expected: raise RuntimeError(state)
        time.sleep(0.25)
    raise TimeoutError('Expected '+expected+'; last state: '+state)
def version():
    with (apps[0] / 'Contents/Info.plist').open('rb') as f: return plistlib.load(f)['CFBundleVersion']

process = None
try:
    # Invalid payload signature must fail without replacing the installed app.
    feed('A' * 86 + '==')
    process = subprocess.Popen([str(apps[0] / 'Contents/MacOS/UpdateTest')])
    wait_state('8 failed'); assert version() == '8'
    feed(signature); command('check'); wait_state('8 ready')
    time.sleep(1); assert version() == '8'
    command('quit'); process.wait(timeout=10)
    time.sleep(2); assert version() == '8', 'Normal quit must not install'
    # A fresh process uses the cached verified archive. Remove the server copy
    # after discovery to prove Sparkle receives that cache rather than redownloading.
    (root / 'state').unlink(missing_ok=True)
    process = subprocess.Popen([str(apps[0] / 'Contents/MacOS/UpdateTest')])
    wait_state('8 ready')
    archive.rename(payload / 'offline.zip')
    command('install')
    wait_state('9 current', timeout=60)
    assert version() == '9'
    print('PASS: bad signature rejected; ordinary quit preserved old app; cached signed update installed and relaunched.', flush=True)
    print('Evidence:', root, flush=True)
finally:
    command('quit')
    if process and process.poll() is None:
        try: process.wait(timeout=5)
        except subprocess.TimeoutExpired: process.terminate()
    server.shutdown()
