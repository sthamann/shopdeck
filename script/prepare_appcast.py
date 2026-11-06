#!/usr/bin/env python3
"""Create a signed Sparkle appcast. Does not publish or upload anything."""
import argparse,pathlib,subprocess,xml.etree.ElementTree as E,re,datetime
p=argparse.ArgumentParser();p.add_argument('archive',type=pathlib.Path);p.add_argument('--download-url',required=True);p.add_argument('--key',type=pathlib.Path,required=True);p.add_argument('--output',type=pathlib.Path,required=True);p.add_argument('--notes',default='')
a=p.parse_args()
if not a.download_url.startswith('https://'):p.error('The download URL must use HTTPS.')
root=pathlib.Path(__file__).resolve().parent.parent
version=re.search(r'current = "([^"]+)"',(root/'Sources/ShopdeckCore/AppVersion.swift').read_text()).group(1)
signer=root/'.build/artifacts/sparkle/Sparkle/bin/sign_update'
signature=subprocess.check_output([str(signer),'--ed-key-file',str(a.key),'-p',str(a.archive)],text=True).strip()
subprocess.run([str(signer),'--ed-key-file',str(a.key),'--verify',str(a.archive),signature],check=True,capture_output=True)
ns='http://www.andymatuschak.org/xml-namespaces/sparkle';E.register_namespace('sparkle',ns)
rss=E.Element('rss',version='2.0');channel=E.SubElement(rss,'channel');E.SubElement(channel,'title').text='Shopdeck Updates';item=E.SubElement(channel,'item');E.SubElement(item,'title').text='Shopdeck '+version
E.SubElement(item,'pubDate').text=datetime.datetime.now(datetime.timezone.utc).strftime('%a, %d %b %Y %H:%M:%S +0000')
E.SubElement(item,'description').text=a.notes
E.SubElement(item,'enclosure',{'url':a.download_url,'length':str(a.archive.stat().st_size),'type':'application/octet-stream','{'+ns+'}edSignature':signature,'{'+ns+'}version':str(sum(int(n)*factor for n,factor in zip(version.split('.'),[1000000,1000,1]))),'{'+ns+'}shortVersionString':version})
E.SubElement(item,'{'+ns+'}minimumSystemVersion').text='14.0'
a.output.parent.mkdir(parents=True,exist_ok=True);E.ElementTree(rss).write(a.output,encoding='utf-8',xml_declaration=True)
subprocess.run([str(signer),'--ed-key-file',str(a.key),str(a.output)],check=True,capture_output=True)
print('Signed appcast created. Nothing uploaded.')
