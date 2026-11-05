import CryptoKit
import XCTest
@testable import Core

final class PushesTests: XCTestCase {
    var root: URL!
    var store: FileStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("push-tests-\(UUID().uuidString)", isDirectory: true)
        store = try FileStore.create(at: root, owner: "me")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testAddressesLiveInTheFolderOnePerDevice() throws {
        XCTAssertEqual(try store.pushAddresses(), [])
        let first = PushAddress(device: "rounded", token: "aa11", environment: "development", topic: "social.interface.notebook",
                                updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
        try store.savePushAddress(first)
        try store.savePushAddress(PushAddress(device: "flat", token: "bb22", environment: "production", topic: "social.interface.notebook",
                                              updatedAt: Date(timeIntervalSince1970: 1_700_000_001)))
        // A new token for the same phone replaces the old one.
        let renewed = PushAddress(device: "rounded", token: "cc33", environment: "development", topic: "social.interface.notebook",
                                  updatedAt: Date(timeIntervalSince1970: 1_700_000_002))
        try store.savePushAddress(renewed)
        let addresses = try store.pushAddresses()
        XCTAssertEqual(addresses.count, 2)
        XCTAssertEqual(addresses.first { $0.device == "rounded" }?.token, "cc33")
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.devicesDirectory.appendingPathComponent("rounded.json").path))
    }

    func testKeyIDComesFromApplesFileName() {
        XCTAssertEqual(PushKey.keyID(fromFileName: "AuthKey_ABC123DEFG.p8"), "ABC123DEFG")
        XCTAssertNil(PushKey.keyID(fromFileName: "something.p8"))
        XCTAssertNil(PushKey.keyID(fromFileName: "AuthKey_.p8"))
    }

    /// The claim Apple checks: two base64url JSON parts and a signature the key's public half verifies.
    func testTokenIsSignedByTheKey() throws {
        let privateKey = P256.Signing.PrivateKey()
        let key = PushKey(keyID: "KEY1234567", teamID: "TEAM123456", pem: privateKey.pemRepresentation)
        let now = Date(timeIntervalSince1970: 1_762_300_000)
        let token = try APNS.token(for: key, now: now)
        let parts = token.split(separator: ".").map(String.init)
        XCTAssertEqual(parts.count, 3)

        let header = try JSONSerialization.jsonObject(with: Self.unbase64url(parts[0])) as? [String: String]
        XCTAssertEqual(header, ["alg": "ES256", "kid": "KEY1234567"])
        let claims = try JSONSerialization.jsonObject(with: Self.unbase64url(parts[1])) as? [String: Any]
        XCTAssertEqual(claims?["iss"] as? String, "TEAM123456")
        XCTAssertEqual(claims?["iat"] as? Int, 1_762_300_000)

        let signature = try P256.Signing.ECDSASignature(rawRepresentation: Self.unbase64url(parts[2]))
        XCTAssertTrue(privateKey.publicKey.isValidSignature(signature, for: Data("\(parts[0]).\(parts[1])".utf8)))
    }

    func testRequestGoesToTheRightSideOfApple() throws {
        let key = PushKey(keyID: "KEY1234567", teamID: "TEAM123456", pem: P256.Signing.PrivateKey().pemRepresentation)
        let entry = ULID()
        let message = APNS.Message(title: "weeju", body: "Four to six weeks, when roots show.", entry: entry)
        let sandbox = PushAddress(device: "rounded", token: "aa11", environment: "development", topic: "social.interface.notebook")
        let request = try APNS.request(message, to: sandbox, key: key)
        XCTAssertEqual(request.url?.absoluteString, "https://api.sandbox.push.apple.com/3/device/aa11")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "apns-topic"), "social.interface.notebook")
        XCTAssertEqual(request.value(forHTTPHeaderField: "apns-push-type"), "alert")
        XCTAssertTrue(request.value(forHTTPHeaderField: "authorization")?.hasPrefix("bearer ") ?? false)
        let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
        XCTAssertEqual(body?["entry"] as? String, entry.string)
        let aps = body?["aps"] as? [String: Any]
        XCTAssertEqual((aps?["alert"] as? [String: String])?["body"], "Four to six weeks, when roots show.")

        let live = PushAddress(device: "rounded", token: "aa11", environment: "production", topic: "social.interface.notebook")
        XCTAssertEqual(APNS.url(for: live).host, "api.push.apple.com")
    }

    static func unbase64url(_ text: String) -> Data {
        var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        return Data(base64Encoded: base64)!
    }
}
