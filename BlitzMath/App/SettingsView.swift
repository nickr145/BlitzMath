//
//  SettingsView.swift
//  BlitzMath
//
//  Accessibility preferences that sit alongside the device settings
//  (SRS FR-SET-001, FR-SET-002).
//

import SwiftUI

struct SettingsView: View {
    /// Forces Reduce Motion on inside the app even when the device setting is
    /// off. Every animated site reads this key alongside
    /// `\.accessibilityReduceMotion` (SRS FR-SET-002).
    @AppStorage(BlitzTheme.Motion.reduceMotionOverrideKey) private var reduceMotionEnabled = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: BlitzTheme.Layout.stackGap) {
            HStack {
                Text("Settings")
                    .font(BlitzTheme.Typography.title)
                    .foregroundStyle(BlitzTheme.Palette.ink)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(BlitzTheme.Typography.closeIcon)
                        .foregroundStyle(BlitzTheme.Palette.inkSecondary)
                }
                .frame(minWidth: BlitzTheme.Layout.minimumTarget, minHeight: BlitzTheme.Layout.minimumTarget)
                .accessibilityLabel("Close")
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
                        Text("Turn off the moving parts. Your device setting still applies.")
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
}

#Preview {
    SettingsView()
}
