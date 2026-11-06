// 7-day free trial, then a Lemon Squeezy license key unlocks the app.
// Uses the public License API (no secret key in the app): activate once per Mac, re-validate on launch.
import AppKit
import Foundation

enum LicenseConfig {
    // Lemon Squeezy store "thehueflow" (Settings → Stores) and the Hueflow product.
    static let storeID = 516112
    static let productID = 1503830
    static let checkoutURL = URL(string: "https://thehueflow.lemonsqueezy.com/checkout/buy/b38c690e-405f-427a-a3df-5589af32b819")!
    static let trialDays = 7
}

@MainActor
final class License: ObservableObject {
    enum State: Equatable { case trial(daysLeft: Int), licensed, expired }

    @Published private(set) var state: State = .expired
    var onChange: () -> Void = {}
    var isUnlocked: Bool { state != .expired }

    // shortcut: trial start and key live in UserDefaults, so deleting the prefs restarts the trial;
    // move them to the Keychain if trial resets become a real problem.
    private let defaults = UserDefaults.standard
    private var key: String? { defaults.string(forKey: "licenseKey") }
    private var instanceID: String? { defaults.string(forKey: "licenseInstance") }

    init() {
        if defaults.object(forKey: "trialStart") == nil { defaults.set(Date(), forKey: "trialStart") }
        refresh()
        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }
        if let key, let instanceID { Task { await revalidate(key: key, instance: instanceID) } }
    }

    private func refresh() {
        let old = state
        if key != nil && instanceID != nil {
            state = .licensed
        } else {
            let start = defaults.object(forKey: "trialStart") as? Date ?? Date()
            let left = LicenseConfig.trialDays - Int(Date().timeIntervalSince(start) / 86400)
            state = left > 0 ? .trial(daysLeft: left) : .expired
        }
        if state != old { onChange() }
    }

    struct APIError: LocalizedError { let errorDescription: String? }

    private struct Response: Decodable {
        struct Instance: Decodable { let id: String }
        struct Meta: Decodable { let store_id: Int; let product_id: Int }
        let activated: Bool?
        let valid: Bool?
        let error: String?
        let instance: Instance?
        let meta: Meta?
    }

    private func call(_ endpoint: String, _ fields: [String: String]) async throws -> Response {
        var req = URLRequest(url: URL(string: "https://api.lemonsqueezy.com/v1/licenses/\(endpoint)")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        req.httpBody = form.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONDecoder().decode(Response.self, from: data)
    }

    /// A key from another Lemon Squeezy store/product must not unlock Hueflow.
    private func ours(_ r: Response) -> Bool {
        r.meta?.store_id == LicenseConfig.storeID && r.meta?.product_id == LicenseConfig.productID
    }

    func activate(_ rawKey: String) async throws {
        // Keys are uppercase hex UUIDs, so a typed letter O can only mean zero.
        let k = rawKey.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().replacingOccurrences(of: "O", with: "0")
        guard !k.isEmpty else { throw APIError(errorDescription: "Enter a license key") }
        let r = try await call("activate", ["license_key": k, "instance_name": Host.current().localizedName ?? "Mac"])
        guard r.activated == true, let id = r.instance?.id else { throw APIError(errorDescription: r.error ?? "Invalid license key") }
        guard ours(r) else {
            _ = try? await call("deactivate", ["license_key": k, "instance_id": id])
            throw APIError(errorDescription: "This license key isn't for Hueflow")
        }
        defaults.set(k, forKey: "licenseKey")
        defaults.set(id, forKey: "licenseInstance")
        refresh()
    }

    func deactivate() async {
        if let key, let instanceID { _ = try? await call("deactivate", ["license_key": key, "instance_id": instanceID]) }
        defaults.removeObject(forKey: "licenseKey")
        defaults.removeObject(forKey: "licenseInstance")
        refresh()
    }

    /// Offline or server errors keep the license; only an explicit "not valid" (refunded, disabled, deactivated) removes it.
    private func revalidate(key: String, instance: String) async {
        guard let r = try? await call("validate", ["license_key": key, "instance_id": instance]) else { return }
        if r.valid == false || (r.valid == true && !ours(r)) {
            defaults.removeObject(forKey: "licenseKey")
            defaults.removeObject(forKey: "licenseInstance")
            refresh()
        }
    }
}
