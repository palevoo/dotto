#if canImport(AppKit)
import AppKit
#endif
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Core

/// What a drop or a paste becomes in the live line, and a picture as the notebook keeps it.
final class ArrivalTests: XCTestCase {
    private let bytes = Data([1, 2, 3])

    func testALinkDraggedFromABrowserLandsOnceAsItsAddress() {
        let link = URL(string: "https://transformer-circuits.pub/2022/toy_model/index.html")!
        let offered = Offered(link: link, words: link.absoluteString)
        XCTAssertEqual(offered.arrivals(), [.words(link.absoluteString)])
    }

    func testAPictureCopiedFromAPageIsThePictureNotItsAddress() {
        let offered = Offered(picture: bytes, link: URL(string: "https://example.com/a.png")!, words: "https://example.com/a.png")
        XCTAssertEqual(offered.arrivals(), [.picture(bytes)])
    }

    func testWordsThatComeWithARenderingOfThemAreWords() {
        // Cells copied from a spreadsheet: the text and a picture of the cells.
        XCTAssertEqual(Offered(picture: bytes, words: "Olives\t130 kg").arrivals(), [.words("Olives\t130 kg")])
        // A picture alone is the picture.
        XCTAssertEqual(Offered(picture: bytes).arrivals(), [.picture(bytes)])
        // Words selected on a page that happen to be offered with the page's address.
        let page = URL(string: "https://example.com/essay")!
        XCTAssertEqual(Offered(link: page, words: "a passage from it").arrivals(), [.words("a passage from it")])
    }

    func testWordsLandTrimmedAndBlankWordsDoNotLand() {
        XCTAssertEqual(Offered(words: "  a thought\n").arrivals(), [.words("a thought")])
        XCTAssertEqual(Offered(words: " \n ").arrivals(), [])
        XCTAssertTrue(Offered().isEmpty)
        XCTAssertEqual(Offered().arrivals(), [])
    }

    func testOfFilesPicturesLandAndTheRestAreNamed() {
        let shot = URL(fileURLWithPath: "/tmp/Screenshot 2026-11-10 at 09.14.02.png")
        let paper = URL(fileURLWithPath: "/tmp/more-is-different.pdf")
        let offered = Offered(files: [shot, paper], words: "ignored beside files")
        let arrivals = offered.arrivals { $0 == shot ? self.bytes : nil }
        XCTAssertEqual(arrivals, [.picture(bytes), .leftOut("more-is-different.pdf")])
    }

    func testAPictureFileThatCannotBeReadIsLeftOutByName() {
        let gone = URL(fileURLWithPath: "/tmp/gone.jpg")
        XCTAssertEqual(Offered(files: [gone]).arrivals { _ in nil }, [.leftOut("gone.jpg")])
    }

    func testAPassageWithBreaksBecomesOneLine() {
        XCTAssertEqual(Words.flattened("one\ntwo"), "one two")
        XCTAssertEqual(Words.flattened("one  \n\n   two\nthree"), "one two three")
        XCTAssertEqual(Words.flattened("\nleading"), "leading")
        XCTAssertEqual(Words.flattened("no breaks  here"), "no breaks  here", "spaces that are not around a break stay")
    }

    func testAScreenshotIsKeptAsAJPEGNoLargerThanTheStoredSide() throws {
        let png = try XCTUnwrap(Self.png(width: 3456, height: 2234))
        let kept = try XCTUnwrap(Picture.process(png))
        XCTAssertEqual(kept.width, Picture.storedSide)
        XCTAssertEqual(kept.height, 1324)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(kept.jpeg as CFData, nil))
        XCTAssertEqual(CGImageSourceGetType(source) as String?, UTType.jpeg.identifier)
        XCTAssertFalse(kept.thumbnail.isEmpty)
        XCTAssertNil(Picture.process(Data("not a picture".utf8)))
    }

    #if canImport(AppKit)
    /// A pasteboard of the test's own, never the clipboard.
    @MainActor
    private func pasteboard() -> NSPasteboard {
        let board = NSPasteboard(name: NSPasteboard.Name("dotto.tests.\(UUID().uuidString)"))
        board.clearContents()
        addTeardownBlock { board.releaseGlobally() }
        return board
    }

    @MainActor
    func testWordsOnAPasteboardAreWords() {
        let board = pasteboard()
        board.setString("how do you say tall", forType: .string)
        let offered = Offered.read(board)
        XCTAssertEqual(offered, Offered(words: "how do you say tall"))
        XCTAssertEqual(offered.arrivals(), [.words("how do you say tall")])
    }

    @MainActor
    func testALinkOnAPasteboardLandsAsItsAddress() {
        let board = pasteboard()
        let link = URL(string: "https://www.tkm.kit.edu/downloads/TKM1_2011_more_is_different_PWA.pdf")!
        board.writeObjects([link as NSURL])
        let offered = Offered.read(board)
        XCTAssertEqual(offered.link, link)
        XCTAssertTrue(offered.files.isEmpty)
        XCTAssertEqual(offered.arrivals(), [.words(link.absoluteString)])
    }

    @MainActor
    func testAPictureOnAPasteboardIsThePicture() throws {
        let board = pasteboard()
        let png = try XCTUnwrap(Self.png(width: 40, height: 30))
        board.setData(png, forType: .png)
        let offered = Offered.read(board)
        XCTAssertEqual(offered.picture, png)
        XCTAssertEqual(offered.arrivals(), [.picture(png)])
    }

    @MainActor
    func testAPictureFileOnAPasteboardIsReadFromTheFile() throws {
        let board = pasteboard()
        let png = try XCTUnwrap(Self.png(width: 40, height: 30))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("dotto-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let shot = folder.appendingPathComponent("Screenshot 2026-11-10 at 09.14.02.png")
        let paper = folder.appendingPathComponent("paper.pdf")
        try png.write(to: shot)
        try Data("%PDF".utf8).write(to: paper)
        board.writeObjects([shot as NSURL, paper as NSURL])
        // A loose picture beside files is the files' icon, not the thing.
        board.addTypes([.tiff], owner: nil)
        board.setData(Data([0]), forType: .tiff)
        let offered = Offered.read(board)
        XCTAssertEqual(offered.files.map(\.lastPathComponent), [shot.lastPathComponent, "paper.pdf"])
        XCTAssertNil(offered.picture)
        XCTAssertNil(offered.link, "a file's address is not a link")
        XCTAssertEqual(offered.arrivals(), [.picture(png), .leftOut("paper.pdf")])
    }
    #endif

    private static func png(width: Int, height: Int) -> Data? {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(red: 0.9, green: 0.34, blue: 0.18, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
