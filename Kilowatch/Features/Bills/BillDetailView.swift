import SwiftUI

/// Line-by-line breakdown of one bill with an explanation for every bucket.
struct BillDetailView: View {
    @EnvironmentObject private var model: AppModel
    let bill: Bill
    @State private var expanded: Set<ChargeCategory> = []

    var body: some View {
        List {
            Section {
                CurrentBillCard(bill: bill, previous: model.previousBill(before: bill),
                                isCurrent: bill.id == model.currentBill?.id)
            } footer: {
                if bill.chargesAreEstimated {
                    Label("Usage is from your meter data. Line items are estimated from Con Edison's standard residential rates because Green Button files don't include charges.",
                          systemImage: "info.circle")
                }
            }
            Section("What changed") {
                ForEach(model.insights(for: bill)) { InsightRow(insight: $0) }
            }
            ForEach(ChargeCategory.allCases) { cat in
                let total = bill.total(for: cat)
                if total != 0 || !bill.charges.filter({ $0.category == cat }).isEmpty {
                    Section {
                        DisclosureGroup(isExpanded: binding(for: cat)) {
                            Text(cat.explanation)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 4)
                        } label: {
                            HStack {
                                Circle().fill(cat.color).frame(width: 10, height: 10)
                                Text(cat.title).bold()
                                Spacer()
                                Text(Formatters.currency(total)).monospacedDigit()
                            }
                        }
                        ForEach(bill.charges.filter { $0.category == cat }) { charge in
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(charge.name).font(.subheadline)
                                    if let detail = charge.detail {
                                        Text(detail).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text(Formatters.currency(charge.amount))
                                    .font(.subheadline.monospacedDigit())
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(Formatters.billMonth(bill))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func binding(for cat: ChargeCategory) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(cat) },
            set: { isOn in if isOn { expanded.insert(cat) } else { expanded.remove(cat) } })
    }
}
