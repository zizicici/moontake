//
//  FocusView.swift
//  moontake
//
//  Created by Ci Zi on 2023/7/27.
//

import UIKit

class FocusView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        layer.borderColor = UIColor.moonColor.cgColor
        layer.borderWidth = 1.0
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
