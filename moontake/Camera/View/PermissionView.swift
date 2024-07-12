//
//  PermissionView.swift
//  moontake
//
//  Created by Ci Zi on 2023/8/9.
//

import UIKit
import SnapKit

class PermissionView: UIView {
    private let cameraButton: UIButton = {
        var configuration = UIButton.Configuration.filled()
        configuration.image = UIImage(systemName: "camera")?.withTintColor(.moonColor, renderingMode: .alwaysOriginal)
        configuration.imagePadding = 12.0
        configuration.title = String(localized: "Enable Camera Permission")
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer({ incoming in
            var outgoing = incoming
            outgoing.font = UIFont.systemFont(ofSize: 16)
            outgoing.foregroundColor = UIColor.moonColor

            return outgoing
        })
        configuration.subtitle = String(localized: "permission.camera.subtitle")
        configuration.subtitleTextAttributesTransformer = UIConfigurationTextAttributesTransformer({ incoming in
            var outgoing = incoming
            outgoing.font = UIFont.systemFont(ofSize: 12)
            outgoing.foregroundColor = UIColor.moonColor.withAlphaComponent(0.9)

            return outgoing
        })
        configuration.cornerStyle = .large
        configuration.titlePadding = 10.0
        configuration.contentInsets = .init(top: 14, leading: 18, bottom: 14, trailing: 18)
        
        let button = UIButton(configuration: configuration)
        button.tintColor = .skyColor
        
        return button
    }()
    
    private let albumButton: UIButton = {
        var configuration = UIButton.Configuration.filled()
        configuration.image = UIImage(systemName: "photo.on.rectangle")?.withTintColor(.moonColor, renderingMode: .alwaysOriginal)
        configuration.imagePadding = 12.0
        configuration.title = String(localized: "Enable Add Photo Permission")
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer({ incoming in
            var outgoing = incoming
            outgoing.font = UIFont.systemFont(ofSize: 16)
            outgoing.foregroundColor = UIColor.moonColor

            return outgoing
        })
        configuration.subtitle = String(localized: "permission.addPhoto.subtitle")
        configuration.subtitleTextAttributesTransformer = UIConfigurationTextAttributesTransformer({ incoming in
            var outgoing = incoming
            outgoing.font = UIFont.systemFont(ofSize: 12)
            outgoing.foregroundColor = UIColor.moonColor.withAlphaComponent(0.9)

            return outgoing
        })
        configuration.cornerStyle = .large
        configuration.titlePadding = 10.0
        configuration.contentInsets = .init(top: 14, leading: 18, bottom: 14, trailing: 18)
        
        let button = UIButton(configuration: configuration)
        button.tintColor = .skyColor
        
        return button
    }()
    
    private let stackView: UIStackView = {
        var stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 40.0
        stackView.alignment = .center
        
        return stackView
    }()
    
    var cameraClosure: (() -> ())? = nil
    
    var albumClosure: (() -> ())? = nil
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        backgroundColor = .moonColor.withAlphaComponent(0.5)
        
        addSubview(stackView)
        stackView.snp.makeConstraints { make in
            make.centerX.centerY.equalTo(self)
            make.leading.greaterThanOrEqualTo(self)
            make.top.greaterThanOrEqualTo(self)
        }
        
        cameraButton.addTarget(self, action: #selector(cameraAction), for: .touchUpInside)
        albumButton.addTarget(self, action: #selector(albumAction), for: .touchUpInside)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func update(showCameraButton: Bool, showAlbumButton: Bool) {
        [cameraButton, albumButton].forEach { button in
            button.removeFromSuperview()
        }
        if showCameraButton {
            stackView.addArrangedSubview(cameraButton)
        }
        if showAlbumButton {
            stackView.addArrangedSubview(albumButton)
        }
    }
    
    @objc
    private func cameraAction() {
        cameraClosure?()
    }
    
    @objc
    private func albumAction() {
        albumClosure?()
    }
}
