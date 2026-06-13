import SwiftUI

enum MistiaPrivacySheetContext {
    case familySharing
    case profile
}

struct MistiaPrivacySheet: View {
    @Environment(\.dismiss) private var dismiss

    var context: MistiaPrivacySheetContext = .familySharing

    private var content: MistiaPrivacySheetContent {
        switch context {
        case .familySharing:
            MistiaPrivacySheetContent(
                symbolName: "person.2.fill",
                title: L10n.family.mistiaprivacy.familySharingPrivacy,
                subtitle: L10n.family.mistiaprivacy.familySharingIsDesignedToProtectYour,
                bullets: [
                    L10n.family.mistiaprivacy.theAgeAndCountryOrRegionAssociated,
                    L10n.family.mistiaprivacy.whenYouStartOrJoinAFamily,
                    L10n.family.mistiaprivacy.mistiaUsesDataAboutYourFamilyMembership
                ]
            )
        case .profile:
            MistiaPrivacySheetContent(
                symbolName: "person.text.rectangle.fill",
                title: L10n.management.profilePrivacy.personalInformationPrivacy,
                subtitle: L10n.management.profilePrivacy.profileInformationHelpsMistiaKeepYour,
                bullets: [
                    L10n.management.profilePrivacy.yourNameProfilePhotoEmailAnd,
                    L10n.management.profilePrivacy.mistiaUsesThisInformationToShow,
                    L10n.management.profilePrivacy.sensitivePersonalDetailsShouldOnlyBe,
                    L10n.management.profilePrivacy.profileChangesUseYourSignedIn,
                    L10n.management.profilePrivacy.youStayInControlOfProfile
                ]
            )
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HStack {
                        Spacer()
                        Image(systemName: content.symbolName)
                            .font(.system(size: 64))
                            .foregroundStyle(MistiaAccent.purple.color)
                        Spacer()
                    }
                    .padding(.top, 30)

                    VStack(alignment: .leading, spacing: 16) {
                        Text(content.title)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.leading)

                        Text(content.subtitle)
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 24) {
                        ForEach(Array(content.bullets.enumerated()), id: \.offset) { _, bullet in
                            privacyBulletItem(description: bullet)
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 40)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func privacyBulletItem(description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(verbatim: "•")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.secondary)
            
            Text(description)
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct MistiaPrivacySheetContent {
    let symbolName: String
    let title: String
    let subtitle: String
    let bullets: [String]
}
