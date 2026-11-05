import AVFoundation
import Foundation
import Speech

/// Speech to words, on the phone, in whichever of your languages a take is in.
///
/// The languages are the phone's own list, Settings · General · Language & Region. Each
/// one that Apple's on-device models cover is a candidate; a take is run through every
/// candidate at once and the words that fit best are kept, judged by the model's own
/// confidence, so Russian and English can follow each other line by line with nothing to
/// switch. The models are downloaded once, from Setup, and kept on the phone.
@MainActor
@Observable
final class Voice {
    static let shared = Voice()

    struct Language: Identifiable {
        let locale: Locale
        /// "Russian", in the phone's language.
        let name: String
        /// The better model where Apple has one for the language, else the dictation one.
        let way: Way
        var state: State

        var id: String { locale.identifier }
    }

    enum Way: String { case transcriber, dictation }

    enum State: Equatable {
        case ready
        case getting
        case missing
        case unsupported
    }

    private(set) var languages: [Language] = []
    /// Apple's refusal, in its words, where it can be read and reported.
    private(set) var trouble: String?

    /// Which of the phone's languages can be heard, and which have their model here.
    func refresh() async {
        guard #available(iOS 26, *) else { return }
        var found: [Language] = []
        let transcriber = await SpeechTranscriber.supportedLocales
        let dictation = await DictationTranscriber.supportedLocales
        for identifier in Locale.preferredLanguages {
            let wanted = Locale(identifier: identifier)
            guard let code = wanted.language.languageCode?.identifier,
                  !found.contains(where: { $0.locale.language.languageCode?.identifier == code }) else { continue }
            let name = Locale.current.localizedString(forLanguageCode: code)?.capitalized ?? code
            if let locale = Self.match(wanted, in: transcriber) {
                let state = await Self.state(of: SpeechTranscriber(locale: locale, preset: .transcription))
                found.append(Language(locale: locale, name: name, way: .transcriber, state: state))
            } else if let locale = Self.match(wanted, in: dictation) {
                let state = await Self.state(of: DictationTranscriber(locale: locale, preset: .shortDictation))
                found.append(Language(locale: locale, name: name, way: .dictation, state: state))
            } else {
                found.append(Language(locale: wanted, name: name, way: .transcriber, state: .unsupported))
            }
        }
        languages = found
    }

    /// Downloads the model for one language and keeps it on the phone.
    func get(_ language: Language) {
        guard #available(iOS 26, *), let index = languages.firstIndex(where: { $0.id == language.id }) else { return }
        languages[index].state = .getting
        trouble = nil
        Task {
            do {
                let module: any SpeechModule = language.way == .transcriber
                    ? SpeechTranscriber(locale: language.locale, preset: .transcription)
                    : DictationTranscriber(locale: language.locale, preset: .shortDictation)
                if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
                    try await request.downloadAndInstall()
                }
                try? await AssetInventory.reserve(locale: language.locale)
            } catch {
                trouble = error.localizedDescription
            }
            await refresh()
        }
    }

    /// The words of a take: every ready language tried at once, the best fit kept. Falls back
    /// to the older recogniser when no model is here, so a take never comes back empty for
    /// want of a download.
    static func transcribe(_ url: URL) async -> String {
        if #available(iOS 26, *) {
            let ready = await shared.readyLanguages()
            if !ready.isEmpty {
                let best = await withTaskGroup(of: (String, Double).self, returning: (String, Double).self) { group in
                    for language in ready {
                        group.addTask { await Self.run(url, language) }
                    }
                    var best = ("", -1.0)
                    for await result in group where result.1 > best.1 { best = result }
                    return best
                }
                if best.1 >= 0.3 { return best.0.trimmingCharacters(in: .whitespacesAndNewlines) }
                return ""
            }
        }
        return await Transcriber.transcribe(url)
    }

    private func readyLanguages() async -> [Language] {
        if languages.isEmpty { await refresh() }
        return languages.filter { $0.state == .ready }
    }

    // MARK: - Apple's analyser

    @available(iOS 26, *)
    private static func run(_ url: URL, _ language: Language) async -> (String, Double) {
        final class Heard: @unchecked Sendable {
            var text = ""
            var confidences: [Double] = []
            func take(_ attributed: AttributedString) {
                text += String(attributed.characters)
                for run in attributed.runs {
                    if let confidence = run.transcriptionConfidence { confidences.append(confidence) }
                }
            }
            var mean: Double { confidences.isEmpty ? -1 : confidences.reduce(0, +) / Double(confidences.count) }
        }
        let heard = Heard()
        do {
            let file = try AVAudioFile(forReading: url)
            switch language.way {
            case .transcriber:
                let module = SpeechTranscriber(locale: language.locale, transcriptionOptions: [], reportingOptions: [],
                                               attributeOptions: [.transcriptionConfidence])
                let analyzer = SpeechAnalyzer(modules: [module])
                async let results: Void = { for try await result in module.results { heard.take(result.text) } }()
                try await analyzer.analyzeSequence(from: file)
                try await analyzer.finalizeAndFinishThroughEndOfInput()
                try await results
            case .dictation:
                let module = DictationTranscriber(locale: language.locale, contentHints: [], transcriptionOptions: [],
                                                  reportingOptions: [], attributeOptions: [.transcriptionConfidence])
                let analyzer = SpeechAnalyzer(modules: [module])
                async let results: Void = { for try await result in module.results { heard.take(result.text) } }()
                try await analyzer.analyzeSequence(from: file)
                try await analyzer.finalizeAndFinishThroughEndOfInput()
                try await results
            }
        } catch {
            NSLog("voice failed for \(language.locale.identifier): \(error)")
            return ("", -1)
        }
        return (heard.text, heard.mean)
    }

    @available(iOS 26, *)
    private static func state(of module: some SpeechModule) async -> State {
        switch await AssetInventory.status(forModules: [module]) {
        case .installed: .ready
        case .downloading: .getting
        case .supported: .missing
        case .unsupported: .unsupported
        @unknown default: .unsupported
        }
    }

    /// The supported locale for a wanted language: the same region when there is one,
    /// else the first with that language.
    private static func match(_ wanted: Locale, in supported: [Locale]) -> Locale? {
        guard let code = wanted.language.languageCode?.identifier else { return nil }
        let same = supported.filter { $0.language.languageCode?.identifier == code }
        if let region = wanted.region, let exact = same.first(where: { $0.region == region }) { return exact }
        return same.first
    }
}
