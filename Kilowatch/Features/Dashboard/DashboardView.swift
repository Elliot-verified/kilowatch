import SwiftUI
import Charts

struct DashboardView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List {
            if let bill = model.currentBill {
                Section {
                    CurrentBillCard(bill: bill, previous: model.previousBill(before: bill))
                }
                Section("What changed") {
                    ForEach(model.insights(for: bill)) { InsightRow(insight: $0) }
                }
            }
            if !model.dailyUsage.isEmpty {
                Section("Last 30 days") {
                    DailyUsageChart(usage: model.dailyUsage)
                        .frame(height: 160)
                        .padding(.vertical, 4)
                }
            }
            if let neighbors = model.neighborComparison {
                Section {
                    NavigationLink { CompareView() } label: {
                        NeighborSummaryRow(comparison: neighbors)
                    }
                }
            }
        }
        .navigationTitle(model.account?.shortAddress ?? "Home")
        .refreshable { await model.refresh() }
    }
}

struct CurrentBillCard: View {
    let bill: Bill
    let previous: Bill?
    var isCurrent: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(isCurrent ? "Current bill" : "Bill") · \(Formatters.period(bill))\(bill.chargesAreEstimated ? " · charges estimated" : "")")
                .font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline) {
                Text(Formatters.currency(bill.total)).font(.system(size: 40, weight: .bold, design: .rounded))
                if let previous {
                    let delta = bill.total - previous.total
                    Label(Formatters.signedCurrency(delta), systemImage: delta >= 0 ? "arrow.up" : "arrow.down")
                        .font(.subheadline.bold())
                        .foregroundStyle(delta >= 0 ? .red : .green)
                }
            }
            HStack(spacing: 16) {
                stat("Usage", Formatters.kWh(bill.kWh))
                stat("Per day", Formatters.kWh(bill.kWhPerDay))
                stat("Per kWh", Formatters.cents(bill.effectiveRatePerKWh))
                stat("Due", Formatters.shortDate(bill.dueDate))
            }
            CategoryBar(bill: bill).frame(height: 10)
        }
        .padding(.vertical, 6)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.footnote.bold())
        }
    }
}

/// Stacked bar showing how the bill splits across categories.
struct CategoryBar: View {
    let bill: Bill

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(ChargeCategory.allCases) { cat in
                    let share = bill.total > 0 ? bill.total(for: cat) / bill.total : 0
                    if share > 0 {
                        Rectangle().fill(cat.color).frame(width: max(2, geo.size.width * share))
                    }
                }
            }
            .clipShape(Capsule())
        }
    }
}

struct InsightRow: View {
    let insight: Insight

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: insight.symbol)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 3) {
                Text(insight.title).font(.subheadline.bold())
                Text(insight.detail).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var color: Color {
        switch insight.tone {
        case .neutral: return .blue
        case .good: return .green
        case .warning: return .orange
        }
    }
}

struct DailyUsageChart: View {
    let usage: [UsageInterval]

    var body: some View {
        Chart(usage) { day in
            BarMark(x: .value("Day", day.start, unit: .day), y: .value("kWh", day.kWh))
                .foregroundStyle(.yellow.gradient)
        }
        .chartYAxisLabel("kWh")
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.abbreviated).day(), collisionResolution: .greedy)
            }
        }
    }
}

struct NeighborSummaryRow: View {
    let comparison: CohortComparison

    var body: some View {
        HStack {
            Image(systemName: "person.3").foregroundStyle(.tint)
            VStack(alignment: .leading) {
                Text(comparison.deltaFromMedian >= 0
                     ? "You used \(Formatters.percent(comparison.deltaFromMedian)) more than similar homes"
                     : "You used \(Formatters.percent(-comparison.deltaFromMedian)) less than similar homes")
                    .font(.subheadline.bold())
                Text(comparison.cohortDescription).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

extension ChargeCategory {
    var color: Color {
        switch self {
        case .supply: return .orange
        case .delivery: return .blue
        case .taxesAndFees: return .gray
        case .adjustments: return .purple
        }
    }
}
