import SwiftUI

struct SettingsView: View {
    @State private var reduceMotionEnabled = false

    var body: some View {
        VStack(spacing: BlitzTheme.Layout.stackGap) {
            HStack {
                Text("Settings")
                    .font(BlitzTheme.Typography.title)
                    .foregroundStyle(BlitzTheme.Palette.ink)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(BlitzTheme.Palette.inkSecondary)
                }
            }
            .padding(BlitzTheme.Layout.gutter)

            Divider()
                .background(BlitzTheme.Palette.rule)

            VStack(alignment: .leading, spacing: BlitzTheme.Layout.stackGap) {
                Toggle(isOn: $reduceMotionEnabled) {
                    VStack(alignment: .leading, spacing: BlitzTheme.Layout.tightGap) {
                        Text("Reduce Motion")
                            .font(BlitzTheme.Typography.body)
                            .foregroundStyle(BlitzTheme.Palette.ink)
                        Text("Disable animations for accessibility")
                            .font(BlitzTheme.Typography.caption)
                            .foregroundStyle(BlitzTheme.Palette.inkSecondary)
                    }
                }
                .tint(BlitzTheme.Palette.velocity)
            }
            .padding(BlitzTheme.Layout.gutter)

            Spacer()
        }
        .background(GraphPaperGrid().ignoresSafeArea())
    }

    @Environment(\.dismiss) private var dismiss
}

#Preview {
    SettingsView()
}
