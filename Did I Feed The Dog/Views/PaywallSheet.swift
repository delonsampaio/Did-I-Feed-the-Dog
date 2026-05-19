import SwiftUI
import StoreKit

struct PaywallSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(EntitlementManager.self) private var entitlements
    @Environment(\.horizontalSizeClass) private var sizeClass

    var source: String = "unknown"
    var petName: String? = nil

    private let features: [(icon: String, text: String)] = [
        ("dog.fill",            "Unlimited dogs"),
        ("apps.iphone",         "Home & Lock Screen widgets"),
        ("bell.badge.fill",     "Push notifications"),
        ("shippingbox.fill",    "Food stock tracking"),
        ("mic.fill",            "Siri & Shortcuts"),
        ("command.circle.fill", "Action Button & Quick Actions"),
        ("person.2.fill",       "Family Sharing included"),
    ]

    private var isIPad: Bool { sizeClass == .regular }
    private var contentMaxWidth: CGFloat { isIPad ? 560 : .infinity }
    private var horizontalPadding: CGFloat { isIPad ? 40 : 24 }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: isIPad ? 36 : 28) {
                        header
                        featureList
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.bottom, 16)
                    .frame(maxWidth: contentMaxWidth)
                    .frame(maxWidth: .infinity)
                }

                VStack(spacing: 12) {
                    if let errorMessage = entitlements.purchaseError {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }
                    purchaseButton
                    restoreButton
                    legalNote
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .frame(maxWidth: contentMaxWidth)
                .frame(maxWidth: .infinity)
                .background(Color(.systemGroupedBackground))
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Pro Upgrade")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Maybe Later") { dismiss() }
                }
            }
            .onChange(of: entitlements.isPro) { _, isPro in
                if isPro { dismiss() }
            }
            .task {
                AppSettings.incrementTelemetry(
                    key: AppSettings.Key.paywallShownFromPrefix + source)
                await entitlements.loadProduct()
            }
        }
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(spacing: isIPad ? 16 : 12) {
            Image(systemName: "pawprint.fill")
                .font(.system(size: isIPad ? 72 : 56))
                .foregroundStyle(Color.accentColor)
                .padding(isIPad ? 28 : 20)
                .background(Color.accentColor.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: isIPad ? 28 : 20))
                .accessibilityHidden(true)
                .padding(.top, 8)

            Text("Did I Feed the Dog? Pro")
                .font(isIPad ? .title.bold() : .title2.bold())

            if let name = petName {
                Text("Save \(name) to your pack — upgrade to Pro to unlock multiple dogs.")
                    .font(isIPad ? .body : .subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("Free for 1 dog with the essentials. Pro unlocks more dogs and power features.")
                    .font(isIPad ? .body : .subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var featureList: some View {
        Group {
            if isIPad {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
                    ForEach(features, id: \.text) { feature in
                        featureRow(feature, iconSize: .title3, frameWidth: 28)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(features, id: \.text) { feature in
                        featureRow(feature, iconSize: .body, frameWidth: 24)
                    }
                }
            }
        }
        .padding(isIPad ? 20 : 16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func featureRow(_ feature: (icon: String, text: String), iconSize: Font, frameWidth: CGFloat) -> some View {
        HStack(spacing: 12) {
            Image(systemName: feature.icon)
                .font(iconSize)
                .foregroundStyle(Color.accentColor)
                .frame(width: frameWidth)
                .accessibilityHidden(true)
            Text(feature.text)
                .font(.body)
            Spacer(minLength: 0)
        }
    }

    private var purchaseButton: some View {
        Button {
            Task { await entitlements.purchase(source: source) }
        } label: {
            Group {
                if entitlements.isLoading {
                    ProgressView().tint(.white)
                } else {
                    Text("Upgrade to Pro — \(entitlements.product?.displayPrice ?? "$0.99")")
                        .font(.headline)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.accentColor)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .disabled(entitlements.isLoading)
    }

    private var restoreButton: some View {
        Button("Restore Purchase") {
            Task { await entitlements.restore() }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .disabled(entitlements.isLoading)
    }

    private var legalNote: some View {
        Text("One-time purchase · No subscription")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .padding(.bottom, 8)
    }
}
