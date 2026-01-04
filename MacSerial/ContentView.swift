//
//  ContentView.swift
//  MacSerial
//
//  Created by Tomosawa on 2025/12/19.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        MainTabView()
            .frame(minWidth: 1120, maxWidth: .infinity, minHeight: 700, maxHeight: .infinity)
    }
}

#Preview {
    ContentView()
        .frame(minWidth: 1120, maxWidth: .infinity, minHeight: 700, maxHeight: .infinity)
}
