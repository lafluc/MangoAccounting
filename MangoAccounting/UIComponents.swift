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
                .accessibilityHidden(true)

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
            // Direction is otherwise conveyed by icon and colour alone, which is
            // invisible to VoiceOver and to anyone who cannot distinguish the two.
            Image(systemName: transaction.type == "Income" ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                .font(.title2)
                .foregroundColor(transaction.type == "Income" ? AppTheme.positive : AppTheme.negative)
                .frame(width: 25, alignment: .center)
                .accessibilityLabel(transaction.type == "Income" ? "Income" : "Expense")

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

/// Strip of title suggestions shown beneath the description field.
///
/// Wraps onto further lines rather than scrolling horizontally: with up to eight
/// chips a scroller would hide most of them behind an edge the user has no reason
/// to suspect, and a nested horizontal scroller also fights the form's own
/// vertical one for space.
struct TitleSuggestionRow: View {
    let suggestions: [TitleSuggestion]
    let onSelect: (TitleSuggestion) -> Void

    var body: some View {
        WrappingHStack(spacing: 6, lineSpacing: 6) {
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
    }
}

/// Lays subviews out left to right, wrapping to a new line when the next one will
/// not fit.
///
/// SwiftUI has no built-in wrapping stack, and the alternatives — a horizontal
/// `ScrollView`, or a `LazyVGrid` with fixed columns — either hide content or
/// force every item to a common width, which looks wrong for chips of varying
/// length.
struct WrappingHStack: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = arrange(subviews: subviews, in: maxWidth)

        let height = rows.reduce(into: CGFloat.zero) { total, row in
            total += row.height
        } + lineSpacing * CGFloat(max(0, rows.count - 1))

        let widest = rows.map(\.width).max() ?? 0
        return CGSize(width: min(widest, maxWidth), height: height)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        let rows = arrange(subviews: subviews, in: bounds.width)
        var y = bounds.minY

        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(subviews: Subviews, in maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let widthIfAdded = current.indices.isEmpty
                ? size.width
                : current.width + spacing + size.width

            if !current.indices.isEmpty && widthIfAdded > maxWidth {
                rows.append(current)
                current = Row()
                current.indices = [index]
                current.width = size.width
                current.height = size.height
            } else {
                current.indices.append(index)
                current.width = widthIfAdded
                current.height = max(current.height, size.height)
            }
        }

        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
