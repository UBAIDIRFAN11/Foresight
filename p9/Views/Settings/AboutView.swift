import SwiftUI

struct AboutView: View {
    private var versionText: String {
        // Pull the app version from the generated Info.plist values.
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Foresight")
                        .accessibilityAddTraits(.isHeader)
                        .font(.largeTitle.weight(.bold))
                    Text("Version \(versionText)")
                        .foregroundStyle(.secondary)

                    Text("Plan Today. A brighter tomorrow")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(ForesightTheme.accent)
                        .fixedSize(horizontal: false, vertical: true)
                }

                aboutSection("Author", "Ubaid Irfan\n33886466")
                aboutSection("Purpose", "Foresight is a personal financial planning app to help you set goals, make well-informed decisions, and bring your dreams closer.")
                VStack(alignment: .leading, spacing: 8) {
                    Text("Technologies & Acknowledgements")
                        .accessibilityAddTraits(.isHeader)
                        .font(.headline)

                    Text("Foresight was developed using Apple's SwiftUI for the user interface, SwiftData for local data persistence, Swift Charts for financial visualisations, and UserNotifications for reminders.")
                        .foregroundStyle(.secondary)

                    Text("AI explanations are generated on device using Apple's Foundation Models framework. They interpret results Foresight has already calculated and may be incorrect.")
                        .foregroundStyle(.secondary)

                    Text("Foreign-currency evaluations use dated exchange-rate information provided by [Frankfurter](https://frankfurter.dev/).")
                        .foregroundStyle(.secondary)
                        .tint(ForesightTheme.accent)

                    Text("The application icon was generated using the app icon generator on [appicon.co](https://appicon.co).")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .foresightCard()
                aboutSection("Disclaimer", "Foresight provides planning estimates and visualisations for educational purposes only. It is not a substitute for professional financial advice.")
            }
            .foresightReadableContent()
        }
        .background(ForesightTheme.background)
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func aboutSection(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .accessibilityAddTraits(.isHeader)
                .font(.headline)
            Text(body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foresightCard()
    }
}
