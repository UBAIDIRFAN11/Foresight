import SwiftUI

struct AboutView: View {
    private var versionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Foresight")
                        .font(.largeTitle.weight(.bold))
                    Text("Version \(versionText)")
                        .foregroundStyle(.secondary)
                }

                aboutSection("Author", "Ubaid Irfan\n33886466")
                aboutSection("Purpose", "Foresight helps people estimate whether their savings capacity can meet personal financial goals by a target date using information stored locally on this device.")
                aboutSection("Disclaimer", "Foresight provides planning estimates based on the information you enter. It does not provide financial advice.")
            }
            .padding()
        }
        .background(ForesightTheme.background)
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func aboutSection(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foresightCard()
    }
}
