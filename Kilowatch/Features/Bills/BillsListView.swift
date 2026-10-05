import SwiftUI
import Charts

struct BillsListView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List {
            Section("Last 12 months") {
                Chart(model.sortedBills) { bill in
                    ForEach(ChargeCategory.allCases) { cat in
                        BarMark(x: .value("Month", bill.periodEnd, unit: .month),
                                y: .value("Amount", bill.total(for: cat)))
                            .foregroundStyle(by: .value("Category", cat.title))
                    }
                }
                .chartForegroundStyleScale(
                    domain: ChargeCategory.allCases.map(\.title),
                    range: ChargeCategory.allCases.map(\.color))
                .chartXAxis { AxisMarks(values: .stride(by: .month, count: 2)) }
                .frame(height: 180)
                .padding(.vertical, 4)
            }
            Section {
                ForEach(model.sortedBills) { bill in
                    NavigationLink { BillDetailView(bill: bill) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(Formatters.monthYear(bill.periodEnd)).font(.body)
                                Text("\(Formatters.kWh(bill.kWh)) · \(Formatters.period(bill))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(Formatters.currency(bill.total)).font(.body.monospacedDigit())
                        }
                    }
                }
            }
        }
        .navigationTitle("Bills")
    }
}
