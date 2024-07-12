//
//  UIColor+Extension.swift
//  moontake
//
//  Created by Ci Zi on 2023/7/8.
//


import UIKit

extension UIColor {
    static let backgroundColor: UIColor = UIColor(named: "BackgroundColor") ?? UIColor.systemBackground
    static let moonColor: UIColor = UIColor(named: "MoonColor") ?? UIColor.white
    static let skyColor: UIColor = UIColor(named: "SkyColor") ?? UIColor.black
}

class ColorHighlightButton: UIButton {
    var highlightedColor: UIColor?
    var normalColor: UIColor? {
        didSet {
            backgroundColor = normalColor
        }
    }
    
    override var isHighlighted: Bool {
        didSet {
            backgroundColor = isHighlighted ? highlightedColor : normalColor
        }
    }
}
