import Foundation
import Network

public struct HTTPRequest: Sendable {
    public let method: String
    public let path: String
    /// Header names lower-cased.
    public let headers: [String: String]
    public let body: Data
}

public struct HTTPResponse: Sendable {
    public var status: Int
    public var headers: [String: String]
    public var body: Data

    public init(status: Int, json body: Data) {
        self.init(status: status, headers: ["Content-Type": "application/json"], body: body)
    }

    public init(status: Int, text: String, headers: [String: String] = [:]) {
        var all = headers
        all["Content-Type"] = "text/plain; charset=utf-8"
        self.init(status: status, headers: all, body: Data(text.utf8))
    }

    public init(status: Int, headers: [String: String], body: Data) {
        self.status = status
        self.headers = headers
        self.body = body
    }
}

/// The smallest HTTP/1.1 server that will do: loopback only, one request per connection,
/// no keep-alive, no streaming. Enough for a door that answers one message at a time.
public final class DoorServer: @unchecked Sendable {
    public typealias Handler = @Sendable (HTTPRequest) -> HTTPResponse

    private let listener: NWListener
    private let handler: Handler
    private let queue = DispatchQueue(label: "dotto.door.server")
    private let lock = NSLock()
    private var readyContinuations: [CheckedContinuation<UInt16, Error>] = []
    private var state: State = .idle

    private enum State { case idle, ready(UInt16), failed(Error), cancelled }

    public enum Failure: Error { case notReady, cancelled }

    /// `port` 0 asks the system for a free one; read `start()`'s return value.
    public init(port: UInt16 = 0, handler: @escaping Handler) throws {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port) ?? .any)
        listener = try NWListener(using: parameters)
        self.handler = handler
    }

    /// Starts listening and returns the port once it is bound.
    public func start() async throws -> UInt16 {
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.settle(.ready(self.listener.port?.rawValue ?? 0))
            case .failed(let error):
                self.settle(.failed(error))
            case .cancelled:
                self.settle(.cancelled)
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.serve(connection)
        }
        listener.start(queue: queue)
        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            switch state {
            case .ready(let port):
                lock.unlock()
                continuation.resume(returning: port)
            case .failed(let error):
                lock.unlock()
                continuation.resume(throwing: error)
            case .cancelled:
                lock.unlock()
                continuation.resume(throwing: Failure.cancelled)
            case .idle:
                readyContinuations.append(continuation)
                lock.unlock()
            }
        }
    }

    public func stop() {
        listener.cancel()
    }

    private func settle(_ newState: State) {
        lock.lock()
        state = newState
        let waiting = readyContinuations
        readyContinuations = []
        lock.unlock()
        for continuation in waiting {
            switch newState {
            case .ready(let port): continuation.resume(returning: port)
            case .failed(let error): continuation.resume(throwing: error)
            case .cancelled: continuation.resume(throwing: Failure.cancelled)
            case .idle: continuation.resume(throwing: Failure.notReady)
            }
        }
    }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection, sofar: Data())
    }

    private func receive(_ connection: NWConnection, sofar: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = sofar
            if let data { buffer.append(data) }
            if let request = Self.parse(buffer) {
                let response = self.handler(request)
                connection.send(content: Self.serialize(response), completion: .contentProcessed { _ in
                    connection.cancel()
                })
                return
            }
            if isComplete || error != nil || buffer.count > (8 << 20) {
                connection.cancel()
                return
            }
            self.receive(connection, sofar: buffer)
        }
    }

    // MARK: - Wire format

    static func parse(_ data: Data) -> HTTPRequest? {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let head = String(decoding: data[data.startIndex..<headerEnd.lowerBound], as: UTF8.self)
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        // A length that is not a number, or is below nothing, is no body at all; the door
        // then answers the empty request as it would any other it cannot read.
        let length = max(0, Int(headers["content-length"] ?? "0") ?? 0)
        let bodyStart = headerEnd.upperBound
        guard data.endIndex - bodyStart >= length else { return nil }
        let body = Data(data[bodyStart..<(bodyStart + length)])
        return HTTPRequest(method: String(requestLine[0]), path: String(requestLine[1]), headers: headers, body: body)
    }

    static func serialize(_ response: HTTPResponse) -> Data {
        var head = "HTTP/1.1 \(response.status) \(reason(response.status))\r\n"
        for (name, value) in response.headers.sorted(by: { $0.key < $1.key }) {
            head += "\(name): \(value)\r\n"
        }
        head += "Content-Length: \(response.body.count)\r\nConnection: close\r\n\r\n"
        return Data(head.utf8) + response.body
    }

    static func reason(_ status: Int) -> String {
        switch status {
        case 200: "OK"
        case 202: "Accepted"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        default: "Status"
        }
    }
}
