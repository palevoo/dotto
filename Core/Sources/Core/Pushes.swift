import CryptoKit
import Foundation

/// Where a phone can be reached with a push: the address Apple gave it, kept in the notebook
/// folder as `devices/<device>.json` so whoever holds the folder and the key can send.
public struct PushAddress: Hashable, Codable, Sendable, Identifiable {
    public var device: DeviceID
    /// Apple's token for this app on this phone, as hex.
    public var token: String
    /// "development" for a build run from Xcode, "production" for TestFlight and the store.
    /// Apple keeps the two apart and a push sent to the wrong side is refused.
    public var environment: String
    /// The app's bundle id, which Apple calls the topic.
    public var topic: String
    public var updatedAt: Date

    public var id: DeviceID { device }

    public init(device: DeviceID, token: String, environment: String, topic: String, updatedAt: Date = Date()) {
        self.device = device
        self.token = token
        self.environment = environment
        self.topic = topic
        self.updatedAt = updatedAt
    }
}

public extension FileStore {
    var devicesDirectory: URL { root.appendingPathComponent("devices", isDirectory: true) }

    /// The phone writes its address, replacing the last one for the same device.
    func savePushAddress(_ address: PushAddress) throws {
        try FileManager.default.createDirectory(at: devicesDirectory, withIntermediateDirectories: true)
        let encoder = JSONLines.encoder()
        encoder.outputFormatting.insert(.prettyPrinted)
        try encoder.encode(address).write(to: devicesDirectory.appendingPathComponent("\(Self.safe(address.device.rawValue)).json"), options: .atomic)
    }

    /// Every phone that can be reached, as last written.
    func pushAddresses() throws -> [PushAddress] {
        guard FileManager.default.fileExists(atPath: devicesDirectory.path) else { return [] }
        let decoder = JSONLines.decoder()
        return try FileManager.default.contentsOfDirectory(atPath: devicesDirectory.path)
            .filter { $0.hasSuffix(".json") }
            .sorted()
            .compactMap { name in
                guard let data = FileManager.default.contents(atPath: devicesDirectory.appendingPathComponent(name).path) else { return nil }
                return try decoder.decode(PushAddress.self, from: data)
            }
    }
}

/// The key Apple issued to the developer account for sending pushes: the `.p8` file,
/// its id, and the team. Held by whoever sends.
public struct PushKey: Hashable, Sendable {
    public var keyID: String
    public var teamID: String
    /// The `.p8` file's text.
    public var pem: String

    public init(keyID: String, teamID: String, pem: String) {
        self.keyID = keyID
        self.teamID = teamID
        self.pem = pem
    }

    /// "ABC123DEFG" from "AuthKey_ABC123DEFG.p8", as Apple names the download.
    public static func keyID(fromFileName name: String) -> String? {
        let base = (name as NSString).deletingPathExtension
        guard base.hasPrefix("AuthKey_") else { return nil }
        let id = String(base.dropFirst("AuthKey_".count))
        return id.isEmpty ? nil : id
    }
}

/// One push, as Apple takes it: a request to their server, signed with the key.
public enum APNS {
    /// What the phone shows and what the app opens when it is tapped.
    public struct Message: Hashable, Sendable {
        public var title: String
        public var body: String
        /// The line to open, if the push is about one.
        public var entry: ULID?

        public init(title: String, body: String, entry: ULID? = nil) {
            self.title = title
            self.body = body
            self.entry = entry
        }
    }

    public static func url(for address: PushAddress) -> URL {
        let host = address.environment == "production" ? "api.push.apple.com" : "api.sandbox.push.apple.com"
        return URL(string: "https://\(host)/3/device/\(address.token)")!
    }

    /// The request, ready to send, signed fresh. For many pushes make the token once with
    /// `token(for:now:)` and pass it as the bearer: Apple refuses a key re-signed more often
    /// than every twenty minutes, and takes one for an hour.
    public static func request(_ message: Message, to address: PushAddress, key: PushKey, now: Date = Date()) throws -> URLRequest {
        try request(message, to: address, bearer: token(for: key, now: now))
    }

    public static func request(_ message: Message, to address: PushAddress, bearer: String) throws -> URLRequest {
        var request = URLRequest(url: url(for: address))
        request.httpMethod = "POST"
        request.setValue("bearer \(bearer)", forHTTPHeaderField: "authorization")
        request.setValue(address.topic, forHTTPHeaderField: "apns-topic")
        request.setValue("alert", forHTTPHeaderField: "apns-push-type")
        request.setValue("10", forHTTPHeaderField: "apns-priority")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload(message))
        return request
    }

    public static func payload(_ message: Message) -> [String: Any] {
        var payload: [String: Any] = [
            "aps": ["alert": ["title": message.title, "body": message.body], "sound": "default"],
        ]
        if let entry = message.entry { payload["entry"] = entry.string }
        return payload
    }

    /// The signed claim Apple asks for: who the key is (kid), which team (iss), when (iat),
    /// in the ES256 form. Good for an hour; Apple refuses one older than that.
    public static func token(for key: PushKey, now: Date = Date()) throws -> String {
        let header = try JSONSerialization.data(withJSONObject: ["alg": "ES256", "kid": key.keyID], options: .sortedKeys)
        let claims = try JSONSerialization.data(withJSONObject: ["iss": key.teamID, "iat": Int(now.timeIntervalSince1970)], options: .sortedKeys)
        let signing = "\(base64url(header)).\(base64url(claims))"
        let privateKey = try P256.Signing.PrivateKey(pemRepresentation: key.pem)
        let signature = try privateKey.signature(for: Data(signing.utf8))
        return "\(signing).\(base64url(signature.rawRepresentation))"
    }

    static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
