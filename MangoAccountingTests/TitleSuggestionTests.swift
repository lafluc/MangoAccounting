//
//  TitleSuggestionTests.swift
//  MangoAccountingTests
//

import Foundation
import Testing
@testable import MangoAccounting

@Suite("Title suggestion ranking")
struct TitleSuggestionRankingTests {

    private func suggestion(_ title: String, uses: Int, daysAgo: Int) -> TitleSuggestion {
        TitleSuggestion(
            title: title,
            useCount: uses,
            lastUsed: Date(timeIntervalSince1970: 1_770_000_000 - Double(daysAgo) * 86_400)
        )
    }

    private var sample: [TitleSuggestion] {
        [
            suggestion("Coffee with client", uses: 12, daysAgo: 3),
            suggestion("Coworking desk", uses: 2, daysAgo: 1),
            suggestion("Train ticket", uses: 7, daysAgo: 40),
            suggestion("Camera lens", uses: 1, daysAgo: 200),
            suggestion("Client dinner", uses: 7, daysAgo: 2),
        ]
    }

    @Test("with nothing typed, the most-used titles come first")
    func ordersByFrequency() {
        let ranked = TitleSuggestionStore.rank(sample, matching: "")
        #expect(ranked.first?.title == "Coffee with client")
        // Equal use counts fall back to the more recent one.
        let sevens = ranked.filter { $0.useCount == 7 }.map(\.title)
        #expect(sevens == ["Client dinner", "Train ticket"])
    }

    @Test("typing filters to matching titles")
    func filtersByQuery() {
        let ranked = TitleSuggestionStore.rank(sample, matching: "cl")
        #expect(Set(ranked.map(\.title)) == ["Client dinner", "Coffee with client"])
    }

    @Test("titles starting with what was typed rank above mid-word matches")
    func prefixMatchesWinEvenWithFewerUses() {
        let ranked = TitleSuggestionStore.rank(sample, matching: "cl")
        // "Client dinner" starts with "cl" and wins despite 7 uses against 12.
        #expect(ranked.first?.title == "Client dinner")
    }

    @Test("matching ignores case and accents")
    func matchingIsCaseAndDiacriticInsensitive() {
        let items = [suggestion("Büro Miete", uses: 3, daysAgo: 1)]
        #expect(TitleSuggestionStore.rank(items, matching: "buro").count == 1)
        #expect(TitleSuggestionStore.rank(items, matching: "BÜRO").count == 1)
        #expect(TitleSuggestionStore.rank(items, matching: "miete").count == 1)
    }

    @Test("a title identical to what is typed is not offered back")
    func exactMatchIsDropped() {
        let ranked = TitleSuggestionStore.rank(sample, matching: "Train ticket")
        #expect(!ranked.contains { $0.title == "Train ticket" })

        // Case and surrounding whitespace still count as identical.
        #expect(!TitleSuggestionStore.rank(sample, matching: "  train TICKET ")
            .contains { $0.title == "Train ticket" })
    }

    @Test("a query matching nothing yields nothing")
    func noMatches() {
        #expect(TitleSuggestionStore.rank(sample, matching: "zzzz").isEmpty)
    }

    @Test("the list is capped so the row stays scannable")
    func respectsLimit() {
        let many = (0..<50).map { suggestion("Title \($0)", uses: $0, daysAgo: 1) }
        #expect(TitleSuggestionStore.rank(many, matching: "").count == TitleSuggestionStore.maximumSuggestions)
        #expect(TitleSuggestionStore.rank(many, matching: "", limit: 3).count == 3)
    }

    @Test("ranking is deterministic when frequency and recency tie")
    func stableOnFullTie() {
        let tied = [
            TitleSuggestion(title: "Beta", useCount: 1, lastUsed: nil),
            TitleSuggestion(title: "Alpha", useCount: 1, lastUsed: nil),
        ]
        #expect(TitleSuggestionStore.rank(tied, matching: "").map(\.title) == ["Alpha", "Beta"])
    }
}
