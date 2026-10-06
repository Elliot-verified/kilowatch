import SwiftUI
import UniformTypeIdentifiers

/// First-run screen. The app works from a Green Button file the user exports
/// from coned.com; there is no server and no account linking. A sample-data
/// mode lets people explore the app before exporting anything.
struct ConnectAccountView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingImporter = false

    static let downloadURL = URL(string: "https://www.coned.com/en/accounts-billing/share-energy-usage-data")!

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "bolt.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.yellow)
                        .padding(.top, 32)
                    Text("Kilowatch")
                        .font(.largeTitle.bold())
                    Text("Understand your Con Edison bill, and see how you stack up against people like you.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text("Get your data from Con Edison")
                        .font(.headline)
                    step(1, "Sign in at coned.com and open My Account, then Usage.")
                    step(2, "Choose Download My Data (Green Button). Pick the longest date range offered and export as CSV or XML.")
                    step(3, "Get the file onto this phone with AirDrop, Files, or email, then import it below.")
                    Link(destination: Self.downloadURL) {
                        Label("Open coned.com", systemImage: "safari")
                            .font(.subheadline.bold())
                    }
                    .padding(.top, 2)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal)

                VStack(alignment: .leading, spacing: 12) {
                    bullet("iphone", "Your file stays on this phone. Kilowatch has no server.")
                    bullet("square.stack.3d.up", "Import more than one export and they merge, so you can build up a full year.")
                    bullet("eye.slash", "Comparisons are a preview with sample neighbors for now.")
                }
                .padding(.horizontal, 28)
                .font(.subheadline)
            }
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                if case .failed(let message) = model.linkState {
                    Text(message).foregroundStyle(.red).font(.footnote)
                }
                Button {
                    showingImporter = true
                } label: {
                    Label("Import your Green Button file", systemImage: "square.and.arrow.down")
                        .bold()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    Task { await model.linkAccount() }
                } label: {
                    HStack {
                        if model.linkState == .linking { ProgressView() }
                        Text(model.linkState == .linking ? "Loading sample…" : "Explore with sample data")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .disabled(model.linkState == .linking)
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .background(.bar)
        }
        .greenButtonImporter(isPresented: $showingImporter)
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)")
                .font(.caption.bold())
                .frame(width: 22, height: 22)
                .background(Circle().fill(.tint))
                .foregroundStyle(.white)
            Text(text).font(.subheadline)
        }
    }

    private func bullet(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).frame(width: 24).foregroundStyle(.tint)
            Text(text)
        }
    }
}

#Preview {
    ConnectAccountView().environmentObject(AppModel(restoreImport: false))
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
