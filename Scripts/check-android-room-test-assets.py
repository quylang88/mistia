#!/usr/bin/env python3
"""Check the packaged database AndroidTest APK, without claiming device execution."""
import json
import pathlib
import sys
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
SCHEMAS = ROOT / 'android/core/database/schemas/vn.com.quyln.mistia.core.database.MistiaDatabase'
METADATA = ROOT / 'android/core/database/build/outputs/apk/androidTest/debug/output-metadata.json'
if len(sys.argv) > 1:
    apk = pathlib.Path(sys.argv[1])
else:
    metadata = json.loads(METADATA.read_text())
    assert len(metadata['elements']) == 1, 'Expected one database instrumentation APK'
    apk = METADATA.parent / metadata['elements'][0]['outputFile']

with zipfile.ZipFile(apk) as archive:
    entries = set(archive.namelist())
    sources = sorted(SCHEMAS.glob('*.json'))
    assert sources, 'No exported Room schemas'
    missing = [p.name for p in sources if 'assets/' + SCHEMAS.name + '/' + p.name not in entries]
    assert not missing, 'Missing packaged Room migration schemas: ' + ', '.join(missing)
    for source in sources:
        assert json.loads(archive.read('assets/' + SCHEMAS.name + '/' + source.name)) == json.loads(source.read_text()), 'Packaged schema differs: ' + source.name
    catalog = ROOT / 'Mistia/Shared/CoreLogic/MistiaSystemCategories.json'
    assert json.loads(archive.read('assets/MistiaSystemCategories.json')) == json.loads(catalog.read_text()), 'Packaged bootstrap catalog differs'
print(f'Room test APK assets passed ({len(sources)} schemas and bootstrap catalog).')
