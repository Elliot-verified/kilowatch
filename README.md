# Kilowatch

An iOS app that links to a customer's Con Edison account, explains their electric bill in plain English, and shows how their usage compares with similar homes nearby and with friends who opt in.

## Product sketch

### Who it's for
New York City residents who get a Con Edison bill, don't understand why it changed, and want to know whether they are using more electricity than they should.

### Core flows

1. **Get data** — One screen with the three steps to export a Green Button file from coned.com, an import button, and a sample-data mode for exploring the app first. There is no account linking and no server in this version; see "Getting Con Edison data" below for why. Several exports merge, so a user can build up a full year.
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

backend/ (deployed at https://kilowatch-api.vercel.app, Vercel project kilowatch-api)
  ├─ api/                     Vercel Functions: register, me, usage, comparison, invites, cron
  ├─ lib/cohorts.ts           cohort aggregation, k-anonymity (20 households), fallback cohorts
  ├─ lib/friends.ts           mutual opt-in friend comparison rules
  └─ lib/store.ts             private Vercel Blob store (or in-memory for tests)
```

The backend deploys automatically from `backend/` on every push to `main`. Cohorts recompute daily at 09:00 UTC (Vercel Hobby allows one cron run per day). See `backend/README.md` for the API.

Sample-data mode runs on `MockUtilityDataProvider` and `MockComparisonService`. With an imported Green Button file, usage comes from `ImportedUtilityDataProvider` and comparisons from `RemoteComparisonService`, which talks to the backend. The API base URL is `KilowatchAPIBaseURL` in Info.plist (set in `project.yml`); a launch argument of the same name overrides it for local testing against `npm run dev` in `backend/`.

### Getting Con Edison data
Con Edison has no public API for customers. The options:

1. **Green Button Download My Data** — **what v1 uses.** The user exports a file from coned.com (Usage → Download My Data) and imports it. Works offline with no backend.
2. **Con Edison Share My Data (Green Button Connect My Data)** — OAuth 2.0 access for registered third parties, with 15-minute intervals, billing data, and two years of history, free of charge. Requires registering as a company, signing Con Edison's Data Security Agreement, and a 30–60 day technical onboarding against their test environment. Tokens and batch notifications need a server. Deferred: the parser already handles the ESPI XML it returns, so adding it later is server plumbing plus a new `UtilityDataProvider`.
3. **Utility data aggregator** (UtilityAPI, Arcadia) — hosted connection to Con Edison, per-account cost. Also needs a server.

### Green Button import
`Kilowatch/Services/GreenButton/` handles both export formats:

- **CSV** (`GreenButtonCSVParser`): Con Edison's `TYPE,DATE,START TIME,END TIME,USAGE,UNITS,COST,NOTES` layout, with the name/address/account preamble. Columns are matched by name, gas rows are skipped, daily reads without times are supported.
- **ESPI XML** (`GreenButtonXMLParser`): the Atom feed. Readings are scaled by the ReadingType's power-of-ten multiplier; uom 72 is Wh; costs are in 1/100000 dollars; `ElectricPowerUsageSummary` gives billing periods and totals when present.

Green Button files carry usage and sometimes a period total, never line items. `BillBuilder` groups intervals into billing periods (the file's own periods, or calendar months with at least 20 days of data) and `ConEdRateModel` produces a line-item breakdown from Con Edison's standard residential rate. When the file has a real total, the breakdown is scaled to match it. Such bills are flagged `chargesAreEstimated` and the UI says so. The last import is persisted in Application Support so the app reopens to it.

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
