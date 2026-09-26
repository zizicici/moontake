"""Fetch the four public-domain source rasters into a development-only directory.

Usage: python3 fetch-reference-sources.py /tmp/moontake-reference-sources
The roughly 115 MB of original TIFFs must never be placed in the App target.
"""
import hashlib
import json
import pathlib
import sys
import urllib.request

plan = json.loads(pathlib.Path(__file__).with_name('reference-image-plan.json').read_text())
destination = pathlib.Path(sys.argv[1])
destination.mkdir(parents=True, exist_ok=True)
for source in plan['sources'].values():
    path = destination / source['file']
    if not path.exists():
        temporary = path.with_suffix('.download')
        urllib.request.urlretrieve(source['url'], temporary)
        temporary.replace(path)
    data = path.read_bytes()
    if len(data) != source['bytes'] or hashlib.sha256(data).hexdigest() != source['sha256']:
        raise ValueError(f"Source changed or download incomplete: {path}")
    print(f"Verified {path.name}: {len(data):,} bytes")
