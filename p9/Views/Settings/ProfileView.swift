import SwiftUI

struct ProfileView: View {
    var body: some View {
        ContentUnavailableView(
            "Profile",
            systemImage: "person.crop.circle",
            description: Text("Account fields, cloud sync, and identity features still TODO")
        )
        .background(ForesightTheme.background)
        .navigationTitle("Profile")
    }
}
