//
//  ProfileView.swift
//  messageai-swift
//
//  Created by Nick Kenkel on 11/19/25.
//

import Foundation
import PhotosUI
import SwiftUI
import UIKit

struct ProfileView: View {
    let user: AuthService.AppUser
    let onSignOut: () -> Void
    let showsDismissButton: Bool

    init(
        user: AuthService.AppUser,
        onSignOut: @escaping () -> Void,
        showsDismissButton: Bool = true
    ) {
        self.user = user
        self.onSignOut = onSignOut
        self.showsDismissButton = showsDismissButton
    }

    @Environment(AuthService.self) private var authService
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isUpdatingPhoto = false
    @State private var photoError: String?

    private var displayedUser: AuthService.AppUser {
        authService.currentUser ?? user
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 12) {
                        ProfileAvatar(
                            photoURL: displayedUser.photoURL,
                            initials: initials(for: displayedUser.displayName),
                            isUpdating: isUpdatingPhoto
                        )
                            .frame(width: 96, height: 96)

                        Text(displayedUser.displayName)
                            .font(.title2.weight(.semibold))

                        Text(displayedUser.email)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        PhotosPicker(
                            selection: $selectedPhotoItem,
                            matching: .images,
                            photoLibrary: .shared()
                        ) {
                            HStack {
                                Image(systemName: "camera.fill")
                                Text(isUpdatingPhoto ? "Updating..." : "Change Photo")
                            }
                        }
                        .disabled(isUpdatingPhoto)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
                }

                Section("Account") {
                    LabeledContent("Email", value: displayedUser.email)
                    LabeledContent("User ID", value: displayedUser.id)
                }

                Section {
                    Button(role: .destructive, action: signOut) {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showsDismissButton {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
            }
            .alert(
                "Unable to update photo",
                isPresented: .init(
                    get: { photoError != nil },
                    set: { if !$0 { photoError = nil } }
                ),
                actions: {
                    Button("OK", role: .cancel) { photoError = nil }
                },
                message: {
                    Text(photoError ?? "Unknown error")
                }
            )
            .onChange(of: selectedPhotoItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    await handlePhotoSelection(newItem)
                }
            }
        }
    }

    private func signOut() {
        onSignOut()
        if showsDismissButton {
            dismiss()
        }
    }

    private func initials(for name: String) -> String {
        let components = name.split(separator: " ")
        let initials = components.prefix(2).compactMap { $0.first }.map(String.init)
        return initials.joined().uppercased()
    }

    @MainActor
    private func handlePhotoSelection(_ item: PhotosPickerItem) async {
        isUpdatingPhoto = true
        defer {
            selectedPhotoItem = nil
            isUpdatingPhoto = false
        }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                photoError = "Selected image could not be loaded."
                return
            }
            guard let image = UIImage(data: data) else {
                photoError = "Unsupported image format."
                return
            }

            guard let jpegData = image.scaled(toMaxDimension: 512)?.jpegData(compressionQuality: 0.8) else {
                photoError = "Failed to process image."
                return
            }

            await authService.updateProfilePhoto(with: jpegData)

            if let message = authService.errorMessage {
                photoError = message
            }
        } catch {
            photoError = error.localizedDescription
        }
    }
}

private struct ProfileAvatar: View {
    let photoURL: URL?
    let initials: String
    let isUpdating: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.2))

            if let photoURL {
                AsyncImage(url: photoURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        Text(initials.isEmpty ? "?" : initials)
                            .font(.title.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    case .empty:
                        ProgressView()
                    @unknown default:
                        EmptyView()
                    }
                }
                .clipShape(Circle())
            } else {
                Text(initials.isEmpty ? "?" : initials)
                    .font(.title.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }

            if isUpdating {
                Circle()
                    .fill(Color.black.opacity(0.35))
                ProgressView()
                    .tint(.white)
            }
        }
    }
}

private extension UIImage {
    func scaled(toMaxDimension maxDimension: CGFloat) -> UIImage? {
        let maxSide = max(size.width, size.height)
        guard maxSide > maxDimension else { return self }

        let scale = maxDimension / maxSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        UIGraphicsBeginImageContextWithOptions(newSize, false, 0)
        defer { UIGraphicsEndImageContext() }

        draw(in: CGRect(origin: .zero, size: newSize))
        return UIGraphicsGetImageFromCurrentImageContext()
    }
}
