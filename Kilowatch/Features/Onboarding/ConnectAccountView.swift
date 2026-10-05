import SwiftUI

/// First-run screen. Explains what linking does and kicks off the flow.
struct ConnectAccountView: View {
    @EnvironmentObject private var model: AppModel

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
            .padding(.bottom)
        }
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
