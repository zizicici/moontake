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

## Camera moon calendar

The camera's top-right calendar button opens `MoonCalendarViewController` in a
large sheet, using the same sky/moon colors and 44-point entry as the finder.
The sheet contains a selected-day phase, the next full Moon from the current
instant, a browsable Gregorian month and every principal phase event in that
month. Event rows select their date; Today returns to the current month.

`MoonCalendarMonth` groups exact events by the device's local civil date. Normal
days use the local-noon phase for their schematic icon and name. Illumination
shows the local day's starting value → its ending value (the next midnight),
with exactly one decimal place. These endpoints stay in chronological order,
including decreasing illumination during waning; they are not daily extrema.
Calendar day intervals handle 23/25-hour daylight-saving days. The values use
unrounded physical illumination, not the app's 0%/100% presentation window. Principal-phase days show the exact event's name
and schematic angle; the event list retains its precise local time, so an event
near midnight is not lost or mislabeled by the noon sample. A month may include two
full Moons or two occurrences of another quarter. Day arithmetic uses Calendar,
including leap days and daylight-saving transitions. Icons show waxing on the
right and waning on the left; they do not depict local sky orientation.
Months enumerate actual civil-day intervals up to the month boundary. Historical
skipped dates leave empty grid cells, preserving weekday alignment without
introducing a date from the next month.

Calculations and ephemeris preparation run outside the main actor. Changing
months cancels the previous request and discards its result. The previous month
stays visible during calculation and is replaced in one layout pass, preserving
the scroll position. Today reuses the loaded current month. Missing data shows
a retry state while month navigation remains available. Opening the calendar
closes the finder and does not require location, camera or photo permission.
Times refresh after a significant clock/time-zone change or foregrounding.
Changing time zones preserves the browsed year/month and selected civil date;
the new zone's data replaces the previous snapshot. Today never reuses a snapshot
calculated in another time zone. If a selected civil date does not exist in the
new zone, the selection moves to a valid date in the same month.

Non-members can view only the current local month. Month navigation remains
available, while other months' details, grid and events are covered by a frosted
glass overlay with a purchase explanation and an Unlock button. The button opens
the existing MoreKit settings/membership page. Covered content cannot be tapped
or read with VoiceOver; Reduce Transparency uses an opaque cover. Returning to
this month removes the cover only after its snapshot is ready. The next-full-Moon
summary is also hidden when it falls outside this month. Access follows MoreKit's
live purchase/restore state: unlocking reveals the selected month in place, and
revocation covers it without changing the selected month.
