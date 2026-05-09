import SwiftUI
import StoreKit

struct PaywallSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(EntitlementManager.self) private var entitlements

    var source: String = "unknown"
    var petName: String? = nil

    private let features: [(icon: String, text: String)] = [
        ("dog.fill",            "Unlimited dogs"),
        ("bell.badge.fill",     "Push notifications for every dog"),
        ("apps.iphone",         "Home & Lock Screen widgets"),
        ("mic.fill",            "Siri & Shortcuts"),
        ("app.badge.fill",      "App icon badge"),
        ("shippingbox.fill",    "Food stock tracking"),
        ("command.circle.fill", "Action Button & Quick Actions"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    header
                    familySharingBanner
                    featureList
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
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
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
        VStack(spacing: 12) {
            Image(systemName: "pawprint.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.accentColor)
                .padding(20)
                .background(Color.accentColor.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .accessibilityHidden(true)
                .padding(.top, 8)

            Text("Did I Feed the Dog? Pro")
                .font(.title2.bold())

            if let name = petName {
                Text("Save \(name) to your pack — upgrade to Pro to unlock multiple dogs.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("Free for 1 dog with the essentials. Pro unlocks more dogs and power features.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var familySharingBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.2.fill")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("One purchase covers your whole family")
                    .font(.subheadline.bold())
                Text("Family Sharing enabled — pay once for everyone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(Color.accentColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(features, id: \.text) { feature in
                HStack(spacing: 14) {
                    Image(systemName: feature.icon)
                        .font(.body)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 24)
                        .accessibilityHidden(true)
                    Text(feature.text)
                        .font(.body)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
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
        Text("One-time purchase · No subscription · Family Sharing included")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .padding(.bottom, 8)
    }
}
