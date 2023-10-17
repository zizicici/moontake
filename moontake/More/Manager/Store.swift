//
//  Store.swift
//  lemon
//
//  Created by Ci Zi on 2023/7/18.
//

import Foundation
import StoreKit

public enum StoreError: Error {
    case failedVerification
}

class Store: ObservableObject {
    static let shared = Store()
    
    @Published private(set) var memberships: [Product]
    
    @Published private(set) var purchasedMemberships: [Product] = [] {
        didSet {
            if purchasedMemberships.count > 0 {
                NotificationCenter.default.post(name: NSNotification.Name.LifetimeMemberShip, object: nil)
            }
        }
    }

    var updateListenerTask: Task<Void, Error>? = nil
    var networkIssueOccurs = false

    init() {
        memberships = []
        
        updateListenerTask = listenForTransactions()
        
        Task {
            await requestProducts()
            
            await updateCustomerProductStatus()
        }
    }
    
    deinit {
        updateListenerTask?.cancel()
    }
    
    func retryRequestProducts() {
        Task {
            await requestProducts()
            
            await updateCustomerProductStatus()
        }
    }
    
    func listenForTransactions() -> Task<Void, Error> {
        return Task.detached {
            //Iterate through any transactions that don't come from a direct call to `purchase()`.
            for await result in Transaction.updates {
                do {
                    let transaction = try self.checkVerified(result)

                    //Deliver products to the user.
                    await self.updateCustomerProductStatus()

                    //Always finish a transaction.
                    await transaction.finish()
                } catch {
                    //StoreKit has a transaction that fails verification. Don't deliver content to the user.
                    print("Transaction failed verification")
                }
            }
        }
    }
    
    func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        //Check whether the JWS passes StoreKit verification.
        switch result {
        case .unverified:
            //StoreKit parses the JWS, but it fails verification.
            throw StoreError.failedVerification
        case .verified(let safe):
            //The result is verified. Return the unwrapped value.
            return safe
        }
    }
    
    @MainActor
    func requestProducts() async {
        do {
            let products = try await Product.products(
                for: [
                    "com.zizicici.moontake.iap.lifetime"
                ]
            )
            
            for product in products {
                switch product.type {
                case .nonConsumable:
                    memberships.append(product)
                default:
                    break
                }
            }
            
            print(memberships)
            networkIssueOccurs = false
        }
        catch {
            if let error = error as? StoreKit.StoreKitError {
                switch error {
                case .networkError:
                    networkIssueOccurs = true
                default:
                    break
                }
            }
            // -1009 Network
            print(error)
        }
    }
    
    func purchase(_ product: Product) async throws -> Transaction? {
        //Begin purchasing the `Product` the user selects.
        let result = try await product.purchase()
        
        switch result {
        case .success(let verification):
            //Check whether the transaction is verified. If it isn't,
            //this function rethrows the verification error.
            let transaction = try checkVerified(verification)

            //The transaction is verified. Deliver content to the user.
            await updateCustomerProductStatus()

            //Always finish a transaction.
            await transaction.finish()

            return transaction
        case .userCancelled, .pending:
            return nil
        default:
            return nil
        }
    }
    
    @MainActor
    func updateCustomerProductStatus() async {
        var purchasedMemberships: [Product] = []

        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)
                switch transaction.productType {
                case .nonConsumable:
                    if let membership = memberships.first(where: { $0.id == transaction.productID }) {
                        purchasedMemberships.append(membership)
                    }
                    break
                default:
                    break
                }
            }
            catch {
                print("updateCustomerProductStatus")
                print(error)
            }
        }
        self.purchasedMemberships = purchasedMemberships
        
        NotificationCenter.default.post(name: NSNotification.Name.StoreInfoLoaded, object: nil)
    }
}

extension Store {
    func purchaseLifetimeMembership() async throws -> Transaction? {
        guard purchasedMemberships.count == 0 else {
            return nil
        }
        if let membership = memberships.first {
            return try await purchase(membership)
        } else {
            return nil
        }
    }
    
    func hasValidMembership() -> Bool {
        return !purchasedMemberships.isEmpty
    }
    
    func isPro() -> Bool {
        return proTier() != .none
    }
    
    func proTier() -> ProTier {
        if hasValidMembership() {
            return .lifetime
        } else {
            return .none
        }
    }
    
    func sync() async {
        //This call displays a system prompt that asks users to authenticate with their App Store credentials.
        //Call this function only in response to an explicit user action, such as tapping a button.
        try? await AppStore.sync()
        await updateCustomerProductStatus()
    }
    
    func membershipDisplayPrice() -> String? {
        return memberships.first?.displayPrice
    }
}
