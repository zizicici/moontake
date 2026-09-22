# Moon finder

The camera preview's upper-left button toggles an approximate Moon direction guide.
It is available without a Pro membership. The icon-only 44-point button uses the
same plain style, tint, opacity and 6-point inset as the lower preview controls.
An AR-style hollow ring follows the Moon’s estimated position over the live camera.
Off-screen targets show a perimeter arrow; rotate and tilt the phone to bring the
ring to the center. Status information stays at the bottom. The guide passes focus
and zoom gestures through to the preview and can remain open while taking photos.

## Implementation

- SkyKit's `Moon.position` provides the direction: DE440
  coefficients, ERFA IAU 2006/2000A transforms, separate UTC/TT/TDB/UT1, light time,
  solar deflection, aberration, parallax and available IERS Earth-orientation data.
  Core Location's valid WGS84 ellipsoidal height is used (zero if unavailable).
  There is no alternate engine. The HUD uses a standalone implementation of
  NOAA standard atmospheric refraction. Missing resources suppress guidance and
  display an unavailable state.
  Weather-dependent refraction, terrain, buildings, clouds and visibility are not
  predicted. See [package coverage and quality policy](https://github.com/zizicici/SkyKit/blob/main/README.md)
  and [photo phases](moon-phases.md). Expired EOP and unknown future leap seconds
  carry explicit quality metadata; the fixed kernel cannot predict these inputs.
- `MoonGuidance` transforms the north/west/up target vector into device coordinates
  using Core Motion's `xTrueNorthZVertical` attitude. The rear camera points along
  device -Z. Vector projection avoids Euler-angle singularities and handles phone
  roll and the 0°/360° boundary. Targets behind the camera request a turn-around.
- `MoonProjection` uses the active camera format’s horizontal FOV, current zoom
  and preview-layer image rectangle (including letterboxing/cropping) for portrait
  pinhole projection. The ring becomes green within 24 points of image center.
  Markers outside the unobscured preview area become edge arrows. This estimates
  direction, not visual Moon recognition or ARKit world tracking.
- `MoonFinderManager` owns a separate location request from photo geotagging. It
  never changes `Location.manualDisable`. It accepts fresh positions (up to 60 s,
  accuracy within 10 km, including approximate-location permission), updates the
  ephemeris at least every second, and samples fused device motion at 30 Hz.
  Stale location/motion and uncalibrated or low-accuracy magnetic data suppress arrows.
- No magnetic-north fallback is used. Unsupported sensors still allow geographic
  angles to be displayed. Below-horizon positions suppress arrows and stop motion.
- Closing the guide, opening another app page, or entering the background stops
  location and motion updates and invalidates the timer. The camera's existing
  orientation sensor remains separate.
- All 14 app localizations include finder copy and updated privacy descriptions.
  Current-day finding uses bundled data and sends no coordinates to a service.
  Historical/future photo phases can download date-specific coefficients; see the package policy.
- **The device heading, not the ephemeris, is the accuracy floor.** Measured on
  device at Kinmen on 2026-09-22: the computed azimuth tracked Skyfield to three
  decimals in real time (217.47° at 23:00, 221.10° at 23:16), while iOS reported a
  heading 17-19° away from the Moon's true bearing — the same offset in both a flat
  and an upright pose, and growing as the phone turned, which is the signature of
  hard-iron distortion rather than a software bias. On the telephoto lens a 17°
  error is most of the frame. `moon_finder.tracking.detail` and
  `moon_finder.aligned.detail` therefore tell users the ring is a guide and that the
  phone's compass may be off, so a visible mismatch is not read as a phase error.

## References

- [DE440 package sources, provenance and ERFA license](https://github.com/zizicici/SkyKit/blob/main/README.md).
- NASA/JPL [Horizons API](https://ssd-api.jpl.nasa.gov/doc/horizons.html),
  Moon (301), Earth topocentric observer, quantity 4, airless, UTC.
  SkyKit's `scripts/generate-moon-fixtures.py` refreshes 16 independent samples
  in its `Tests/SkyKitTests/Fixtures/`; tests themselves run offline.
- Apple [videoFieldOfView](https://developer.apple.com/documentation/avfoundation/avcapturedevice/format/videofieldofview)
  and [preview coordinate conversion](https://developer.apple.com/documentation/avfoundation/avcapturevideopreviewlayer/layerrectconverted(frommetadataoutputrect:)).
- Apple, [xTrueNorthZVertical](https://developer.apple.com/documentation/coremotion/cmattitudereferenceframe/xtruenorthzvertical)
  and [CMRotationMatrix](https://developer.apple.com/documentation/coremotion/cmrotationmatrix).
- Independent numerical fixtures use [PyEphem](https://rhodesmill.org/pyephem/)
  4.2.1, `Observer.pressure = 0`, `elevation = 0`, and UTC times. Example:

```python
import ephem, math
observer = ephem.Observer()
observer.lat, observer.lon = '1.3521', '103.8198'
observer.date = '2026/09/22 12:00:00'
observer.pressure = 0
observer.elevation = 0
moon = ephem.Moon(observer)
print(math.degrees(moon.az), math.degrees(moon.alt))
# 129.44073179123086, 55.49172164760685
```

The numerical checks live in SkyKit. `MoonPositionTests` checks 14 JPL Horizons
directions within one arcminute of angular separation, plus two exact-pole altitude
comparisons (azimuth is not uniquely defined at a geographic pole). It also checks
seven PyEphem positions within one arcminute per angle. Samples
cover 2020–2035, both hemispheres, near-pole and exact-pole locations, the date line, elevated observers,
a low Moon and below-horizon positions. Refraction is tested separately.
`MoonGuidanceTests` covers camera-axis signs, phone roll, zenith, north wrap, and
projection under zoom and letterboxing. Both use a plain `import SkyKit` so they
also assert the package's public surface is sufficient.

`MoonFinderTests` here keeps what depends on the app: location quality, touch
passthrough, shutdown, the photo-geotag preference, and deterministic HUD
snapshots for on-screen and off-screen targets. UI tests cover the entry point,
denied permission and lifecycle.

## Device QA still required

A simulator cannot validate live compass/gyro accuracy or interference. Outdoors,
compare the guide against a visible Moon, rotate and tilt the phone (including a
90° roll), and check that the arrow converges into a moving ring. Check multiple zoom
factors on both wide and telephoto lenses; the ring is approximate, especially
with magnetic interference or strong zoom. Check calibration near magnetic
accessories and recovery after moving away. Verify location-denied and approximate
location modes, and confirm closing the guide leaves the photo geotag setting intact.
