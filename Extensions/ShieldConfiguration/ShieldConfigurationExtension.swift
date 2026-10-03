import ManagedSettings
import ManagedSettingsUI
import UIKit

final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration { appearance() }
    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration { appearance() }
    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration { appearance() }
    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration { appearance() }

    private func appearance() -> ShieldConfiguration {
        ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: UIColor(red: 0.03, green: 0.06, blue: 0.13, alpha: 1),
            icon: UIImage(systemName: "star.fill")?.withTintColor(.systemYellow, renderingMode: .alwaysOriginal),
            title: .init(text: "今日のマストから、はじめよう。", color: .white),
            subtitle: .init(text: "ドパギキで今日のマストを終えると解禁！\n一時解除はドパギキの設定から。", color: .lightGray),
            primaryButtonLabel: .init(text: "いったん閉じる", color: .white),
            primaryButtonBackgroundColor: .systemBlue,
            secondaryButtonLabel: nil)
    }
}
