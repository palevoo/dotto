import SwiftUI
import UniformTypeIdentifiers

/// First launch: where the notebook lives. A folder of plain files, yours.
struct ChooseFolderView: View {
    let onChoose: (URL) -> Void
    @State private var picking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Spacer()
            Theme.square(44)
                .fill(Theme.accent)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 12) {
                Text("Where should your notebook live?")
                    .font(Theme.title)
                    .foregroundStyle(Theme.foreground)
                Text("A folder of plain files, owned by you. Put it in iCloud Drive and your Mac sees it in Finder.")
                    .font(Theme.serifSmall)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 14) {
                Button {
                    picking = true
                } label: {
                    Text("Choose a folder")
                        .font(Theme.sansSmall.weight(.medium))
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .clipShape(Theme.square(48))

                Button {
                    onChoose(Library.localFolder)
                } label: {
                    Text("Keep it on this phone for now")
                        .font(Theme.sansSmall)
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .sheet(isPresented: $picking) {
            FolderPicker { url in
                picking = false
                if let url { onChoose(url) }
            }
            .ignoresSafeArea()
        }
    }
}

struct FolderPicker: UIViewControllerRepresentable {
    let onPick: (URL?) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL?) -> Void
        init(onPick: @escaping (URL?) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls.first)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onPick(nil)
        }
    }
}
