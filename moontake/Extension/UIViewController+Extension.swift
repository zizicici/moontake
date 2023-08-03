//
//  UIViewController+Extension.swift
//  moontake
//
//  Created by Ci Zi on 2023/8/3.
//

import UIKit
import SafariServices

extension UIViewController {
    func openSF(with url: URL) {
        let safariViewController = SFSafariViewController(url: url)
        navigationController?.present(safariViewController, animated: true)
    }
}
