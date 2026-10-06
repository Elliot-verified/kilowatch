import SwiftUI

struct CompareView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingInvite = false

    var body: some View {
        List {
            if model.usingSampleComparisons {
                Section {
                    Label("These are sample neighbors and friends. Import your Green Button data to compare for real.",
                          systemImage: "info.circle")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            } else if let error = model.comparisonError {
                Section {
                    Label(error, systemImage: "wifi.exclamationmark")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Try again") { Task { await model.refreshComparisons() } }
                }
            }

            Section("Neighbors") {
                if let comparison = model.neighborComparison {
                    NeighborComparisonCard(comparison: comparison)
                } else if !model.privacy.contributeToNeighborCohort {
                    Text("Neighbor comparison is off. Turn on \"Compare with similar homes\" in Settings to see it.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else if model.effectiveZip.count != 5 {
                    Text("Add your ZIP code in Settings so we can find similar homes nearby.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text("Not enough similar homes nearby yet. Comparisons appear once at least 20 households in your area have joined, and they refresh every few hours.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }

            Section {
                if model.friendComparisons.isEmpty {
                    Text("No friends yet. Share an invite code and, once you both opt in, you'll each see how you compare.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    ForEach(model.friendComparisons) { FriendRow(friend: $0) }
                }
                Button {
                    showingInvite = true
                } label: {
                    Label("Invite or add a friend", systemImage: "person.badge.plus")
                }
            } header: {
                Text("Friends")
            } footer: {
                Text("Friends see only the percentage difference between you, adjusted for home size. Nobody sees your exact usage unless you turn that on.")
            }
        }
        .navigationTitle("Compare")
        .refreshable { await model.refreshComparisons() }
        .sheet(isPresented: $showingInvite) { InviteFriendSheet() }
    }
}

struct NeighborComparisonCard: View {
    let comparison: CohortComparison

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(headline).font(.title3.bold())
                Text("Compared with \(comparison.householdCount) \(comparison.cohortDescription) over the same billing period.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            UsageScale(you: comparison.yourKWh, efficient: comparison.efficientKWh, median: comparison.medianKWh)
                .frame(height: 64)
            HStack {
                legend(.green, "Efficient", Formatters.kWh(comparison.efficientKWh))
                legend(.secondary, "Typical", Formatters.kWh(comparison.medianKWh))
                legend(.yellow, "You", Formatters.kWh(comparison.yourKWh))
            }
        }
        .padding(.vertical, 6)
    }

    private var headline: String {
        let pct = Formatters.percent(abs(comparison.deltaFromMedian))
        if comparison.deltaFromMedian > 0.03 { return "You use \(pct) more than similar homes" }
        if comparison.deltaFromMedian < -0.03 { return "You use \(pct) less than similar homes" }
        return "You're right in line with similar homes"
    }

    private func legend(_ color: Color, _ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(.caption2).foregroundStyle(.secondary)
                Text(value).font(.caption.bold())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Horizontal scale with markers for efficient, typical, and you.
struct UsageScale: View {
    let you: Double
    let efficient: Double
    let median: Double

    var body: some View {
        GeometryReader { geo in
            let maxValue = max(you, median, efficient) * 1.25
            let width = geo.size.width
            let x: (Double) -> CGFloat = { CGFloat($0 / maxValue) * width }

            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary).frame(height: 12).frame(maxHeight: .infinity)
                Capsule().fill(.yellow).frame(width: x(you), height: 12).frame(maxHeight: .infinity)
                // Labels sit on opposite sides of the bar so they never collide.
                marker(at: x(efficient), color: .green, label: "Efficient", labelAbove: true)
                marker(at: x(median), color: .secondary, label: "Typical", labelAbove: false)
            }
        }
    }

    private func marker(at x: CGFloat, color: Color, label: String, labelAbove: Bool) -> some View {
        VStack(spacing: 2) {
            if labelAbove { Text(label).font(.caption2).foregroundStyle(color) }
            Rectangle().fill(color).frame(width: 2, height: 28)
            if !labelAbove { Text(label).font(.caption2).foregroundStyle(color) }
        }
        .fixedSize()
        .position(x: x, y: 32)
    }
}

struct FriendRow: View {
    let friend: FriendComparison

    var body: some View {
        HStack {
            Circle().fill(.tint.opacity(0.2)).frame(width: 36, height: 36)
                .overlay(Text(String(friend.displayName.prefix(1))).bold())
            VStack(alignment: .leading, spacing: 2) {
                Text(friend.displayName).font(.body)
                Text(friend.sharesExactUsage && friend.kWh != nil
                     ? "\(Formatters.kWh(friend.kWh ?? 0)) this period"
                     : "Shares relative usage only")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(friend.deltaFromYou >= 0
                 ? "+\(Formatters.percent(friend.deltaFromYou))"
                 : "−\(Formatters.percent(-friend.deltaFromYou))")
                .font(.subheadline.bold().monospacedDigit())
                .foregroundStyle(friend.deltaFromYou >= 0 ? .orange : .green)
        }
    }
}

struct InviteFriendSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var myCode: String?
    @State private var enteredCode = ""
    @State private var status: String?
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let code = myCode {
                        HStack {
                            Text(code).font(.title2.monospaced().bold())
                            Spacer()
                            ShareLink(item: "Compare electricity use with me on Kilowatch. My invite code is \(code).") {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                        }
                    } else {
                        Button {
                            Task {
                                busy = true; defer { busy = false }
                                do { myCode = try await model.createInvite(); status = nil }
                                catch { status = error.localizedDescription }
                            }
                        } label: {
                            HStack { if busy { ProgressView() }; Text("Get my invite code") }
                        }
                        .disabled(busy)
                    }
                } header: {
                    Text("Invite a friend")
                } footer: {
                    Text("Codes work for 14 days and once each. Your friend enters it below on their phone.")
                }

                Section {
                    TextField("K7M3-PX9Q", text: $enteredCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                    Button("Add friend") {
                        Task {
                            busy = true; defer { busy = false }
                            do {
                                let name = try await model.acceptInvite(code: enteredCode)
                                status = "You and \(name) are now comparing."
                                enteredCode = ""
                            } catch {
                                status = error.localizedDescription
                            }
                        }
                    }
                    .disabled(busy || enteredCode.trimmingCharacters(in: .whitespaces).count < 8)
                } header: {
                    Text("Have a friend's code?")
                }

                if let status {
                    Section { Text(status).font(.footnote) }
                }
            }
            .navigationTitle("Friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.large])
    }
}
