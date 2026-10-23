import MoreKit

enum ProStatus {
    static let productID = "com.zizicici.moontake.iap.lifetime"
    static let monthlyProductID = "com.zizicici.moontake.subscription.monthly"
    static let yearlyProductID = "com.zizicici.moontake.subscription.yearly"
    static let subscriptionProductIDs = [yearlyProductID, monthlyProductID]
    static let displayProductIDs = [monthlyProductID, yearlyProductID, productID]

    static var isPro: Bool { Store.shared.hasValidMembership() }
}
