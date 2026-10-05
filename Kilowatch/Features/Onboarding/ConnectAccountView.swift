import SwiftUI
import UniformTypeIdentifiers

/// First-run screen. Explains what linking does and kicks off the flow.
struct ConnectAccountView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingImporter = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: "bolt.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.yellow)
            VStack(spacing: 8) {
                Text("Kilowatch")
                    .font(.largeTitle.bold())
                Text("Finally understand your Con Edison bill, and see how you stack up against people like you.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }

            VStack(alignment: .leading, spacing: 14) {
                bullet("lock.shield", "You sign in on Con Edison's site. Kilowatch never sees your password.")
                bullet("doc.text.magnifyingglass", "We read your bills and meter data, nothing else.")
                bullet("eye.slash", "Comparisons are opt-in and anonymous by default.")
            }
            .padding()
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal)

            Spacer()

            if case .failed(let message) = model.linkState {
                Text(message).foregroundStyle(.red).font(.footnote)
            }

            Button {
                Task { await model.linkAccount() }
            } label: {
                HStack {
                    if model.linkState == .linking { ProgressView().tint(.white) }
                    Text(model.linkState == .linking ? "Connecting…" : "Connect Con Edison")
                        .bold()
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.linkState == .linking)
            .padding(.horizontal)

            Button {
                showingImporter = true
            } label: {
                Label("Import a Green Button file", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .padding(.horizontal)
            .padding(.bottom)
        }
        .greenButtonImporter(isPresented: $showingImporter)
    }

    private func bullet(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).frame(width: 24).foregroundStyle(.tint)
            Text(text).font(.subheadline)
        }
    }
}

#Preview {
    ConnectAccountView().environmentObject(AppModel())
}

/// Shared file picker + error alert for Green Button imports.
struct GreenButtonImporter: ViewModifier {
    @EnvironmentObject private var model: AppModel
    @Binding var isPresented: Bool

    static let contentTypes: [UTType] = [.xml, .commaSeparatedText, .plainText, .data]

    func body(content: Content) -> some View {
        content
            .fileImporter(isPresented: $isPresented, allowedContentTypes: Self.contentTypes) { result in
                switch result {
                case .success(let url):
                    Task { await model.importGreenButton(from: url) }
                case .failure(let error):
                    model.importError = error.localizedDescription
                }
            }
            .alert("Couldn't import that file", isPresented: Binding(
                get: { model.importError != nil },
                set: { if !$0 { model.importError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.importError ?? "")
            }
    }
}

extension View {
    func greenButtonImporter(isPresented: Binding<Bool>) -> some View {
        modifier(GreenButtonImporter(isPresented: isPresented))
    }
}
