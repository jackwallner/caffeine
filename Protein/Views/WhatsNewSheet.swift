import SwiftUI

/// One-time announcement after an update. Purely an awareness surface: nothing
/// it mentions turns itself on.
struct WhatsNewSheet: View {
    let isPro: Bool
    let tryFreeCTATitle: String
    let onTryFree: () -> Void
    let onOpenSettings: () -> Void
    let onDismiss: () -> Void

    private let highlights: [PlusFeature] = [.wristLogging, .quickAdd, .reminders]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    ZStack {
                        Circle()
                            .fill(Theme.proteinGradient)
                            .frame(width: 64, height: 64)
                        Image(systemName: "sparkles")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .padding(.top, 12)

                    VStack(spacing: 6) {
                        Text("What's new")
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Your protein total, the widget, and the watch complication stay exactly as they were.")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(spacing: 10) {
                        ForEach(highlights, id: \.self) { feature in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: feature.symbol)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(feature.tint)
                                    .frame(width: 34, height: 34)
                                    .background(feature.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(feature.title)
                                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                        .foregroundStyle(Theme.textPrimary)
                                    Text(feature.detail)
                                        .font(.system(.caption, design: .rounded))
                                        .foregroundStyle(Theme.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityElement(children: .combine)
                        }
                    }

                    VStack(spacing: 10) {
                        if isPro {
                            Button(action: onOpenSettings) {
                                primaryLabel("Open Settings")
                            }
                            .buttonStyle(.plain)
                        } else {
                            Button(action: onTryFree) {
                                primaryLabel(tryFreeCTATitle)
                            }
                            .buttonStyle(.plain)
                        }
                        Button(action: onDismiss) {
                            Text("Not now")
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                .foregroundStyle(Theme.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .background(Theme.background)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func primaryLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(.headline, design: .rounded, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.proteinGradient, in: Capsule())
    }
}
