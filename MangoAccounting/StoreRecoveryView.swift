// StoreRecoveryView.swift
//
// Shown in place of the app when the database cannot be opened. Its whole job is
// to make sure a failed launch never costs the user their records: nothing is
// moved or deleted unless they ask for it here.

import SwiftUI

struct StoreRecoveryView: View {
    @ObservedObject var controller: PersistenceController

    private var failure: StoreLoadFailure? { controller.loadFailure }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundColor(AppTheme.accent)

            Text("Your data could not be opened")
                .font(AppTheme.titleFont)
                .foregroundColor(AppTheme.textPrimary)
                .multilineTextAlignment(.center)

            Text(explanation)
                .font(AppTheme.bodyFont)
                .foregroundColor(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let detail = failure?.message, !detail.isEmpty {
                ScrollView {
                    Text(detail)
                        .font(AppTheme.captionFont)
                        .foregroundColor(AppTheme.textSecondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 90)
                .padding(10)
                .background(AppTheme.cardBackground)
                .cornerRadius(AppTheme.cornerRadius)
            }

            if let backupURL = controller.lastBackupURL {
                VStack(spacing: 6) {
                    Text("Your previous database was kept as a backup.")
                        .font(AppTheme.bodyFont)
                        .foregroundColor(AppTheme.textPrimary)
                    Text(backupURL.lastPathComponent)
                        .font(AppTheme.captionFont)
                        .foregroundColor(AppTheme.textSecondary)
                        .textSelection(.enabled)
                    Button("Show Backup in Finder") { reveal(backupURL) }
                        .buttonStyle(.link)
                        .tint(AppTheme.accent)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(AppTheme.cardBackground)
                .cornerRadius(AppTheme.cornerRadius)
            }

            VStack(spacing: 12) {
                Button("Try Again") { controller.retry() }
                    .buttonStyle(PillButtonStyle())

                if failure?.allowsStartingFresh == true {
                    Button("Back Up My Data and Start Fresh") {
                        controller.backUpAndStartFresh()
                    }
                    .buttonStyle(.borderless)
                    .tint(AppTheme.accent)

                    Text("Your existing database is renamed, never deleted. You can send it to support or restore it later.")
                        .font(AppTheme.captionFont)
                        .foregroundColor(AppTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(28)
        .frame(minWidth: 420, idealWidth: 480, minHeight: 420)
        .background(AppTheme.background.ignoresSafeArea())
    }

    private var explanation: String {
        switch failure {
        case .incompatibleWithModel:
            return String(localized: "The database was created by a version of MangoAccounting that this version cannot read. Quitting and reopening sometimes clears this. Nothing has been changed on disk.")
        case .unreadable:
            return String(localized: "The database file could not be read. This is often temporary — a full disk, a file still in use, or missing permissions. Nothing has been changed on disk.")
        case nil:
            return String(localized: "The database is available again.")
        }
    }

    private func reveal(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.activateFileViewerSelecting([url])
        #endif
    }
}

private extension String {
    /// Small shim so the explanation strings above are still picked up by the
    /// string-catalog extractor while living outside a `Text`.
    init(localized key: String.LocalizationValue) {
        self.init(localized: key, bundle: .main)
    }
}
