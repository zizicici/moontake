//
//  ImageCell.swift
//  moontake
//
//  Created by zici on 13/7/24.
//

import UIKit
import SnapKit
import Kingfisher

fileprivate extension UIConfigurationStateCustomKey {
    static let imageInfo = UIConfigurationStateCustomKey("com.zizicici.moontake.cell.imageInfo")
}

extension UICellConfigurationState {
    var imageInfo: ImageInfo? {
        set { self[.imageInfo] = newValue }
        get { return self[.imageInfo] as? ImageInfo }
    }
}

class ImageInfoBaseCell: UICollectionViewCell {
    private var imageInfo: ImageInfo? = nil
    
    func update(with newImageInfo: ImageInfo) {
        guard imageInfo != newImageInfo else { return }
        imageInfo = newImageInfo
        setNeedsUpdateConfiguration()
    }
    
    override var configurationState: UICellConfigurationState {
        var state = super.configurationState
        state.imageInfo = self.imageInfo
        return state
    }
}

class ImageCell: ImageInfoBaseCell {
    var paperView: UIView = {
        let paperView = UIView()
        paperView.backgroundColor = .moonColor.withAlphaComponent(0.83)
        
        return paperView
    }()
    
    var imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        
        return imageView
    }()
    
    private func setupViewsIfNeeded() {
        guard paperView.superview == nil else {
            return
        }
        
        contentView.addSubview(paperView)
        
        contentView.addSubview(imageView)
        imageView.snp.makeConstraints { make in
            make.width.equalTo(100.0).priority(.high)
            make.height.equalTo(210.0).priority(.high)
            make.center.equalTo(contentView)
            make.width.equalTo(contentView).offset(-6)
        }
        
        paperView.snp.makeConstraints { make in
            make.edges.equalTo(imageView).inset(-3)
        }
    }
    
    override func updateConfiguration(using state: UICellConfigurationState) {
        super.updateConfiguration(using: state)
        setupViewsIfNeeded()
        
        if let imageInfo = state.imageInfo {
            if let thumbnailURL = imageInfo.thumbnailURL {
                imageView.kf.setImage(with: thumbnailURL, options: [.loadDiskFileSynchronously])
            }
            let factor = Double(imageInfo.height) / 210.0
            let imageWidth = floor(Double(imageInfo.width) / factor)
            let imageHeight = floor(Double(imageInfo.height) / factor)
            imageView.snp.updateConstraints { make in
                make.width.equalTo(imageWidth).priority(.high)
                make.height.equalTo(imageHeight).priority(.high)
            }
        }
        if state.isHighlighted {
            paperView.backgroundColor = .moonColor
        } else {
            paperView.backgroundColor = .moonColor.withAlphaComponent(0.83)
        }
    }
}
