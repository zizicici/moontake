//
//  AppCell.swift
//  moontake
//
//  Created by Ci Zi on 2023/8/10.
//

import UIKit
import SnapKit

class AppCell: UITableViewCell {
    private var icon: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(named: "LemonIcon")
        imageView.layer.cornerCurve = .continuous
        imageView.layer.cornerRadius = 8.0
        imageView.clipsToBounds = true
        
        return imageView
    }()
    
    private var firstLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.preferredFont(forTextStyle: .body)
        label.textAlignment = .natural
        label.textColor = .label
        label.numberOfLines = 1
        label.text = "A Lemon Diary".localized()
        
        return label
    }()
    
    private var secondLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.preferredFont(forTextStyle: .callout)
        label.textAlignment = .natural
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        label.text = "A pure text diary".localized()
        
        return label
    }()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        contentView.addSubview(icon)
        icon.snp.makeConstraints { make in
            make.leading.equalTo(contentView).inset(16)
            make.width.height.equalTo(50)
            make.centerY.equalTo(contentView)
        }
        
        contentView.addSubview(firstLabel)
        firstLabel.snp.makeConstraints { make in
            make.leading.equalTo(icon.snp.trailing).offset(16)
            make.trailing.equalTo(contentView).inset(16)
            make.top.equalTo(contentView).inset(12)
        }
        
        contentView.addSubview(secondLabel)
        secondLabel.snp.makeConstraints { make in
            make.leading.equalTo(icon.snp.trailing).offset(16)
            make.trailing.equalTo(contentView).inset(16)
            make.top.equalTo(firstLabel.snp.bottom).offset(10)
            make.bottom.equalTo(contentView).inset(12)
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
