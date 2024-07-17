//
//  MembershipCell.swift
//  moontake
//
//  Created by Ci Zi on 2023/8/9.
//

import UIKit
import SnapKit

class MembershipCell: UITableViewCell {
    enum DisplayType: Hashable {
        case tier(ProTier)
        case issue
    }
    
    struct DisplayItem: Hashable {
        var type: DisplayType
        var membership: String?
        var subscription: String?
    }
    
    private var firstLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 21, weight: .bold)
        label.textAlignment = .center
        label.textColor = .label
        label.numberOfLines = 1
        label.text = "moontake"
        
        return label
    }()
    
    private var proLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 16, weight: .bold)
        label.textAlignment = .center
        label.textColor = .white
        label.numberOfLines = 1
        label.text = "Pro"
        label.backgroundColor = .systemRed.withAlphaComponent(0.75)
        label.layer.cornerCurve = .continuous
        label.layer.cornerRadius = 6.0
        label.clipsToBounds = true
        
        return label
    }()
    
    private var secondLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 15)
        label.textAlignment = .center
        label.textColor = .label
        label.numberOfLines = 0
        label.text = ""
        
        return label
    }()
    
    private let restoreButton: UIButton = {
        var configuration = UIButton.Configuration.plain()
        configuration.title = String(localized: "membership.restore")
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer({ incoming in
            var outgoing = incoming
            outgoing.font = UIFont.preferredFont(forTextStyle: .footnote)

            return outgoing
        })
        
        let button = UIButton(configuration: configuration)
        button.tintColor = .systemRed
        
        return button
    }()
    
    private let lifetimeButton: UIButton = {
        var configuration = UIButton.Configuration.tinted()
        configuration.title = String(localized: "membership.purchase")
        configuration.titleAlignment = .center
        configuration.cornerStyle = .medium
        configuration.titlePadding = 10.0
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer({ incoming in
            var outgoing = incoming
            outgoing.font = UIFont.preferredFont(forTextStyle: .callout)

            return outgoing
        })
        
        let button = UIButton(configuration: configuration)
        button.tintColor = .systemRed

        return button
    }()
    
    private let dynamicView = UIView()
    
    var lifetimeClosure: (() -> ())?
    var manageClosure: (() -> ())?
    
    var lifetimePrice: String = "" {
        didSet {
            var config = lifetimeButton.configuration
            config?.subtitle = lifetimePrice
            lifetimeButton.configuration = config
        }
    }
    
    private var shouldUpdateContent: Bool = false {
        didSet {
            if shouldUpdateContent {
                if isPurchased {
                    contentToUpdate = String(localized: "hint.wish")
                } else {
                    contentToUpdate = String(localized: "Pro users can unlock all watermarks and have the ability to save the original images.")
                }
            } else {
                if isPurchased {
                    contentToUpdate = String(localized: "Thanks for your support.")
                } else {
                    contentToUpdate = String(localized: "Your support is the biggest motivation for @AppJun to keep creating.")
                }
            }
        }
    }
    
    private var contentToUpdate: String = "" {
        didSet {
            secondLabel.text = contentToUpdate
            if shouldUpdateContent {
                var config = lifetimeButton.configuration
                config?.title = String(localized: "membership.purchase")
                lifetimeButton.configuration = config
            } else {
                var config = lifetimeButton.configuration
                config?.title = String(localized: "Support @AppJun")
                lifetimeButton.configuration = config
            }
        }
    }
    
    private var isPurchased: Bool = false {
        didSet {
            secondLabel.alpha = isPurchased ? 0.62 : 1.0
        }
    }
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        contentView.addSubview(firstLabel)
        firstLabel.snp.makeConstraints { make in
            make.top.equalTo(contentView).inset(20)
            make.centerX.equalTo(contentView).offset(-18)
            make.leading.trailing.greaterThanOrEqualTo(contentView).inset(16).priority(.low)
        }
        
        contentView.addSubview(proLabel)
        proLabel.snp.makeConstraints { make in
            make.centerY.equalTo(firstLabel)
            make.leading.equalTo(firstLabel.snp.trailing).offset(6)
            make.width.equalTo(36)
            make.height.equalTo(25)
        }
        
        contentView.addSubview(secondLabel)
        secondLabel.snp.makeConstraints { make in
            make.top.equalTo(firstLabel.snp.bottom).offset(16)
            make.leading.trailing.equalTo(contentView).inset(16)
        }
        
        contentView.addSubview(dynamicView)
        dynamicView.snp.makeConstraints { make in
            make.top.equalTo(secondLabel.snp.bottom)
            make.bottom.equalTo(contentView)
            make.leading.trailing.equalTo(contentView)
            make.height.greaterThanOrEqualTo(12)
        }
        
        lifetimeButton.addTarget(self, action: #selector(lifetimeAction), for: .touchUpInside)
        restoreButton.addTarget(self, action: #selector(restoreAction), for: .touchUpInside)
        
        let view = UIView()
        selectedBackgroundView = view
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func update(item: DisplayItem) {
        lifetimePrice = item.membership ?? "loading"
        switch item.type {
        case .tier(let tier):
            switch tier {
            case .none:
                dynamicView.subviews.forEach { $0.removeFromSuperview() }
                
                dynamicView.addSubview(lifetimeButton)
                lifetimeButton.snp.makeConstraints { make in
                    make.top.equalTo(dynamicView).inset(20)
                    make.centerX.equalTo(contentView)
                }

                dynamicView.addSubview(restoreButton)
                restoreButton.snp.makeConstraints { make in
                    make.top.equalTo(lifetimeButton.snp.bottom).offset(20)
                    make.centerX.equalTo(contentView)
                    make.bottom.equalTo(dynamicView).inset(12)
                }
                updateRestoreButtonToRestoreButton()
                
                dynamicView.snp.remakeConstraints { make in
                    make.top.equalTo(secondLabel.snp.bottom)
                    make.bottom.equalTo(contentView)
                    make.leading.trailing.equalTo(contentView)
                    make.height.greaterThanOrEqualTo(12)
                }
                
                updateHintLabelForPromotion()
            case .lifetime:
                dynamicView.subviews.forEach { $0.removeFromSuperview() }
                
                dynamicView.snp.remakeConstraints { make in
                    make.top.equalTo(secondLabel.snp.bottom)
                    make.bottom.equalTo(contentView)
                    make.leading.trailing.equalTo(contentView)
                    make.height.greaterThanOrEqualTo(20)
                }
                
                updateHintLabelForThanks()
            }
        case .issue:
            dynamicView.subviews.forEach { $0.removeFromSuperview() }
            
            dynamicView.addSubview(restoreButton)
            restoreButton.snp.makeConstraints { make in
                make.top.equalTo(dynamicView).inset(20)
                make.centerX.equalTo(contentView)
                make.bottom.equalTo(dynamicView).inset(12)
            }
            updateRestoreButtonToRetryButton()
            
            dynamicView.snp.remakeConstraints { make in
                make.top.equalTo(secondLabel.snp.bottom)
                make.bottom.equalTo(contentView)
                make.leading.trailing.equalTo(contentView)
                make.height.greaterThanOrEqualTo(12)
            }
            
            updateHintLabelForPromotion()
        }
    }
    
    private func updateRestoreButtonToRestoreButton() {
        var config = restoreButton.configuration
        config?.title = String(localized: "membership.restore")
        restoreButton.configuration = config
    }
    
    private func updateRestoreButtonToRetryButton() {
        var config = restoreButton.configuration
        config?.title = String(localized: "Tap to Request Store Information")
        restoreButton.configuration = config
    }
    
    private func updateHintLabelForPromotion() {
        isPurchased = false
        togglePromotionText()
    }
    
    private func updateHintLabelForThanks() {
        isPurchased = true
        togglePromotionText()
    }
    
    @objc
    private func lifetimeAction() {
        lifetimeClosure?()
    }
    
    @objc
    private func restoreAction() {
        manageClosure?()
    }
    
    public func togglePromotionText() {
        shouldUpdateContent.toggle()
    }
}
