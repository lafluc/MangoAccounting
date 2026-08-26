# MangoAccounting

A macOS bookkeeping app for Swiss self-employment: transactions with receipts,
assets with ESTV depreciation, an annual report (Erfolgsrechnung and Bilanz) as
PDF, and invoices with a Swiss QR payment code.

Built with SwiftUI and Core Data. macOS 15.5 or later.

## Layout

| Path | What it holds |
|---|---|
| `MangoAccounting/` | app sources; the folder is synchronised into the Xcode target, so new files are picked up automatically |
| `TransactionItem+CoreData*.swift` | the `TransactionItem` entity, at the repository root and explicit members of the build phase |
| `MangoAccounting/MangoAccounting.xcdatamodeld/` | the Core Data model |
| `Localizable.xcstrings` | all UI strings, in English, German and Oberfränkisch |
| `MangoAccountingTests/` | unit tests |
| `scripts/` | maintenance scripts for the string catalog and the theme colours |
| `distribution/` | release build and notarisation instructions |

## Working on it

Open `MangoAccounting.xcodeproj`. Run the tests before shipping anything:

```
xcodebuild test -project MangoAccounting.xcodeproj -scheme MangoAccounting -destination 'platform=macOS,arch=arm64'
```

Two generated files are maintained by script rather than by hand, so their values
stay reviewable in one place:

```
python3 scripts/update_localizations.py     # Localizable.xcstrings
python3 scripts/generate_theme_colors.py    # theme colour sets, with contrast checks
```

The colour script fails rather than writing a palette that misses WCAG AA.

## Things worth knowing before changing them

- **The bundle identifier is load-bearing.** The app is sandboxed, so users' data
  lives in a container keyed by it. Changing it orphans every existing install.
- **The generated annual report PDF is deliberately German** in every app
  language. It is the statement handed to the tax authority. The in-app summary on
  the same tab *is* localised.
- **Money is `Double`,** so every total goes through `Money.roundToCents` and
  totals are summed from already-rounded rows. That is what keeps a printed
  column adding up to the total printed beneath it.
- **Fiscal years go through `FiscalCalendar`,** never `Calendar.current`: a
  1 January Zurich entry is stored as 31 December 23:00 UTC and would otherwise
  be reported in the wrong tax year on a machine set to a western time zone.
- **Invoices created from version 1.1 store their source** as a
  `*.invoice.json` sidecar beside the PDF, which is what makes them re-openable.
  Invoices archived by earlier versions have no sidecar and stay view-and-export
  only — their line items were never recorded anywhere. "Duplicate as New
  Invoice" is the way to bring one forward.

## Distribution

See [distribution/README.md](distribution/README.md).
