//
//  EXIFCell.swift
//  moontake
//
//  Created by zici on 16/7/24.
//

import UIKit
import SnapKit

fileprivate extension UIConfigurationStateCustomKey {
    static let exifInfo = UIConfigurationStateCustomKey("com.zizicici.moontake.cell.exif")
}

extension UICellConfigurationState {
    var exif: EXIF? {
        set { self[.exifInfo] = newValue }
        get { return self[.exifInfo] as? EXIF }
    }
}


class EXIFBaseCell: UICollectionViewCell {
    private var exif: EXIF? = nil
    
    func update(with newEXIF: EXIF) {
        guard exif != newEXIF else { return }
        exif = newEXIF
        setNeedsUpdateConfiguration()
    }
    
    override var configurationState: UICellConfigurationState {
        var state = super.configurationState
        state.exif = self.exif
        return state
    }
}


class EXIFCell: EXIFBaseCell {
    var titleLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.preferredFont(forTextStyle: .footnote)
        label.textAlignment = .center
        label.textColor = .moonColor.withAlphaComponent(0.5625)
        
        return label
    }()
    
    private func setupViewsIfNeeded() {
        guard titleLabel.superview == nil else {
            return
        }
        
        contentView.addSubview(titleLabel)
        titleLabel.setContentHuggingPriority(.required, for: .vertical)
        titleLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        
        titleLabel.snp.makeConstraints { make in
            make.top.leading.trailing.equalTo(contentView).inset(10)
            make.bottom.equalTo(contentView).inset(30)
        }
    }
    
    override func updateConfiguration(using state: UICellConfigurationState) {
        super.updateConfiguration(using: state)
        setupViewsIfNeeded()
        
        if let exifInfo = state.exif, let iso = exifInfo.iso, let fNumber = exifInfo.fNumber, let exposureTime = exifInfo.exposureTime {
            let denominator = Int(1.0 / exposureTime)
            titleLabel.text = String(format: "ISO %d          f/%.1f          1/%ds", iso, fNumber, denominator)
        }
    }
}
