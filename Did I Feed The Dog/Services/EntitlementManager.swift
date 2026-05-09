import StoreKit
import Observation

@Observable
final class EntitlementManager {
    static let shared = EntitlementManager()
    static let productID = "pro_upgrade"

    private(set) var isPro: Bool = false
    private(set) var product: Product?
    private(set) var purchaseError: String?
    private(set) var isLoading: Bool = false

    private var updatesTask: Task<Void, Never>?

    private init() {
        isPro = AppSettings.isPro
        updatesTask = Task { await listenForTransactions() }
    }

    deinit { updatesTask?.cancel() }

    // Called once at app launch; safe to call multiple times.
    func initialize() async {
        await grantProToExistingPurchasers()
        await checkCurrentEntitlements()
        await loadProduct()
    }

    @MainActor
    func loadProduct() async {
        guard product == nil else { return }
        product = try? await Product.products(for: [Self.productID]).first
    }

    @MainActor
    func purchase(source: String) async {
        isLoading = true
        purchaseError = nil
        defer { isLoading = false }
        do {
            let p: Product
            if let cached = product {
                p = cached
            } else if let fetched = try? await Product.products(for: [Self.productID]).first {
                product = fetched
                p = fetched
            } else {
                purchaseError = "Could not load product."
                return
            }
            let result = try await p.purchase()
            switch result {
            case .success(let verification):
                let transaction = try verification.payloadValue
                grant()
                AppSettings.incrementTelemetry(
                    key: AppSettings.Key.paywallConvertedFromPrefix + source)
                await transaction.finish()
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            purchaseError = "Purchase failed. Please try again."
        }
    }

    @MainActor
    func restore() async {
        isLoading = true
        purchaseError = nil
        defer { isLoading = false }
        do {
            try await AppStore.sync()
            await checkCurrentEntitlements()
            if !isPro { purchaseError = "No previous purchase found." }
        } catch {
            purchaseError = "Restore failed. Please try again."
        }
    }

    // MARK: - Private

    private func grantProToExistingPurchasers() async {
        // Auto-grant Pro to anyone who purchased the original paid app.
        // originalAppVersion < "1.2" means they paid before the freemium pivot.
        guard let result = try? await AppTransaction.shared else { return }
        if case .verified(let appTransaction) = result,
           appTransaction.originalAppVersion.compare("1.2", options: .numeric) == .orderedAscending {
            grant()
        }
    }

    private func checkCurrentEntitlements() async {
        var foundEntitlement = false
        for await verification in Transaction.currentEntitlements {
            if case .verified(let transaction) = verification,
               transaction.productID == Self.productID,
               transaction.revocationDate == nil {
                foundEntitlement = true
                await transaction.finish()
            }
        }
        if foundEntitlement {
            grant()
        } else if !isPro {
            revoke()
        }
    }

    private func listenForTransactions() async {
        for await verification in Transaction.updates {
            if case .verified(let transaction) = verification,
               transaction.productID == Self.productID {
                if transaction.revocationDate == nil { grant() } else { revoke() }
                await transaction.finish()
            }
        }
    }

    private func grant() {
        isPro = true
        AppSettings.isPro = true
    }

    private func revoke() {
        isPro = false
        AppSettings.isPro = false
    }
}
