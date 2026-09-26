# Moon recognition regression fixtures

Run `prepare-fixtures.py` (Pillow required), then `node --test registration.test.mjs`
from this directory. The native suite is `moontakeTests/MoonAtlasTests.swift`.
Both use the production `moontake/Moon/MoonAtlasResources/moon-core.js`.

## Image provenance

Fixtures live in `moontakeTests/Fixtures` and are included only in the test bundle.
`example-nasa.jpg` is an independent NASA SVS render for 2026-01-01 00:00 UTC;
its source is linked in [the atlas documentation](../../docs/moon-atlas.md).

The four phone photographs were supplied by the user. They are not NASA assets
or public-domain images. Their prepared fixtures contain no EXIF, location,
device metadata or original filename. They have not been sharpened or repainted.
Original HEIC files are not stored in the repository or shipped with the App.

| Fixture | UTC capture time | Illumination | Preparation |
| --- | --- | --- | --- |
| `soft-full-moon.png` | 2026-06-30 16:26:09 | 99.47% | 128 × 128 moon crop |
| `soft-gibbous-moon-may.png` | 2026-05-25 11:31:40 | 70.52% | 128 × 128 moon crop |
| `soft-gibbous-moon-september.png` | 2026-09-21 10:33:03 | 73.67% | 128 × 128 moon crop |
| `daylight-moon.jpg` | 2026-04-28 10:08:35 | 89.65% | 1102 × 1468 sky and clouds, footer removed, JPEG quality 94 |

Preparation starts with the same ImageIO orientation handling and maximum
1600-pixel preview as the App. Each date has a fixed SkyKit geometry JSON here.
The originals were also checked through native HEIC loading, EXIF date precedence,
recognition, zoom, annotations and reference overlay before removing the temporary
test files. Scores are engineering correlations, not recognition probabilities.

## Regressions these images protect

- **Soft full Moon:** fine-texture-only matching discarded useful broad maria
  outlines. Compare both broad structure and fine texture at the same alignment,
  refine all four competing roll candidates equally, then check their separation.
  Per-component limb thresholds keep halos and white footers from distorting the
  fitted radius. Do not replace these checks with a lower detail threshold.
- **Gibbous Moons:** the existing multiscale matcher recognizes both photos.
  Check fit, wrong-mirror rejection and hiding unlit features. Do not require a
  complete illuminated circle or lower thresholds for these examples.
- **Daylight Moon:** a global brightness threshold merged the Moon into bright
  sky and produced no candidate. When the initial candidate is absent or too
  small, remove the local sky background for limb detection only. Registration
  and displayed photos retain the original pixels. Removing the Moon with a
  neighboring sky patch must leave clouds that cannot pass registration.

The 21 Node checks cover these fixtures and transformed variants, the independent
NASA render, synthetic phases, blank/overexposed/small inputs and
60 unrelated textured discs. The 13 native tests also cover image loading,
visibility, transitions, gestures, label layout, reference assets and articles.
This is regression coverage, not a measured recognition rate. Thin crescents,
cloud cover, blur and very small moons still need broader real-photo validation.
