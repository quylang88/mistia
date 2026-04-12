import SwiftUI

enum FamilyScopedData {
    static func visible<Record: MistiaOwnedRecord>(
        _ records: [Record],
        entity: MistiaSyncEntity,
        scopes: [OwnedRecordScope],
        familyContextStore: FamilyContextStore,
        sessionStore: SessionStore
    ) -> [Record] {
        let ownerMap = MistiaRecordOwnershipStore.ownerMap(from: scopes, entity: entity)
        return MistiaRecordOwnershipStore.visibleRecords(
            records,
            entity: entity,
            ownerMap: ownerMap,
            subjectUserID: familyContextStore.selectedSubjectUserID ?? sessionStore.signedInUserID,
            signedInUserID: sessionStore.signedInUserID
        )
    }
}

struct FamilyContextChipBar: View {
    @Environment(FamilyContextStore.self) private var familyContextStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let viewedMember = familyContextStore.viewedMember {
            Button {
                withAnimation(.snappy) {
                    familyContextStore.returnToSelf()
                }
            } label: {
                HStack(spacing: 8) {
                    MistiaAvatarBadge(
                        initials: String(viewedMember.displayName.prefix(2)).uppercased(),
                        avatarURL: viewedMember.avatarURL,
                        size: 20,
                        showsStatus: false
                    )

                    Text(mistiaLocalized(
                        vi: "Đang xem: \(viewedMember.displayName)",
                        en: "Viewing: \(viewedMember.displayName)",
                        ja: "表示中: \(viewedMember.displayName)"
                    ))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 6)
                .padding(.trailing, 10)
                .padding(.vertical, 6)
                .background {
                    Capsule()
                        .fill(Color(red: 0.43, green: 0.23, blue: 0.76).opacity(colorScheme == .dark ? 0.24 : 0.12))
                }
                .overlay {
                    Capsule()
                        .strokeBorder(Color(red: 0.43, green: 0.23, blue: 0.76).opacity(0.2), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color(red: 0.43, green: 0.23, blue: 0.76))
            .transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity))
            .padding(.bottom, 4)
        }
    }
}
