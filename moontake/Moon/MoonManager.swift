import Foundation
import SkyKit

final class MoonManager {
    static let shared = MoonManager()

    enum Phase {
        case newMoon, waxingMoon, fullMoon, waningMoon
    }

    enum Quarter: Double {
        case newMoon = 0, firstQuarter = 90, fullMoon = 180, lastQuarter = 270
    }

    struct Info {
        /// Sun–Moon ecliptic longitude difference: 0=new, 180=full.
        let angle: Double
        /// Physical illuminated fraction, before the app's presentation rounding.
        let illumination: Double
        /// Preserve the existing 0%/100% display within two hours of new/full Moon.
        let displayIllumination: Double

        var phase: Phase {
            // Preserve the app's existing phase-name windows. The phase angle
            // replaces four searches for the next quarter to determine waxing/waning.
            switch angle {
            case ..<90: return displayIllumination < 0.025 ? .newMoon : .waxingMoon
            case ..<180: return displayIllumination > 0.9975 ? .fullMoon : .waxingMoon
            case ..<270: return displayIllumination > 0.975 ? .fullMoon : .waningMoon
            default: return .waningMoon
            }
        }

        var name: String {
            switch phase {
            case .newMoon: return String(localized: "moon.phase.new")
            case .fullMoon: return String(localized: "moon.phase.full")
            case .waxingMoon:
                if displayIllumination < 0.49 { return String(localized: "moon.phase.waxing.crescent") }
                if displayIllumination < 0.51 { return String(localized: "moon.phase.waxing.first_quarter") }
                return String(localized: "moon.phase.waxing.gibbous")
            case .waningMoon:
                if displayIllumination < 0.49 { return String(localized: "moon.phase.waning.crescent") }
                if displayIllumination < 0.51 { return String(localized: "moon.phase.waning.last_quarter") }
                return String(localized: "moon.phase.waning.gibbous")
            }
        }
    }

    /// Computes one immutable result for both the label and percentage. No yearly
    /// table, initialization task or shared mutable phase cache is required.
    func info(at date: Date) -> Info? {
        guard let result = Moon.phase(at: date) else { return nil }
        let illumination = result.illumination
        var display = illumination
        if illumination < 0.025 || illumination > 0.975 {
            let target = illumination < 0.025 ? 0.0 : 180.0
            let start = date.addingTimeInterval(-2 * 3600)
            if let event = Moon.nextQuarter(target, onOrAfter: start, limitDays: 4.0 / 24),
               abs(event.timeIntervalSince(date)) < 2 * 3600 {
                display = target == 0 ? 0 : 1
            }
        }
        return Info(angle: result.angle, illumination: illumination, displayIllumination: display)
    }

    func prepare(at date: Date) async {
        _ = try? await Ephemeris.ensureAvailable(at: date)
    }

    func nextOccurrence(of quarter: Quarter, after date: Date) -> Date? {
        Moon.nextQuarter(quarter.rawValue, onOrAfter: date)
    }
}
