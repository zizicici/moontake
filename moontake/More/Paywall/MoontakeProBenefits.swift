import UIKit
import MoreKit

enum MoontakeProFeature: String, CaseIterable {
    case originals, calendar, album, albumSaving

    var comparison: MoontakePaywallConfiguration.Feature {
        let title: String
        let free: String
        let pro: String
        let explanation: String
        switch self {
        case .originals:
            title = String(localized: "paywall.benefit.watermarkFree")
            free = "—"
            pro = String(localized: "paywall.included")
            explanation = String(localized: "paywall.info.originals")
        case .album:
            title = String(localized: "paywall.benefit.album")
            free = String(localized: "paywall.benefit.latest_photos")
            pro = String(localized: "paywall.benefit.allPhotos")
            explanation = String(localized: "paywall.info.album")
        case .calendar:
            title = String(localized: "paywall.benefit.calendar")
            free = String(localized: "paywall.benefit.current_month")
            pro = String(localized: "paywall.benefit.any_month")
            explanation = String(localized: "paywall.info.calendar")
        case .albumSaving:
            title = String(localized: "paywall.benefit.autoSave")
            free = String(localized: "paywall.benefit.alwaysOn")
            pro = String(localized: "paywall.benefit.canDisable")
            explanation = String(localized: "paywall.info.albumSaving")
        }
        return .init(title: title, freeValue: free, proValue: pro, id: rawValue,
                     explanation: explanation, isSubfeature: self == .albumSaving)
    }

    var upgradeMessage: String { comparison.explanation }
}

enum MoontakeProBenefits {
    static let title = "moontake Pro"
    static var features: [MoontakePaywallConfiguration.Feature] { MoontakeProFeature.allCases.map(\.comparison) }
}

extension UIViewController {
    func presentMoontakePaywall(highlighting feature: MoontakeProFeature? = nil) {
        guard presentedViewController == nil else { return }
        view.endEditing(true)
        let paywall = MoontakePaywallViewController(configuration: .init(
            title: MoontakeProBenefits.title,
            features: MoontakeProBenefits.features,
            productIDs: ProStatus.displayProductIDs,
            privacyPolicyURL: URL(string: "https://zizicici.medium.com/policy-of-privacy-for-moontake-afc746183ab7")!,
            highlightedFeature: feature
        ))
        paywall.modalPresentationStyle = .fullScreen
        paywall.onMembershipActivated = { [weak paywall] in
            paywall?.dismiss(animated: ConsideringUser.animated)
        }
        present(paywall, animated: ConsideringUser.animated)
    }
}
