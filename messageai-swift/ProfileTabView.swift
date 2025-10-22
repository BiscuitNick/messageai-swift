import SwiftUI

struct ProfileTabView: View {
    let currentUser: AuthService.AppUser

    @Environment(AuthService.self) private var authService
    @Environment(MessagingService.self) private var messagingService

    var body: some View {
        ProfileView(
            user: currentUser,
            onSignOut: handleSignOut,
            showsDismissButton: false
        )
    }

    private func handleSignOut() {
        authService.signOut()
        messagingService.reset()
    }
}
