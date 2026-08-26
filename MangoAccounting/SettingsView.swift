// SettingsView.swift

import SwiftUI
import UniformTypeIdentifiers
import CoreData

struct SettingsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var settings = UserSettings()
    @AppStorage(AppAppearance.storageKey) private var appearanceRaw: String =
        AppAppearance.defaultValue.rawValue
    
    var body: some View {
        settingsForm
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle(Text("Settings"))
    }
    
    private var settingsForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SectionView(title: "Your Information") {
                    CardView {
                        VStack {
                            TextField("Name", text: $settings.name)
                            Divider()
                            TextField("Address", text: $settings.address, axis: .vertical).lineLimit(1...4)
                            Divider()
                            // ADDITION: New TextField for the UID
                            TextField("UID (CHE-...)", text: $settings.uid)
                            Divider()
                            TextField("IBAN (CH…)", text: $settings.iban)
                        }
                    }
                }
                
                SectionView(title: "Language") {
                    Picker("Language", selection: $settings.language) {
                        Text("English").tag("en")
                        Text("German").tag("de")
                        Text("Oberfränkisch").tag("frk")
                    }
                    .pickerStyle(.segmented)
                    .padding(4)
                    .background(AppTheme.cardBackground)
                    .cornerRadius(12)
                }
                
                SectionView(title: "Appearance") {
                    Picker("Appearance", selection: $appearanceRaw) {
                        ForEach(AppAppearance.allCases) { option in
                            Label(option.label, systemImage: option.symbolName)
                                .tag(option.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(4)
                    .background(AppTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
                }

                // Was gated to iOS, yet macOS is the only platform that actually
                // uses tabOrder — through the custom tab bar — so macOS users had
                // no way to reorder their tabs at all.
                SectionView(title: "Tabs") {
                    CardView {
                        NavigationLink(destination: TabOrderSettingsView(settings: settings)) {
                            HStack {
                                Text("Customize Tab Order")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                            }
                            .foregroundColor(AppTheme.accent)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
        }
    }
}
