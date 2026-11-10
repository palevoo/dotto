import Core
import Foundation
import PDFKit

/// Opens what a line of the owner's points at: one address, out on the web, read once and
/// handed back as words. The home does this, not anyone who reads the notebook, so nothing
/// that reads a stranger's page ever holds a way out. It sends nothing of the owner's: no
/// cookies, no account, a plain name for itself. It follows a redirect only to somewhere it
/// would have been allowed to open in the first place.
enum Opener {
    /// The most that is read of one address.
    private static let most = 8 * 1024 * 1024
    /// Fewer words than this is a page with nothing to keep: a player, a wall, a script.
    private static let least = 200

    static func open(_ url: URL) async -> Web.Page? {
        guard Web.mayOpen(url) else { return nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 40
        let session = URLSession(configuration: configuration, delegate: Redirects(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        var request = URLRequest(url: url)
        request.setValue("dotto (a personal notebook opening a page its owner pointed at)", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html, application/pdf, text/plain;q=0.9, */*;q=0.1", forHTTPHeaderField: "Accept")
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
                if data.count >= most { break }
            }
            let kind = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
            let page: Web.Page?
            if kind.contains("pdf") || data.prefix(5) == Data("%PDF-".utf8) {
                page = pdf(data)
            } else if kind.contains("html") || kind.isEmpty {
                page = Web.page(fromHTML: words(data, kind))
            } else if kind.hasPrefix("text/") {
                page = Web.Page(title: nil, text: String(words(data, kind).prefix(Web.most)))
            } else {
                page = nil
            }
            guard let page, page.text.count >= least else { return nil }
            return page
        } catch {
            return nil
        }
    }

    /// The bytes as words, in the alphabet the page says it is in, else the one that fits.
    private static func words(_ data: Data, _ kind: String) -> String {
        if kind.contains("utf-8") || !kind.contains("charset="), let text = String(data: data, encoding: .utf8) { return text }
        if kind.contains("1251"), let text = String(data: data, encoding: .windowsCP1251) { return text }
        if kind.contains("8859-1") || kind.contains("1252"), let text = String(data: data, encoding: .windowsCP1252) { return text }
        return String(decoding: data, as: UTF8.self)
    }

    private static func pdf(_ data: Data) -> Web.Page? {
        guard let document = PDFDocument(data: data), let text = document.string else { return nil }
        let title = document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String
        let lines = text.split(separator: "\n").map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }.filter { !$0.isEmpty }
        return Web.Page(title: title?.isEmpty == false ? title : nil, text: String(lines.joined(separator: "\n").prefix(Web.most)))
    }

    /// A redirect is followed only to an address that may be opened.
    private final class Redirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest) async -> URLRequest? {
            guard let url = request.url, Web.mayOpen(url) else { return nil }
            return request
        }
    }
}
