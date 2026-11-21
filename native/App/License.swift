// Free: only the first preset (Afterglow), no editor. A Polar license key unlocks everything.
// Uses Polar's public customer-portal License Key API (no secret in the app): activate once per Mac, re-validate on launch.
import AppKit
import Foundation

enum LicenseConfig {
    // Polar: Settings → General → Organization ID, and the product's checkout link (Products → Checkout Links).
    // For a test run use https://sandbox-api.polar.sh with a sandbox organization and checkout link.
    static let api = "https://api.polar.sh/v1/customer-portal/license-keys/"
    static let organizationID = "24827a15-12d7-4cfa-89a3-21d44f0668cc"
    static let checkoutURL = URL(string: "https://buy.polar.sh/polar_cl_zCiBfldT1FCncWUnHyAJnN2WaIvrpILUXi9q62z9wXY")!
}
@MainActor
final class License: ObservableObject {
    enum State: Equatable { case free, licensed }

    @Published private(set) var state: State = .free
    var onChange: () -> Void = {}
    var isUnlocked: Bool { state == .licensed }

    // shortcut: the key lives in UserDefaults, so it can be copied between Macs without activating; move it to the
    // Keychain if license sharing becomes a real problem.
    private let defaults = UserDefaults.standard
    private var key: String? { defaults.string(forKey: "licenseKey") }
    private var instanceID: String? { defaults.string(forKey: "licenseInstance") }

    init() {
        refresh()
        if let key, let instanceID { Task { await revalidate(key: key, instance: instanceID) } }
    }

    private func refresh() {
        let old = state
        state = key != nil && instanceID != nil ? .licensed : .free
        if state != old { onChange() }
    }

    struct APIError: LocalizedError { let errorDescription: String? }

    private struct Activation: Decodable { let id: String }
    private struct Failure: Decodable { let error: String?; let detail: String? }

    /// POSTs JSON; returns the HTTP status and body. Keys are scoped to our organization, so another store's key fails.
    private func call(_ endpoint: String, _ fields: [String: String]) async throws -> (Int, Data) {
        var req = URLRequest(url: URL(string: LicenseConfig.api + endpoint)!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.httpBody = try JSONEncoder().encode(fields.merging(["organization_id": LicenseConfig.organizationID]) { a, _ in a })
        let (data, response) = try await URLSession.shared.data(for: req)
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, data)
    }

    func activate(_ rawKey: String) async throws {
        let k = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty else { throw APIError(errorDescription: "Enter a license key") }
        guard !LicenseConfig.organizationID.isEmpty else { throw APIError(errorDescription: "Licensing isn't set up in this build") }
        let (status, data) = try await call("activate", ["key": k, "label": Host.current().localizedName ?? "Mac"])
        switch status {
        case 200:
            guard let a = try? JSONDecoder().decode(Activation.self, from: data) else { throw APIError(errorDescription: "Unexpected reply from the license server") }
            defaults.set(k, forKey: "licenseKey")
            defaults.set(a.id, forKey: "licenseInstance")
            refresh()
        case 403: throw APIError(errorDescription: "This key is already active on the maximum number of Macs, or it was refunded. Deactivate it on another Mac first.")
        case 404, 422: throw APIError(errorDescription: "Invalid license key")
        default: throw APIError(errorDescription: (try? JSONDecoder().decode(Failure.self, from: data))?.detail ?? "The license server is unavailable (\(status)). Try again later.")
        }
    }

    func deactivate() async {
        if let key, let instanceID { _ = try? await call("deactivate", ["key": key, "activation_id": instanceID]) }
        defaults.removeObject(forKey: "licenseKey")
        defaults.removeObject(forKey: "licenseInstance")
        refresh()
    }

    /// Offline or server errors keep the license; only Polar's "not found" (revoked, refunded, disabled, deactivated)
    /// removes it. Checking the body too means a stray 404 page from a proxy can't lock a paying customer out.
    private func revalidate(key: String, instance: String) async {
        guard let (status, data) = try? await call("validate", ["key": key, "activation_id": instance]), status == 404,
              (try? JSONDecoder().decode(Failure.self, from: data))?.error == "ResourceNotFound" else { return }
        defaults.removeObject(forKey: "licenseKey")
        defaults.removeObject(forKey: "licenseInstance")
        refresh()
    }
}
