import Foundation
import TipKit
import UIKit

/// Completion is independent of purchase state and camera permissions. Interrupted
/// walkthroughs remain eligible; finishing or explicitly skipping dismisses them.
struct CameraTutorialProgress {
    static let version = 1
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var shouldPresent: Bool {
        defaults.integer(forKey: UserDefaults.Custom.CameraTutorialVersion.rawValue) < Self.version
    }

    func complete() {
        defaults.set(Self.version, forKey: UserDefaults.Custom.CameraTutorialVersion.rawValue)
    }

    var unseenTips: [CameraTutorialStep] {
        let seen = Set(defaults.stringArray(forKey: UserDefaults.Custom.CameraTutorialTips.rawValue) ?? [])
        return CameraTutorialStep.tips.filter { !seen.contains($0.rawValue) }
    }

    func recordTipShown(_ tip: CameraTutorialStep) {
        guard CameraTutorialStep.tips.contains(tip) else { return }
        var seen = Set(defaults.stringArray(forKey: UserDefaults.Custom.CameraTutorialTips.rawValue) ?? [])
        seen.insert(tip.rawValue)
        defaults.set(seen.sorted(), forKey: UserDefaults.Custom.CameraTutorialTips.rawValue)
    }
}

enum CameraTutorialStep: String, CaseIterable {
    case exposure, focus, capture
    case zoom, tapFocus, livePhoto, location, moonFinder, moonCalendar, album, settings

    static let basics: [Self] = [.zoom, .tapFocus, .focus, .exposure, .capture]
    static let tips: [Self] = [.livePhoto, .location, .moonFinder, .moonCalendar, .album, .settings]

    var instruction: String { String(localized: String.LocalizationValue("tutorial.camera." + rawValue)) }

    var symbolName: String {
        switch self {
        case .zoom:
            if #available(iOS 18.0, *) { return "hand.pinch" }
            return "arrow.up.left.and.arrow.down.right"
        case .tapFocus: return "hand.tap"
        case .focus: return "slider.horizontal.below.rectangle"
        case .exposure: return "sun.max"
        case .capture: return "camera.aperture"
        case .livePhoto: return "livephoto"
        case .location: return "mappin.and.ellipse"
        case .moonFinder: return "moon.stars"
        case .moonCalendar: return "calendar"
        case .album: return "photo.on.rectangle"
        case .settings: return "gearshape"
        }
    }
}

@available(iOS 17.0, *)
struct CameraControlTip: Tip {
    // Each requested walkthrough can be replayed without resetting TipKit's
    // global datastore or forgetting which optional features have been shown.
    let id: String
    let step: CameraTutorialStep

    var title: Text { Text(verbatim: step.instruction) }
    var image: Image? {
        if #available(iOS 18.0, *) { return Image(systemName: step.symbolName) }
        // iOS 17 has no TipKit imageStyle property.
        guard let symbol = UIImage(systemName: step.symbolName) else { return nil }
        return Image(uiImage: symbol.withTintColor(.skyColor, renderingMode: .alwaysOriginal))
    }
    var options: [Option] { IgnoresDisplayFrequency(true) }

    @MainActor static let isConfigured: Bool = {
        do {
            try Tips.configure()
            return true
        } catch {
            NSLog("Unable to configure camera tips: %@", String(describing: error))
            return false
        }
    }()
}
