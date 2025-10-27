import SwiftUI

struct ProfileTabView: View {
    let currentUser: AuthCoordinator.AppUser

    @Environment(AuthCoordinator.self) private var authService
    @Environment(MessagingCoordinator.self) private var messagingCoordinator

    var body: some View {
        ProfileView(
            user: currentUser,
            onSignOut: handleSignOut,
            showsDismissButton: false
        )
    }

    private func handleSignOut() {
        authService.signOut()
        messagingCoordinator.reset()
    }
}
