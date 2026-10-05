import SwiftUI

struct CompareView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingInvite = false

    var body: some View {
        List {
            Section("Neighbors") {
                if let comparison = model.neighborComparison {
                    NeighborComparisonCard(comparison: comparison)
                } else if !model.privacy.contributeToNeighborCohort {
                    Text("Neighbor comparison is off. Turn on \"Compare with similar homes\" in Settings to see it.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text("Not enough similar homes nearby yet. We only show comparisons once a cohort has at least 20 households.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }

            Section {
                if model.friendComparisons.isEmpty {
                    Text("No friends yet. Invite someone and, once you both opt in, you'll each see how you compare.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    ForEach(model.friendComparisons) { FriendRow(friend: $0) }
                }
                Button {
                    showingInvite = true
                } label: {
                    Label("Invite a friend", systemImage: "person.badge.plus")
                }
            } header: {
                Text("Friends")
            } footer: {
                Text("Friends see only the percentage difference between you, adjusted for home size. Nobody sees your exact usage unless you turn that on.")
            }
        }
        .navigationTitle("Compare")
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
                marker(at: x(efficient), color: .green, label: "Efficient")
                marker(at: x(median), color: .secondary, label: "Typical")
            }
        }
    }

    private func marker(at x: CGFloat, color: Color, label: String) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(color)
            Rectangle().fill(color).frame(width: 2, height: 28)
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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "person.2.wave.2").font(.system(size: 56)).foregroundStyle(.tint)
                Text("Compare with a friend").font(.title2.bold())
                Text("Send an invite link. When they link their Con Edison account and accept, you'll both see how your usage compares, adjusted for home size.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                ShareLink(item: URL(string: "https://kilowatch.app/invite/demo")!) {
                    Label("Share invite link", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity).padding()
                }
                .buttonStyle(.borderedProminent)
                Spacer()
            }
            .padding()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}
