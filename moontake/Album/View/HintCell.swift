//
//  HintCell.swift
//  moontake
//
//  Created by zici on 17/7/24.
//

import UIKit
import SnapKit

enum HintInfo: Hashable {
    case empty(ProTier)
    case normal(ProTier)
    
    var title: String? {
        switch self {
        case .empty:
            return String(localized: "hint.empty")
        case .normal:
            return nil
        }
    }
    
    var subtitle: String? {
        switch self {
        case .empty(let proTier):
            switch proTier {
            case .lifetime:
                return nil
            case .none:
                return String(localized: "hint.promotion")
            }
        case .normal(let proTier):
            switch proTier {
            case .lifetime:
                return String(localized: "hint.wish")
            case .none:
                return String(localized: "hint.promotion")
            }
        }
    }
    
    var shouldShowPurchaseEntry: Bool {
        switch self {
        case .empty(let proTier):
            return proTier != .lifetime
        case .normal(let proTier):
            return proTier != .lifetime
        }
    }
}

fileprivate extension UIConfigurationStateCustomKey {
    static let hintInfo = UIConfigurationStateCustomKey("com.zizicici.moontake.cell.hintInfo")
}

extension UICellConfigurationState {
    var hintInfo: HintInfo? {
        set { self[.hintInfo] = newValue }
        get { return self[.hintInfo] as? HintInfo }
    }
}

class HintBaseCell: UICollectionViewCell {
    private var hintInfo: HintInfo? = nil
    
    func update(with newHintInfo: HintInfo) {
        guard hintInfo != newHintInfo else { return }
        hintInfo = newHintInfo
        setNeedsUpdateConfiguration()
    }
    
    override var configurationState: UICellConfigurationState {
        var state = super.configurationState
        state.hintInfo = self.hintInfo
        return state
    }
}

class HintCell: HintBaseCell {
    var titleLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.preferredFont(forTextStyle: .footnote)
        label.textAlignment = .center
        label.textColor = .moonColor.withAlphaComponent(0.75)
        label.numberOfLines = 0
        
        return label
    }()
    
    var subtitleLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.preferredFont(forTextStyle: .footnote)
        label.textAlignment = .center
        label.textColor = .moonColor.withAlphaComponent(0.75)
        label.numberOfLines = 0
        
        return label
    }()
    
    private let membershipButton: UIButton = {
        var configuration = UIButton.Configuration.tinted()
        
        configuration.image = UIImage(systemName: "arrowshape.up.circle", withConfiguration: UIImage.SymbolConfiguration(textStyle: .footnote))
        configuration.title = String(localized: "membership.learnMore")
        configuration.imagePadding = 9.0
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer({ incoming in
            var outgoing = incoming
            outgoing.font = UIFont.preferredFont(forTextStyle: .callout)

            return outgoing
        })
        configuration.contentInsets = .init(top: 8, leading: 12, bottom: 8, trailing: 12)

        let button = UIButton(configuration: configuration)
        button.tintColor = .moonColor
        button.accessibilityLabel = String(localized: "membership.learnMore")

        return button
    }()
    
    var buttonClosure: (() -> ())?
    
    private func setupViewsIfNeeded() {
        guard titleLabel.superview == nil else {
            return
        }
        
        contentView.addSubview(titleLabel)
        titleLabel.setContentHuggingPriority(.required, for: .vertical)
        titleLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        
        titleLabel.snp.makeConstraints { make in
            make.top.equalTo(contentView).inset(30)
            make.leading.trailing.equalTo(contentView).inset(16)
        }
        
        contentView.addSubview(subtitleLabel)
        subtitleLabel.setContentHuggingPriority(.required, for: .vertical)
        subtitleLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        
        subtitleLabel.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(20)
            make.leading.trailing.equalTo(contentView).inset(16)
        }
        
        contentView.addSubview(membershipButton)
        membershipButton.snp.makeConstraints { make in
            make.top.equalTo(subtitleLabel.snp.bottom).offset(20)
            make.bottom.equalTo(contentView).inset(16)
            make.centerX.equalTo(contentView)
        }
        
        membershipButton.addTarget(self, action: #selector(buttonAction), for: .touchUpInside)
    }
    
    override func updateConfiguration(using state: UICellConfigurationState) {
        super.updateConfiguration(using: state)
        setupViewsIfNeeded()
        
        if let hintInfo = state.hintInfo {
            titleLabel.text = hintInfo.title
            subtitleLabel.text = hintInfo.subtitle
            membershipButton.isHidden = !hintInfo.shouldShowPurchaseEntry
        }
    }
    
    @objc
    func buttonAction() {
        buttonClosure?()
    }
}
