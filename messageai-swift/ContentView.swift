//
//  ContentView.swift
//  messageai-swift
//
//  Created by Nick Kenkel on 10/21/25.
//

import SwiftUI
import Observation
import SwiftData

struct ContentView: View {
    @Environment(AuthService.self) private var authService
    @Environment(FirestoreService.self) private var firestoreService
    @Environment(\.modelContext) private var modelContext
    @State private var hasConfiguredContext = false

    var body: some View {
        Group {
            if let user = authService.currentUser {
                SignedInPlaceholderView(user: user)
            } else {
                AuthView()
            }
        }
        .task {
            guard !hasConfiguredContext else { return }
            authService.configure(modelContext: modelContext, firestoreService: firestoreService)
            hasConfiguredContext = true
        }
    }
}

private struct SignedInPlaceholderView: View {
    let user: AuthService.AppUser
    @Environment(AuthService.self) private var authService

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                    .foregroundStyle(.tint)

                VStack(spacing: 8) {
                    Text("Welcome back, \(user.displayName)!")
                        .font(.title2.weight(.semibold))
                    Text(user.email)
                        .foregroundStyle(.secondary)
                }

                Text("Messaging features will appear here as we build them out.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                Button(role: .destructive) {
                    authService.signOut()
                } label: {
                    Text("Sign Out")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
            .padding()
            .navigationTitle("MessageAI")
        }
    }
}
