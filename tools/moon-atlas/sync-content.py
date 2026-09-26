"""Validate and publish the atlas's English-first editorial content.

Run with --check to verify the checked-in App resources without changing them.
The authoritative English copy is content/en.json; translations are compared
with its SHA-256, preventing silently retaining an older version of a story.
Research claims and their supporting evidence stay outside the App bundle.
"""
import argparse
import hashlib
import json
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent
APP = ROOT.parents[1] / 'moontake'
LANGUAGES = ['ar', 'de', 'en', 'es', 'es-419', 'fr', 'ja', 'pt-BR', 'pt-PT',
             'ru', 'uk', 'zh-Hans', 'zh-Hant', 'zh-HK']


def load(path):
    return json.loads(path.read_text())


def write_catalog(path, catalog):
    """Preserve unrelated Xcode-managed entries byte for byte."""
    raw = path.read_text()
    start = raw.index('{', raw.index('"strings"'))
    decoder = json.JSONDecoder()
    _, end = decoder.raw_decode(raw, start)
    cursor = start + 1
    blocks = {}
    while True:
        while raw[cursor].isspace() or raw[cursor] == ',':
            cursor += 1
        if raw[cursor] == '}':
            break
        key_start = cursor
        key, cursor = decoder.raw_decode(raw, cursor)
        while raw[cursor].isspace() or raw[cursor] == ':':
            cursor += 1
        _, cursor = decoder.raw_decode(raw, cursor)
        if not key.startswith('atlas.'):
            blocks[key] = '    ' + raw[key_start:cursor]
    for key, value in catalog['strings'].items():
        if key.startswith('atlas.'):
            lines = json.dumps({key: value}, ensure_ascii=False, indent=2,
                               separators=(',', ' : ')).splitlines()[1:-1]
            blocks[key] = '\n'.join('  ' + line for line in lines)
    updated = raw[:start + 1] + '\n' + ',\n'.join(blocks[key] for key in sorted(blocks)) + '\n  }' + raw[end:]
    assert json.loads(updated) == catalog
    path.write_text(updated)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    english_path = ROOT / 'content/en.json'
    english = load(english_path)
    assert english['sourceLanguage'] == 'en'
    original = english['strings']
    digest = hashlib.sha256(english_path.read_bytes()).hexdigest()
    translations = {'en': original}
    for language in LANGUAGES:
        if language == 'en':
            continue
        translated = load(ROOT / f'content/{language}.json')
        assert translated['language'] == language
        assert translated['sourceLanguage'] == 'en'
        assert translated['sourceSHA256'] == digest, f'{language}: English source changed; review required'
        assert set(translated['strings']) == set(original), f'{language}: missing or extra translation keys'
        translations[language] = translated['strings']
    for language, strings in translations.items():
        for key, value in strings.items():
            assert isinstance(value, str) and value.strip(), f'{language}/{key}: empty text'
            assert not any(mark in value for mark in ['·', '•', '・']), f'{language}/{key}: unwanted separator'
            assert value.count('%@') == original[key].count('%@'), f'{language}/{key}: changed placeholder'
            if language != 'en' and re.fullmatch(r'atlas\.feature\.\d+\.(naming|story|observation)', key):
                assert value != original[key], f'{language}/{key}: untranslated English article'
    catalog_path = APP / 'Localizable.xcstrings'
    catalog = load(catalog_path)
    # Keep every unrelated translation and its ordering intact.
    for key in list(catalog['strings']):
        if key.startswith('atlas.') and key not in original:
            assert not args.check, f'Obsolete App content: {key}'
            del catalog['strings'][key]
    for key, value in original.items():
        entry = {'extractionState': 'manual', 'localizations': {
            language: {'stringUnit': {'state': 'translated', 'value': translations[language][key]}}
            for language in LANGUAGES
        }}
        if args.check:
            assert catalog['strings'].get(key) == entry, f'App catalog does not match reviewed content: {key}'
        else:
            catalog['strings'][key] = entry
    features = load(APP / 'Moon/MoonAtlasResources/assets/features.json')
    evidence = load(ROOT / 'content/research.json')
    research = {item['id']: item for item in evidence['features']}
    assert set(research) == {feature['id'] for feature in features}
    for feature in features:
        prefix = f'atlas.feature.{feature["id"]}'
        for section in ['label', 'naming', 'story', 'observation']:
            assert f'{prefix}.{section}' in original
        assert research[feature['id']]['claims'], f'{prefix}: missing supporting evidence'
        assert feature['readingSources'], f'{prefix}: no reader references'
        for reference in feature['readingSources']:
            assert reference['titleKey'] in original
            assert reference['url'].startswith('https://')
    for path in APP.rglob('*.swift'):
        for key in re.findall(r'String\(localized: "(atlas\.[^"]+)"', path.read_text()):
            assert key in original, f'{path.name}: missing English source key {key}'
    if not args.check:
        write_catalog(catalog_path, catalog)
    print(f'Validated {len(features)} articles and {len(original)} strings in {len(LANGUAGES)} languages.')


if __name__ == '__main__':
    main()
