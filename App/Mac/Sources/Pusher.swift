import Core
import Foundation
import Security

/// Sends pushes to the phones in the notebook folder, with the developer account's key.
/// The signed claim is made once and reused for fifty minutes, as Apple asks.
actor Pusher {
    private var key: PushKey?
    private var bearer: (value: String, made: Date)?
    private let session = URLSession(configuration: .ephemeral)

    struct Outcome: Sendable {
        let device: DeviceID
        let ok: Bool
        /// Apple's word for what went wrong, such as BadDeviceToken, or the HTTP status.
        let reason: String?
        /// Apple says the address is no longer that phone's: the app was deleted or put on
        /// again since. Nothing sent to it will ever arrive.
        var gone = false
    }

    func use(_ key: PushKey?) {
        self.key = key
        bearer = nil
    }

    func send(_ message: APNS.Message, to addresses: [PushAddress]) async -> [Outcome] {
        guard let key, !addresses.isEmpty else { return [] }
        var outcomes: [Outcome] = []
        for address in addresses {
            do {
                let request = try APNS.request(message, to: address, bearer: try bearer(for: key))
                let (data, response) = try await session.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if status == 200 {
                    outcomes.append(Outcome(device: address.device, ok: true, reason: nil))
                } else {
                    let reason = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["reason"] as? String
                    outcomes.append(Outcome(device: address.device, ok: false, reason: reason ?? "HTTP \(status)", gone: status == 410))
                }
            } catch {
                outcomes.append(Outcome(device: address.device, ok: false, reason: error.localizedDescription))
            }
        }
        return outcomes
    }

    private func bearer(for key: PushKey) throws -> String {
        if let bearer, Date().timeIntervalSince(bearer.made) < 50 * 60 { return bearer.value }
        let made = Date()
        let value = try APNS.token(for: key, now: made)
        bearer = (value, made)
        return value
    }
}

/// The push key on this Mac: the `.p8` text in the keychain, its id and the team beside it.
enum PushKeyStore {
    private static let service = Identity.keychainService("push-key")
    private static let keyIDKey = Identity.Kept.pushKeyID
    private static let teamIDKey = Identity.Kept.pushTeamID

    static func load() -> PushKey? {
        guard let keyID = UserDefaults.standard.string(forKey: keyIDKey),
              let teamID = UserDefaults.standard.string(forKey: teamIDKey) else { return nil }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: keyID,
            kSecReturnData as String: true,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data, let pem = String(data: data, encoding: .utf8) else { return nil }
        return PushKey(keyID: keyID, teamID: teamID, pem: pem)
    }

    static func save(_ key: PushKey) throws {
        remove()
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.keyID,
            kSecValueData as String: Data(key.pem.utf8),
        ]
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: SecCopyErrorMessageString(status, nil) as String? ?? "keychain \(status)"])
        }
        UserDefaults.standard.set(key.keyID, forKey: keyIDKey)
        UserDefaults.standard.set(key.teamID, forKey: teamIDKey)
    }

    static func remove() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        SecItemDelete(query as CFDictionary)
        UserDefaults.standard.removeObject(forKey: keyIDKey)
        UserDefaults.standard.removeObject(forKey: teamIDKey)
    }
}
