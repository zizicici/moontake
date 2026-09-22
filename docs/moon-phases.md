# Moon phase calculations

Photo details and photo watermarks both obtain one immutable `MoonManager.Info`
for the photograph's date. The [SkyKit](https://github.com/zizicici/SkyKit) package supplies the Sun–Moon
phase angle and geometric illuminated fraction using DE440 and ERFA. The phase angle identifies waxing and
waning directly; it no longer requires four next-quarter searches per label.

The existing phase-name thresholds and localization keys are preserved. For
presentation, the illuminated fraction is rounded to 0% or 100% within two hours
of an actual new/full Moon. Those events are now searched around the photograph's
own date. The unrounded physical fraction remains available as `illumination`.
This also works for historical photographs and dates across a year boundary,
without waiting for startup initialization or depending on the current year.

`nextOccurrence(of:after:)` searches the next new, first-quarter, full or
last-quarter Moon on demand. There is no annual table or phase cache. The old
Mooninfo Go XCFramework, Chinese-calendar phase table and decompressor have been
removed. The existing calendar/date formatting elsewhere in the app is unchanged.

SkyKit's `Moon` facade uses DE440/ERFA exclusively. The bundled data covers
1850–2149 on every supported system. iOS 26+ loads one Apple-hosted on-demand
pack containing all 2150–2649 coefficients; iOS 15–18 uses only bundled data. Photo details and
watermark preparation await the download off the main thread. Failures display
an unavailable phase instead of a fabricated value or an old-engine result.
See [package coverage and time-data policy](https://github.com/zizicici/SkyKit/blob/main/README.md)
for historical time estimates, future leap assumptions, EOP expiry and sources.

## Verification

- Nine geocentric illumination fixtures from PyEphem 4.2.1, spanning 2000–2040,
  with an absolute fraction tolerance of 0.0002 (0.02 percentage points).
- Eight quarter-event times from the [USNO 2026 table](https://aa.usno.navy.mil/calculated/moon/phases?year=2026),
  allowing two minutes for model differences and reference rounding.
- All eight localized phase names, waxing/waning, two-hour rounding boundaries,
  historical/year-boundary dates and concurrent photo/finder calculations.
- Finder direction retains its independent JPL Horizons regression tests.

App fixtures explicitly assert the DE440 backend and reject unavailable results.
The package tests also cover historical UTC drift, system-version policy, mocked far-date downloads and offline managed-resource loading.
