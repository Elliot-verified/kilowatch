# Kilowatch

An iOS app that links to a customer's Con Edison account, explains their electric bill in plain English, and shows how their usage compares with similar homes nearby and with friends who opt in.

## Product sketch

### Who it's for
New York City residents who get a Con Edison bill, don't understand why it changed, and want to know whether they are using more electricity than they should.

### Core flows

1. **Connect** — One screen. The user taps "Connect Con Edison", signs in on Con Edison's own site, and grants Kilowatch read access to bills and meter data. Kilowatch never sees the password.
2. **Home** — The current bill: total, change vs. last period, kWh, per-day usage, all-in price per kWh, and a stacked bar showing supply vs. delivery vs. taxes. Below it, a short list of "what changed" insights and a 30-day usage chart.
3. **Bills** — Twelve months of bills as a stacked bar chart, then a list. Tapping a bill opens the breakdown.
4. **Bill detail** — Every line item grouped into Supply, Delivery, Taxes & fees, and Adjustments. Each group expands to a plain-English explanation of what it is and whether the customer can do anything about it.
5. **Compare** — "You use 14% more than similar homes" with a scale showing efficient, typical, and you. Below, a list of friends and the percentage difference between you.
6. **Settings** — Home profile (type, bedrooms, people, AC, electric heat) used for fair cohorts, and privacy toggles.

### The "what changed" engine
The bill explainer (`Kilowatch/Models/Insight.swift`) is the heart of the app. For each bill it separates the two things that move a bill:

- **Usage** — kWh per day vs. the previous period (per day, so 28-day and 33-day bills compare fairly) and vs. the same period last year.
- **Price** — supply cost per kWh, which Con Edison passes through from the wholesale market and the customer cannot control.

It also tells the user what share of the bill is delivery (fixed by regulators, unchanged by switching suppliers) and flags estimated meter readings, which cause confusing true-ups.

### Comparison feature
- **Neighbors**: the backend groups opted-in households by ZIP, home type, bedrooms, and heating/cooling type, then returns the median, the 20th percentile ("efficient"), and the user's percentile for the same billing period. A cohort is only returned if it has at least 20 households, so nobody can be re-identified.
- **Friends**: mutual opt-in via an invite link. By default a friend sees only the percentage difference, normalized per bedroom. Showing exact kWh is a separate opt-in per user.

## Architecture

```
iOS app (SwiftUI, iOS 17)
  ├─ Features/        screens, one folder per tab
  ├─ Models/          Bill, BillCharge, UsageInterval, comparisons, BillExplainer
  ├─ Services/        UtilityDataProvider, ComparisonService (protocols + mocks)
  └─ App/             AppModel (single observable source of truth), RootView

Kilowatch backend (not in this repo)
  ├─ Utility data ingestion   Con Edison data-sharing authorization, bill + interval sync
  ├─ Bill normalizer          maps Con Edison line items → ChargeCategory
  └─ Comparison service       cohort aggregation with k-anonymity, friend graph, consent
```

The app currently runs entirely on `MockUtilityDataProvider` and `MockComparisonService`, which return deterministic sample data shaped like a real Brooklyn apartment account. Swapping in real implementations is the only change needed to go live; the views don't know the difference.

### Getting Con Edison data
Con Edison has no public API for customers. Options, in order of preference:

1. **Con Edison Share My Data (Green Button Connect My Data)** — the OAuth-style flow NY utilities offer to authorized third parties. Requires registering Kilowatch with Con Edison. Gives bills and 15-minute interval data without ever handling credentials. Needs verification of current program status and onboarding time.
2. **Utility data aggregator** (UtilityAPI, Arcadia) — hosted connection to Con Edison, faster to launch, per-account cost.
3. **Green Button Download My Data** — user exports a file from their Con Edison account and imports it. Zero integration work, worst UX. Useful as a fallback or for a demo.

Credential-based scraping is ruled out: it puts the customer's password in our hands and violates Con Edison's terms.

## Building

Requires Xcode 15 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
xcodegen generate
open Kilowatch.xcodeproj
```

Run the `Kilowatch` scheme on any iPhone simulator. Tests are in `KilowatchTests`.

## Open questions

- Which data-access route (Share My Data vs. aggregator) and the cost/timeline of each.
- Whether the first version needs a backend at all, or can ship with import-a-file and on-device insights.
- Gas: Con Edison bills many customers for gas on the same bill. Out of scope for v1, but the `ChargeCategory` model would need a fuel dimension.
- How to verify "neighbors" without an address on file for every user. ZIP plus self-reported home profile is the current plan.
