# Moon atlas editorial content

`en.json` is the sole editorial source. Each of the 22 features has a name,
an account of its naming, a distinct scientific or exploration story, and
recognition guidance for the user's photograph. The same source also contains
the atlas controls and reading-source titles.

`research.json` records the claims, supporting evidence, source links and
historical uncertainties. It is development material and is not bundled with
the App. The app ships only the resulting String Catalog and curated source
links alongside its existing feature metadata and reference images.

## Editing and translation

1. Verify new claims against the named references. Distinguish a name's first
   publication from its later IAU adoption. Attribute interpretations and
   preserve scientific qualifications such as “may” and “if.”
2. Edit and review `en.json` before translating. It uses plain language for
   reading on a phone. Avoid repeating the same generic description for each
   lunar sea. Do not infer a specific naming motive merely from a name's meaning.
3. Translate directly from English into all 13 other locales. Review regional
   usage separately for Spanish, Portuguese and Chinese. Use established local
   lunar names and consistent personal names; Latin feature names remain in the
   feature catalog as an additional reference.
4. Check quantities, dates, compass directions, mission names, uncertainty,
   placeholders and natural phrasing against English. App copy does not use
   middle-dot separators. Do not translate a hypothetical origin into a fact.
5. Record the SHA-256 of the exact reviewed English file in each translation's
   `sourceSHA256`. A changed English file invalidates every previous hash. Review
   the change in every locale before updating that locale's hash; never refresh
   hashes mechanically without checking the translations.
6. Publish with `python3 tools/moon-atlas/sync-content.py`, then run the same
   command with `--check`. It validates all key sets, placeholders, source hashes,
   feature sections, references and static Swift localization keys. Unrelated
   Xcode-managed String Catalog entries are preserved.

Locale files: `ar`, `de`, `en`, `es`, `es-419`, `fr`, `ja`, `pt-BR`, `pt-PT`,
`ru`, `uk`, `zh-Hans`, `zh-Hant`, `zh-HK`.

## Historical distinctions retained

- The 1651 map was drawn by Grimaldi and named by Riccioli. The 1935 IAU date in
  many modern records is an adoption date, not the original naming date.
- Beer and Mädler explicitly introduced Mare Australe in *Der Mond* (1837),
  printed pages 390–391. It is not assigned to Riccioli by analogy with other seas.
- Mare Cognitum follows Ranger 7: Kuiper offered two names in 1964, with
  *Mare Cognitum* chosen. Whitaker records the proposal on printed page 51.
- Ranger 7's final-image timing and detail scale follow the contemporary
  NASA/JPL photographic report: 0.18 seconds and about 0.5 meters, rounded in
  the article to about 0.2 seconds and half-meter detail. Do not restore the
  conflicting figures from the later anniversary article or imply that the
  final frame was transmitted in full.
- Wilhelms records proposing *Oceanus Insularum*, later adopted as *Mare
  Insularum* in 1976. His account's incorrect meeting city is not repeated.
- Hevelius's surviving mountain names are traced to his 1647 naming tradition;
  this does not assert that historical maps defined exactly today's boundaries.
- Tycho's approximately 108-million-year age remains conditional on the origin
  of Apollo 17 impact glass, rather than being presented as a direct sample date.

Images have separate provenance in `../reference-image-plan.json` and
`../reference-images.md`. A scientific text citation is not a license to reuse
its webpage's illustrations.
