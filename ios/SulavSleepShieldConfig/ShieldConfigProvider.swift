import ManagedSettings
import ManagedSettingsUI
import UIKit

// ShieldConfigurationExtension: customizes the overlay shown when the user
// tries to open a shielded app during sleep lockdown. Replaces Apple's generic
// "Screen Time Limit" card with a branded SleepBlock message encouraging the
// user to go back to bed.
//
// This extension runs in its own sandboxed process. It cannot import the main
// app's SwiftUI views — only ManagedSettings types are available.

class ShieldConfigProvider: ShieldConfigurationDataSource {

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        makeConfig()
    }

    override func configuration(shielding application: Application,
                                in category: ActivityCategory) -> ShieldConfiguration {
        makeConfig()
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        makeConfig()
    }

    override func configuration(shielding webDomain: WebDomain,
                                in category: ActivityCategory) -> ShieldConfiguration {
        makeConfig()
    }

    private func makeConfig() -> ShieldConfiguration {
        ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: UIColor(red: 0.03, green: 0.07, blue: 0.12, alpha: 1), // ~#08111E
            icon: UIImage(systemName: "moon.fill"),
            title: ShieldConfiguration.Label(
                text: "Time to Sleep 🌙",
                color: UIColor(red: 0.96, green: 0.64, blue: 0.38, alpha: 1) // ~amber #F4A261
            ),
            subtitle: ShieldConfiguration.Label(
                text: "This app is blocked while you're sleeping. Go back to bed!",
                color: UIColor(red: 0.72, green: 0.74, blue: 0.78, alpha: 1) // ~dim #B7BDC7
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: "Open SleepBlock",
                color: .black
            ),
            primaryButtonBackgroundColor: UIColor(red: 0.96, green: 0.64, blue: 0.38, alpha: 1), // amber
            secondaryButtonLabel: ShieldConfiguration.Label(
                text: "OK",
                color: UIColor(red: 0.72, green: 0.74, blue: 0.78, alpha: 1)
            )
        )
    }
}
