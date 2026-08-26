import SwiftUI

enum AnnualReportPDFPage {
    case incomeStatement
    case balanceSheet
}

/// The printed annual report.
///
/// Its headings are deliberately German in every app language — "ERFOLGSRECHNUNG",
/// "BILANZ", "Jahresgewinn" and the rest. This is the statement handed to the
/// Swiss tax authority, and the German terms are what that document is expected
/// to carry, whichever language the app's own interface is set to. The in-app
/// summary on the Annual Report tab *is* localised; only this page is fixed.
///
/// So: leave the German literals here alone. They are not untranslated strings.
struct AnnualReportPDFView: View {
    let year: Int
    let user: UserSettings
    let report: ReportGenerator
    let page: AnnualReportPDFPage

    private let a4Size = CGSize(width: 595.2, height: 841.8)
    private let margin: CGFloat = 50

    private var yearFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.groupingSeparator = ""
        return formatter
    }

    private var yearString: String {
        yearFormatter.string(from: NSNumber(value: year)) ?? ""
    }

    private var totalPassivenWithEquity: Double {
        report.totalPassiven + report.eigenkapital
    }

    private var bilanzTitle: String {
        String(
            format: NSLocalizedString("BILANZ (per 31.12.%@)", comment: "Balance sheet title with year"),
            yearString
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
                .padding(.bottom, 30)

            if page == .incomeStatement {
                incomeStatementSection
                if report.totalCarKilometers > 0 {
                    fahrtenbuchSection
                        .padding(.top, 24)
                }
                Spacer(minLength: 20)
                netResultSection
            } else {
                balanceSheetSection
                Spacer(minLength: 20)
            }

            footerSection
                .padding(.top, 18)
        }
        .padding(margin)
        .frame(width: a4Size.width, height: a4Size.height)
        .background(Color.white)
        .foregroundColor(.black)
    }

    private var headerSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(user.name)
                    .font(.system(size: 20, weight: .bold))
                Text(user.address.replacingOccurrences(of: ", ", with: "\n"))
                    .font(.system(size: 10))
                    .foregroundColor(Color(white: 0.3))
                Text("IBAN: \(user.iban)")
                    .font(.system(size: 10))
                    .foregroundColor(Color(white: 0.3))
                    .padding(.top, 4)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(page == .incomeStatement ? "ERFOLGSRECHNUNG" : "BILANZ")
                    .font(.system(size: 24, weight: .heavy))
                    .tracking(2)
                Text(yearString)
                    .font(.system(size: 18, weight: .medium))
                Text("01.01.\(yearString) – 31.12.\(yearString)")
                    .font(.system(size: 10))
                    .foregroundColor(Color(white: 0.4))
            }
        }
    }

    private var incomeStatementSection: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 0) {
                PDFSectionTitle(title: "Ertrag (Einnahmen)")
                VStack(spacing: 0) {
                    ForEach(report.incomeByCategory, id: \.category) { item in
                        PDFLineItemRow(title: LocalizedStringKey(item.category), amount: item.total)
                    }
                    PDFTotalRow(title: "Total Ertrag", amount: report.totalIncome)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 0)
                        .stroke(Color(white: 0.75), lineWidth: 0.8)
                )
            }

            VStack(alignment: .leading, spacing: 0) {
                PDFSectionTitle(title: "Aufwand (Ausgaben)")
                VStack(spacing: 0) {
                    ForEach(report.expensesByCategory, id: \.category) { item in
                        PDFLineItemRow(title: LocalizedStringKey(item.category), amount: item.total)
                    }
                    PDFTotalRow(title: "Total Aufwand", amount: report.totalExpenses)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 0)
                        .stroke(Color(white: 0.75), lineWidth: 0.8)
                )
            }
        }
    }

    private var balanceSheetSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            PDFSectionTitle(title: LocalizedStringKey(bilanzTitle))

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 0) {
                    PDFColumnHeader(title: "Aktiven")
                    PDFLineItemRow(title: "Flussige Mittel (Bank/Kasse)", amount: report.liquidAssets)
                    PDFLineItemRow(title: "Anlagevermogen (Inventar)", amount: report.totalAssetBookValue)
                    PDFTotalRow(title: "Total Aktiven", amount: report.totalAktiven)
                }
                .frame(maxWidth: .infinity)
                .overlay(
                    RoundedRectangle(cornerRadius: 0)
                        .stroke(Color(white: 0.75), lineWidth: 0.8)
                )

                VStack(alignment: .leading, spacing: 0) {
                    PDFColumnHeader(title: "Passiven")
                    PDFLineItemRow(title: "Fremdkapital (Schulden)", amount: report.totalPassiven)
                    PDFLineItemRow(title: "Eigenkapital", amount: report.eigenkapital)
                    PDFTotalRow(title: "Total Passiven", amount: totalPassivenWithEquity)
                }
                .frame(maxWidth: .infinity)
                .overlay(
                    RoundedRectangle(cornerRadius: 0)
                        .stroke(Color(white: 0.75), lineWidth: 0.8)
                )
            }
        }
    }

    private var fahrtenbuchSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            PDFSectionTitle(title: "Fahrtenbuch")
            HStack {
                Text("Total gefahrene Kilometer")
                    .font(.system(size: 11))
                Spacer()
                Text("\(report.totalCarKilometers, specifier: "%.2f") km")
                    .font(.system(size: 11))
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            Rectangle()
                .fill(Color(white: 0.82))
                .frame(height: 1)
        }
    }

    private var netResultSection: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.black)
                .frame(height: 2)

            HStack {
                Text(report.netProfit >= 0 ? "Jahresgewinn" : "Jahresverlust")
                    .font(.system(size: 16, weight: .bold))
                    .textCase(.uppercase)
                Spacer()
                Text(report.netProfit, format: .currency(code: "CHF"))
                    .font(.system(size: 16, weight: .bold))
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 10)
            .background(Color(white: 0.95))

            Rectangle()
                .fill(Color.black)
                .frame(height: 1)
            Rectangle()
                .fill(Color.black)
                .frame(height: 1)
                .padding(.top, 2)
        }
    }

    private var footerSection: some View {
        HStack {
            Spacer()
            Text(Date(), style: .date)
                .font(.system(size: 8))
                .foregroundColor(Color(white: 0.5))
        }
    }
}

private struct PDFSectionTitle: View {
    let title: LocalizedStringKey

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .textCase(.uppercase)
            Spacer()
            Text("Betrag (CHF)")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Color(white: 0.4))
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(Color(white: 0.92))
        .overlay(
            Rectangle()
                .stroke(Color(white: 0.8), lineWidth: 0.8)
        )
    }
}

private struct PDFColumnHeader: View {
    let title: LocalizedStringKey

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .textCase(.uppercase)
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(Color(white: 0.95))

        Rectangle()
            .fill(Color(white: 0.85))
            .frame(height: 0.8)
    }
}

private struct PDFLineItemRow: View {
    let title: LocalizedStringKey
    let amount: Double

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 11))
            Spacer()
            Text(amount, format: .currency(code: "CHF").presentation(.narrow))
                .font(.system(size: 11))
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)

        Rectangle()
            .fill(Color(white: 0.9))
            .frame(height: 0.5)
    }
}

private struct PDFTotalRow: View {
    let title: LocalizedStringKey
    let amount: Double

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .bold))
            Spacer()
            Text(amount, format: .currency(code: "CHF"))
                .font(.system(size: 12, weight: .bold))
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 10)

        Rectangle()
            .fill(Color.black)
            .frame(height: 1)
    }
}
