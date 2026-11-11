"""Create and verify a signed Sparkle appcast using Sparkle's pinned signing tool."""
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET
from sparkle_bundle import ROOT, ACCOUNT

NS = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', NS)
SIGN = ROOT / '.build/artifacts/sparkle/Sparkle/bin/sign_update'


def signed_feed(archive, url, version, build, output, key_file=None):
    options = ['--ed-key-file', str(key_file)] if key_file else ['--account', ACCOUNT]

    def tool(*args):
        return subprocess.run([str(SIGN), *options, *args], check=True,
                              text=True, capture_output=True).stdout.strip()

    signature = tool('-p', str(archive))
    tool('--verify', str(archive), signature)
    rss = ET.Element('rss', version='2.0')
    channel = ET.SubElement(rss, 'channel')
    ET.SubElement(channel, 'title').text = 'we-sync'
    ET.SubElement(channel, 'link').text = 'https://github.com/wherexml/wesync/releases'
    item = ET.SubElement(channel, 'item')
    ET.SubElement(item, 'title').text = f'we-sync {version}'
    ET.SubElement(item, f'{{{NS}}}version').text = str(build)
    ET.SubElement(item, f'{{{NS}}}shortVersionString').text = version
    ET.SubElement(item, f'{{{NS}}}minimumSystemVersion').text = '14.0.0'
    ET.SubElement(item, f'{{{NS}}}hardwareRequirements').text = 'arm64'
    ET.SubElement(item, 'enclosure', {
        'url': url, 'length': str(archive.stat().st_size), 'type': 'application/octet-stream',
        f'{{{NS}}}edSignature': signature,
    })
    ET.indent(rss)
    ET.ElementTree(rss).write(output, encoding='utf-8', xml_declaration=True)
    tool(str(output))
    tool('--verify', str(output))
    return signature
