//
//  TitleSupplementaryView.swift
//  moontake
//
//  Created by zici on 13/7/24.
//

import UIKit
import SnapKit

class TitleSupplementaryView: UICollectionReusableView {
    let label: UILabel = {
        let label = UILabel()
        label.textColor = .moonColor.withAlphaComponent(0.83)
        label.font = UIFont.preferredFont(forTextStyle: .title3)
        label.adjustsFontForContentSizeCategory = true

        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }
    required init?(coder: NSCoder) {
        fatalError()
    }
}

extension TitleSupplementaryView {
    func configure() {
        addSubview(label)
        label.snp.makeConstraints { make in
            make.top.equalTo(self).inset(16.0)
            make.bottom.equalTo(self).inset(16.0)
            make.leading.equalTo(self).inset(0.0)
            make.trailing.equalTo(self).inset(0.0)
        }
    }
}
