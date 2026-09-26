"""Decode the NASA assets and metadata-free phone crops for the dependency-free Node registration tests.

Requires Pillow. No network access. The reference render is independent of our renderer.
"""
import json
import pathlib
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent
RESOURCES = ROOT.parents[1] / 'moontake' / 'Moon' / 'MoonAtlasResources'
OUTPUT = ROOT / 'output'
OUTPUT.mkdir(exist_ok=True)
sources = {
    'example-nasa': ROOT.parents[1] / 'moontakeTests' / 'Fixtures' / 'example-nasa.jpg',
    'soft-full-moon': ROOT.parents[1] / 'moontakeTests' / 'Fixtures' / 'soft-full-moon.png',
    'soft-gibbous-moon-may': ROOT.parents[1] / 'moontakeTests' / 'Fixtures' / 'soft-gibbous-moon-may.png',
    'soft-gibbous-moon-september': ROOT.parents[1] / 'moontakeTests' / 'Fixtures' / 'soft-gibbous-moon-september.png',
    'daylight-moon': ROOT.parents[1] / 'moontakeTests' / 'Fixtures' / 'daylight-moon.jpg',
    'moon-color': RESOURCES / 'assets' / 'moon-color.jpg',
}
for name, source in sources.items():
    image = Image.open(source).convert('RGBA')
    (OUTPUT / (name + '.rgba')).write_bytes(image.tobytes())
    (OUTPUT / (name + '-size.json')).write_text(json.dumps([image.width, image.height]))
