// AlertPresentation.swift

import SwiftUI

/// One alert's worth of content.
///
/// SwiftUI honours only a **single** `.alert` modifier per view. Stacking two
/// means the second silently replaces the first, and the first never appears —
/// which is exactly what happened when error alerts were added alongside the
/// existing delete confirmations. Views therefore hold one `AlertRequest?` and
/// present it with `.appAlert(_:)`, so there is only ever one alert modifier and
/// the mistake cannot recur.
struct AlertRequest: Identifiable {

    struct Action {
        var label: LocalizedStringKey
        var role: ButtonRole?
        var handler: () -> Void
    }

    let id = UUID()
    var title: LocalizedStringKey
    var message: Text
    /// Shown next to Cancel. When `nil` the alert has a single OK button.
    var confirm: Action?

    /// A failure the user needs to know about but cannot act on.
    static func error(_ title: LocalizedStringKey, _ message: String) -> AlertRequest {
        AlertRequest(title: title, message: Text(message), confirm: nil)
    }

    /// A question with a destructive answer.
    static func confirm(
        title: LocalizedStringKey,
        message: Text,
        label: LocalizedStringKey,
        role: ButtonRole? = .destructive,
        action: @escaping () -> Void
    ) -> AlertRequest {
        AlertRequest(
            title: title,
            message: message,
            confirm: Action(label: label, role: role, handler: action)
        )
    }
}

extension View {
    /// Presents whatever alert the view currently wants, through one modifier.
    func appAlert(_ request: Binding<AlertRequest?>) -> some View {
        alert(
            request.wrappedValue?.title ?? "",
            isPresented: Binding(
                get: { request.wrappedValue != nil },
                set: { if !$0 { request.wrappedValue = nil } }
            ),
            presenting: request.wrappedValue
        ) { pending in
            if let confirm = pending.confirm {
                Button(confirm.label, role: confirm.role) {
                    request.wrappedValue = nil
                    confirm.handler()
                }
                Button("Cancel", role: .cancel) { request.wrappedValue = nil }
            } else {
                Button("OK", role: .cancel) { request.wrappedValue = nil }
            }
        } message: { pending in
            pending.message
        }
    }
}
