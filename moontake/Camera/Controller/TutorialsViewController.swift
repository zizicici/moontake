//
//  TutorialsViewController.swift
//  moontake
//
//  Created by Ci Zi on 2023/8/31.
//

import UIKit
import SnapKit

class TutorialsViewController: UIViewController {
    var textView: UITextView = {
        let textView = UITextView()
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.backgroundColor = .backgroundColor
        textView.isEditable = false
        textView.textContainerInset = UIEdgeInsets(top: 20, left: 16, bottom: 20, right: 16)
        
        return textView
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.title = String(localized: "tutorials.title")
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.largeTitleDisplayMode = .automatic
        let style = NSMutableParagraphStyle()
        style.alignment = .justified
        navigationController?.navigationBar.standardAppearance.largeTitleTextAttributes = [.foregroundColor: UIColor.label.withAlphaComponent(0.8), .paragraphStyle: style]
        navigationController?.navigationBar.tintColor = .systemRed
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: String(localized: "tutorials.close"), style: .plain, target: self, action: #selector(dismissAction))

        view.backgroundColor = .backgroundColor
        
        view.addSubview(textView)
        textView.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide)
            make.bottom.equalTo(view)
            make.leading.trailing.equalTo(view)
        }
        
        setupText()
        
        textView.scrollRangeToVisible(NSRange(location: 0, length: 1))
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        
        setupText()
    }
    
    private func setupText() {
        let text = String(localized: "tutorials.content")

        let attributedString = NSMutableAttributedString(string: text)
        
        // 创建段落样式对象
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 10
        paragraphStyle.paragraphSpacing = 20
        
        let attributes: [NSAttributedString.Key: Any] = [
            .paragraphStyle: paragraphStyle,
            .font: UIFont.systemFont(ofSize: 17),
            .foregroundColor: UIColor.label
        ]
        
        // 将段落样式应用于属性字符串的范围
        attributedString.addAttributes(attributes, range: NSRange(location: 0, length: attributedString.length))
        
        textView.attributedText = attributedString
    }
    
    @objc func dismissAction() {
        dismiss(animated: true)
    }
}
