//
//  ToastView.swift
//  MangoAccounting
//
//  Created by Luc Lafrenaye on 21.08.2025.
//

import SwiftUI

struct ToastView: View {
    let title: LocalizedStringKey
    
    var body: some View {
        Label(title, systemImage: "checkmark.circle.fill")
            .padding()
            .background(.thinMaterial)
            .foregroundColor(.secondary)
            .clipShape(Capsule())
            .shadow(radius: 10)
            .padding()
    }
}
