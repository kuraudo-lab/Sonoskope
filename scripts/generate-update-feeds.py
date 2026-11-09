"""Generate architecture-specific Sparkle feeds from final, notarized ZIPs.

Run only after packages are final. Publish feeds after immutable release assets
are publicly accessible. Private keys stay in the macOS Keychain.
"""
from pathlib import Path
import datetime
import email.utils
import plistlib
import subprocess
import xml.etree.ElementTree as ET

with open('App/Info.plist', 'rb') as f:
    info = plistlib.load(f)
version, build = info['CFBundleShortVersionString'], info['CFBundleVersion']
signer = Path('.build/artifacts/sonoskope/Sparkle/bin/sign_update')
keygen = signer.with_name('generate_keys')
public_key = subprocess.check_output([str(keygen), '--account', 'lab.kuraudo.Sonoskope', '-p'], text=True).strip()
assert public_key == info['SUPublicEDKey'], 'Keychain signing key does not match the bundled public key'
sparkle = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', sparkle)
destination = Path('updates'); destination.mkdir(exist_ok=True)
for architecture in ['arm64', 'x86_64']:
    archive = Path('dist') / f'Sonoskope-{version}-macos-{architecture}.zip'
    signature = subprocess.check_output([str(signer), '--account', 'lab.kuraudo.Sonoskope', '-p', str(archive)], text=True).strip()
    subprocess.run([str(signer), '--account', 'lab.kuraudo.Sonoskope', '--verify', str(archive), signature], check=True)
    rss = ET.Element('rss', version='2.0'); channel = ET.SubElement(rss, 'channel')
    ET.SubElement(channel, 'title').text = f'Sonoskope updates ({architecture})'
    ET.SubElement(channel, 'link').text = 'https://github.com/kuraudo-lab/Sonoskope/releases'
    item = ET.SubElement(channel, 'item')
    ET.SubElement(item, 'title').text = 'Sonoskope ' + version
    ET.SubElement(item, 'pubDate').text = email.utils.format_datetime(datetime.datetime.now(datetime.timezone.utc))
    ET.SubElement(item, '{'+sparkle+'}version').text = build
    ET.SubElement(item, '{'+sparkle+'}shortVersionString').text = version
    ET.SubElement(item, '{'+sparkle+'}minimumSystemVersion').text = '14.2'
    ET.SubElement(item, 'description').text = 'First-run guide, a compact Overview / Trends / Issues workspace, and signed updates that install only when you choose Install and Relaunch.'
    ET.SubElement(item, 'enclosure', url=f'https://github.com/kuraudo-lab/Sonoskope/releases/download/v{version}/{archive.name}',
                  length=str(archive.stat().st_size), type='application/octet-stream',
                  attrib={'{'+sparkle+'}edSignature': signature})
    ET.indent(rss)
    file = destination / f'appcast-{architecture}.xml'
    ET.ElementTree(rss).write(file, encoding='utf-8', xml_declaration=True)
    print(file)
