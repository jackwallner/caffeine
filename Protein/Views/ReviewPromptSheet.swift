import SwiftUI
import UIKit

/// Manual presentation from Settings, which bypasses passive eligibility.
@MainActor
final class ReviewPromptCoordinator: ObservableObject {
    static let shared = ReviewPromptCoordinator()

    enum Presentation {
        case enjoymentPrompt
        case feedbackOnly
    }

    @Published var pendingPresentation: Presentation?

    private init() {}

    func requestEnjoymentPrompt() {
        pendingPresentation = .enjoymentPrompt
    }

    func requestFeedback() {
        pendingPresentation = .feedbackOnly
    }

    func clear() {
        pendingPresentation = nil
    }
}

/// Returned when the sheet closes so the host can call `requestReview()` if
/// appropriate.
enum ReviewPromptDismissOutcome: Sendable {
    case notNow
    case feedbackSubmitted
    case openedWriteReview
    /// User chose "Yes" but dismissed the pitch without opening the store — the
    /// host may call `requestReview()` once in `onDismiss`.
    case enjoyedMaybeLater
}

struct ReviewPromptSheet: View {
    enum Step {
        case enjoyment
        case reviewPitch
        case feedback
    }

    let initialStep: Step
    /// True only when the funnel opened itself off the target-hit rule. The
    /// Settings route bypasses that rule, so it must not claim a streak the
    /// user may not have.
    let earnedByTargetHits: Bool
    let onFinish: (ReviewPromptDismissOutcome) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var step: Step
    @State private var feedbackText = ""
    @State private var mailFailed = false
    @FocusState private var feedbackFocused: Bool

    init(
        initialStep: Step = .enjoyment,
        earnedByTargetHits: Bool = true,
        onFinish: @escaping (ReviewPromptDismissOutcome) -> Void
    ) {
        self.initialStep = initialStep
        self.earnedByTargetHits = earnedByTargetHits
        self.onFinish = onFinish
        _step = State(initialValue: initialStep)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .enjoyment: enjoymentContent
                case .reviewPitch: reviewPitchContent
                case .feedback: feedbackContent
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") { handleNotNow() }
                }
            }
        }
        .presentationDetents(step == .feedback ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var navigationTitle: String {
        switch step {
        case .enjoyment: "Hitting your number?"
        case .reviewPitch: "Support an indie dev"
        case .feedback: "Help us improve"
        }
    }

    private var enjoymentContent: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Theme.proteinGradient)
                    .frame(width: 64, height: 64)
                Image(systemName: "checkmark")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
            }
            .padding(.top, 8)

            Text(earnedByTargetHits
                 ? "You have hit your protein target a few days running. If this app is helping, a quick rating on the App Store makes a real difference."
                 : "If Protein Tracker is helping you hit your number, a quick rating on the App Store makes a real difference.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)

            VStack(spacing: 10) {
                Button {
                    step = .reviewPitch
                } label: {
                    primaryButtonLabel("Yes, it's helping")
                }
                .buttonStyle(.plain)

                Button {
                    step = .feedback
                } label: {
                    secondaryButtonLabel("Not really")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    private var reviewPitchContent: some View {
        VStack(spacing: 18) {
            Text("Protein Tracker is built by one indie developer, with no ads, no accounts, and your health data never leaving your phone.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            Text("An honest App Store review takes seconds, and it is how people looking for a simple protein target find this instead of another calorie app.")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 10) {
                Button {
                    ReviewPromptTracker.markOpenedWriteReview()
                    UIApplication.shared.open(AppStoreReviewLinks.writeReviewURL)
                    finish(.openedWriteReview)
                } label: {
                    primaryButtonLabel("Rate on the App Store")
                }
                .buttonStyle(.plain)

                Button {
                    ReviewPromptTracker.markSoftDeferred()
                    finish(.enjoyedMaybeLater)
                } label: {
                    secondaryButtonLabel("Maybe later")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    private var feedbackContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What would make Protein Tracker work better for you?")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            TextEditor(text: $feedbackText)
                .font(.system(.body, design: .rounded))
                .frame(minHeight: 140)
                .padding(10)
                .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: 12))
                .focused($feedbackFocused)
                // The prompt above is not programmatically attached to the
                // editor, so without this VoiceOver reaches an unnamed field.
                .accessibilityLabel("Your feedback")
                .accessibilityHint("What would make Protein Tracker work better for you")

            if mailFailed {
                Text("No mail app could be opened. Your words are still here. Copy them into an email to \(Self.feedbackAddress).")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.coral)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Opens your mail app with a draft to the developer. No analytics, just your words.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }

            Button {
                sendFeedback()
            } label: {
                primaryButtonLabel("Send feedback")
            }
            .buttonStyle(.plain)
            .disabled(feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .onAppear { feedbackFocused = true }
    }

    private func primaryButtonLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(.headline, design: .rounded, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.proteinGradient, in: Capsule())
    }

    private func secondaryButtonLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(.subheadline, design: .rounded, weight: .semibold))
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
    }

    private func handleNotNow() {
        ReviewPromptTracker.markShown()
        finish(.notNow)
    }

    /// Feedback is only "submitted" once iOS has actually handed the draft to a
    /// mail client. A device with no mail app configured otherwise closed the
    /// sheet, dropped the typed text, and reported success.
    private func sendFeedback() {
        let trimmed = feedbackText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = Self.feedbackMailURL(body: trimmed) else { return }
        UIApplication.shared.open(url, options: [:]) { opened in
            Task { @MainActor in
                guard opened else {
                    mailFailed = true
                    return
                }
                ReviewPromptTracker.markFeedbackSubmitted()
                finish(.feedbackSubmitted)
            }
        }
    }

    private func finish(_ outcome: ReviewPromptDismissOutcome) {
        onFinish(outcome)
        dismiss()
    }

    static let feedbackAddress = "jackwallner+protein@gmail.com"

    /// Pre-filled mailto for private, account-free feedback.
    static func feedbackMailURL(body: String) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = feedbackAddress
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Protein Tracker feedback"),
            URLQueryItem(name: "body", value: body),
        ]
        return components.url
    }
}
