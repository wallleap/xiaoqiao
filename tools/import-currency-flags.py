"""Import all pinned flag-icons SVG assets; never execute archive contents."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import re
import tarfile
import urllib.request
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
COMMIT = 'ac7e0eb3259eb62aa6100c435607e2fe03896a97'
ARCHIVE_SHA256 = '6f2d0915213dbc4b15276e89485ab6f8f8b3f441648b10f0ad37dabccea60b28'
URL = f'https://codeload.github.com/lipis/flag-icons/tar.gz/{COMMIT}'
REGIONS = {'CNY':'cn','USD':'us','EUR':'eu','HKD':'hk','JPY':'jp','GBP':'gb','AUD':'au','CAD':'ca',
           'SGD':'sg','KRW':'kr','CHF':'ch','THB':'th','NZD':'nz','MYR':'my','IDR':'id','INR':'in',
           'PHP':'ph','BRL':'br','CZK':'cz','DKK':'dk','HUF':'hu','ILS':'il','ISK':'is','MXN':'mx',
           'NOK':'no','PLN':'pl','RON':'ro','SEK':'se','TRY':'tr','ZAR':'za'}


def expand_eu_references(content):
    """Derive an ArkUI-friendly copy: inline use nodes and make leaf fill explicit."""
    root = ET.fromstring(content)
    references = {node.attrib['id']: node for node in root.iter() if 'id' in node.attrib}
    ns = '{http://www.w3.org/2000/svg}'
    def expand(node, inherited_fill='black', chain=()):
        tag = node.tag.split('}')[-1]
        if tag == 'defs':
            return None
        fill = node.attrib.get('fill', inherited_fill)
        if tag == 'use':
            ref = node.attrib.get('{http://www.w3.org/1999/xlink}href', node.attrib.get('href', ''))
            if not ref.startswith('#') or ref[1:] not in references or ref in chain:
                raise ValueError('Invalid EU flag reference')
            result = ET.Element(ns+'g')
            if 'transform' in node.attrib:
                result.set('transform', node.attrib['transform'])
            target = result
            if 'x' in node.attrib or 'y' in node.attrib:
                target = ET.SubElement(result, ns+'g', {'transform': 'translate('+node.attrib.get('x','0')+' '+node.attrib.get('y','0')+')'})
            target.append(expand(references[ref[1:]], fill, chain+(ref,)))
            return result
        result = ET.Element(node.tag, {key:value for key,value in node.attrib.items() if key not in ('id','fill')})
        if tag == 'path':
            result.set('fill', fill)
        for child in node:
            expanded = expand(child, fill, chain)
            if expanded is not None:
                result.append(expanded)
        return result
    ET.register_namespace('', 'http://www.w3.org/2000/svg')
    return ET.tostring(expand(root), encoding='utf-8', xml_declaration=False)+b'\n'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--archive', type=Path, help='Use an already downloaded archive, without network access.')
    args = parser.parse_args()
    if args.archive:
        raw = args.archive.read_bytes()
    else:
        with urllib.request.urlopen(URL, timeout=60) as response:
            raw = response.read(30 * 1024 * 1024)
    if hashlib.sha256(raw).hexdigest() != ARCHIVE_SHA256:
        raise ValueError('Pinned archive checksum mismatch')
    media = ROOT/'entry/src/main/resources/base/media'
    metadata = ROOT/'tools/currency-flags'
    metadata.mkdir(parents=True, exist_ok=True)
    files = []
    seen = set()
    with tarfile.open(fileobj=io.BytesIO(raw), mode='r:gz') as archive:
        prefix = f'flag-icons-{COMMIT}/'
        for item in archive.getmembers():
            if not item.isfile() or not item.name.startswith(prefix):
                continue
            path = item.name[len(prefix):]
            match = re.fullmatch(r'flags/(1x1|4x3)/([a-z0-9-]+)\.svg', path)
            if match:
                ratio, region = match.groups()
                resource = f'flag_{ratio}_{region.replace("-", "_")}.svg'
                if resource in seen:
                    raise ValueError('Duplicate resource name')
                seen.add(resource)
                content = archive.extractfile(item).read()
                tree = ET.fromstring(content)
                if tree.tag.split('}')[-1] != 'svg':
                    raise ValueError('Not an SVG')
                for node in tree.iter():
                    if node.tag.split('}')[-1] in ('script', 'foreignObject'):
                        raise ValueError('Active SVG content')
                    for key, value in node.attrib.items():
                        if key.startswith('on') or (key.split('}')[-1] == 'href' and not value.startswith('#')):
                            raise ValueError('External/active SVG reference')
                target = media/resource
                # Only replace a previously imported matching asset, never a user-supplied collision.
                if target.exists() and target.read_bytes() != content:
                    raise ValueError(f'Existing resource differs: {resource}')
                target.write_bytes(content)
                files.append({'region':region,'ratio':ratio,'resource':resource[:-4], 'source':path,
                              'bytes':len(content),'sha256':hashlib.sha256(content).hexdigest()})
            elif path == 'LICENSE':
                (metadata/'LICENSE.flag-icons.txt').write_bytes(archive.extractfile(item).read())
            elif path == 'country.json':
                (metadata/'country.json').write_bytes(archive.extractfile(item).read())
    files.sort(key=lambda item: (item['region'],item['ratio']))
    for code, region in REGIONS.items():
        for ratio in ['4x3','1x1']:
            if f'flag_{ratio}_{region}.svg' not in seen:
                raise ValueError(f'Missing flag for {code}')
    manifest = {'source':'https://github.com/lipis/flag-icons','commit':COMMIT,'archive':URL,
                'archiveSha256':ARCHIVE_SHA256,'license':'MIT','currencyRegions':REGIONS,'files':files}
    (metadata/'catalog.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    compatibility = []
    for ratio in ['4x3','1x1']:
        original = media/f'flag_{ratio}_eu.svg'
        content = expand_eu_references(original.read_bytes())
        resource = f'flag_{ratio}_eu_compat'
        (media/(resource+'.svg')).write_bytes(content)
        compatibility.append({'region':'eu','ratio':ratio,'resource':resource,
                              'sourceSha256':hashlib.sha256(original.read_bytes()).hexdigest(),
                              'bytes':len(content),'sha256':hashlib.sha256(content).hexdigest()})
    (metadata/'compatibility.json').write_text(json.dumps(compatibility,indent=2)+'\n')
    generated = '// Generated by tools/import-currency-flags.py; do not edit by hand.\n'
    generated += 'export interface CurrencyFlagAsset { currencyCode: string; regionCode: string; flag: Resource; }\n'
    generated += 'export const CURRENCY_FLAGS: CurrencyFlagAsset[] = [\n'
    generated += ',\n'.join("  { currencyCode: '"+code+"', regionCode: '"+region+"', flag: $r('app.media.flag_4x3_"+region+('_compat' if region == 'eu' else '')+"') }" for code,region in REGIONS.items())+'\n];\n'
    generated += "export function currencyFlag(code: string): Resource { return CURRENCY_FLAGS.find((item: CurrencyFlagAsset) => item.currencyCode === code)?.flag || $r('app.media.lucide_globe1'); }\n"
    countries = json.loads((metadata/'country.json').read_text())
    names = {item['code']: item['name'] for item in countries}
    generated += 'export interface RegionFlag { region: string; name: string; flag: Resource; }\n'
    generated += 'export const REGION_FLAGS: RegionFlag[] = [\n'
    generated += ',\n'.join("  { region: '"+item['region']+"', name: "+json.dumps(names.get(item['region'], item['region']),ensure_ascii=False)+", flag: $r('app.media."+item['resource']+('_compat' if item['region'] == 'eu' else '')+"') }" for item in files if item['ratio'] == '4x3')+'\n];\n'
    generated += "export function regionFlag(region: string): Resource | undefined { return REGION_FLAGS.find((item: RegionFlag) => item.region === region)?.flag; }\n"
    (ROOT/'entry/src/main/ets/presentation/exchange/CurrencyFlags.ets').write_text(generated)
    print(f'Imported {len(files)} SVGs ({len(files)//2} flag/region pairs), mapped {len(REGIONS)} currencies.')


if __name__ == '__main__':
    main()
