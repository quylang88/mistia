import SwiftUI

struct MistiaPrivacySheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    // Hero Icon
                    HStack {
                        Spacer()
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(MistiaAccent.purple.color)
                        Spacer()
                    }
                    .padding(.top, 30)

                    VStack(alignment: .leading, spacing: 16) {
                        Text(L10n.family.mistiaprivacy.familySharingPrivacy)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.leading)

                        Text(L10n.family.mistiaprivacy.familySharingIsDesignedToProtectYour)
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 24) {
                        privacyBulletItem(
                            description: L10n.family.mistiaprivacy.theAgeAndCountryOrRegionAssociated
                        )

                        privacyBulletItem(
                            description: L10n.family.mistiaprivacy.whenYouStartOrJoinAFamily
                        )
                        
                        privacyBulletItem(
                            description: L10n.family.mistiaprivacy.mistiaUsesDataAboutYourFamilyMembership
                        )
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
