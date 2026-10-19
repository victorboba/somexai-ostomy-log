import SwiftUI

/// The app's three colours, the same three the icon is drawn in, so the home screen and the
/// Home Screen agree with each other.
///
/// Teal rather than the medical blue every other ostomy app uses, and a warm coral for the one
/// thing that needs to stand out — the wear-time ring, which is what the app exists to produce.
extension Color {
    /// 1F6F78
    static let appAccent = Color(red: 0.122, green: 0.435, blue: 0.471)
    /// 3FA0A8
    static let appAccentLight = Color(red: 0.247, green: 0.627, blue: 0.659)
    /// F07F5C
    static let appBadge = Color(red: 0.941, green: 0.498, blue: 0.361)
}

/// A plain card. The dashboard is made of these rather than of list rows, because the home
/// screen of this app is a status board and not a list of things to scroll.
struct DashboardCard<Content: View>: View {
    var title: String? = nil
    var symbol: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Label {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                } icon: {
                    if let symbol {
                        Image(systemName: symbol).foregroundStyle(Color.appAccent)
                    }
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }
}
