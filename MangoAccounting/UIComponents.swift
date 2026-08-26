// UIComponents.swift

import SwiftUI

struct PlaceholderView: View {
    let systemImageName: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: systemImageName)
                .font(.system(size: 50, weight: .light))
                .foregroundColor(AppTheme.accent.opacity(0.7))

            VStack(spacing: 4) {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .foregroundColor(AppTheme.textPrimary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.background.ignoresSafeArea())
    }
}

struct TransactionRowView: View {
    @ObservedObject var transaction: TransactionItem

    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: transaction.type == "Income" ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                .font(.title2)
                .foregroundColor(transaction.type == "Income" ? AppTheme.positive : AppTheme.negative)
                .frame(width: 25, alignment: .center)

            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.details ?? "—")
                    .font(.headline)
                    .foregroundColor(AppTheme.textPrimary)
                    .lineLimit(1)
                
                HStack(spacing: 6) {
                    Text(transaction.category ?? "Uncategorized")
                        .font(.caption)
                        .foregroundColor(AppTheme.textSecondary)
                    
                    // Show original currency if different from CHF
                    if let code = transaction.currencyCode, code != "CHF", transaction.originalAmount > 0 {
                        Text("(\(code) \(String(format: "%.2f", transaction.originalAmount)))")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(AppTheme.textSecondary.opacity(0.2))
                            .cornerRadius(4)
                            .foregroundColor(AppTheme.textSecondary)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                // Main display is always CHF so the math checks out visually
                Text(transaction.amount, format: .currency(code: "CHF"))
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundColor(transaction.type == "Income" ? AppTheme.positive : AppTheme.negative)
                Text(transaction.date ?? .now, style: .date)
                    .font(.caption)
                    .foregroundColor(AppTheme.textSecondary)
            }
        }
        .padding(.vertical, 8)
    }
}

struct SectionView<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(AppTheme.headlineFont)
                .foregroundColor(AppTheme.textSecondary)
            content
        }
    }
}

/// A tappable chip, used for previously-used transaction titles.
///
/// The app had no reusable chip: the nearest visuals were inlined in
/// `TransactionRowView` and the dashboard's timeframe picker.
struct SuggestionChip: View {
    let title: String
    let detail: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title)
                    .lineLimit(1)
                if let detail {
                    Text(detail)
                        .foregroundColor(AppTheme.textSecondary)
                }
            }
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(AppTheme.accent.opacity(0.16))
            .foregroundColor(AppTheme.textPrimary)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(AppTheme.accent.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// Horizontal strip of title suggestions shown beneath the description field.
struct TitleSuggestionRow: View {
    let suggestions: [TitleSuggestion]
    let onSelect: (TitleSuggestion) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(suggestions) { suggestion in
                    SuggestionChip(
                        title: suggestion.title,
                        detail: suggestion.useCount > 1 ? "\(suggestion.useCount)\u{00D7}" : nil
                    ) {
                        onSelect(suggestion)
                    }
                    .help("Use this title and fill in its usual type, category and currency")
                }
            }
            .padding(.vertical, 2)
        }
        // A horizontal scroller inside a vertical one needs a fixed height or it
        // fights the outer ScrollView for space.
        .frame(height: 30)
    }
}
