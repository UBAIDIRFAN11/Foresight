import SwiftUI

struct HistoryView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 0) {
                Text("History")
                    .font(.largeTitle.weight(.bold))
                Text("Your saved hypothetical decisions.")
                    .font(.title3)
            }

            ContentUnavailableView(
                "No Saved Decisions",
                systemImage: "folder",
                description: Text("Purchase decision history is deferred for a later milestone.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ForesightTheme.background)
    }
}
