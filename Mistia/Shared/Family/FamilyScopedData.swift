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

    var body: some View {
        if let title = familyContextStore.contextChipTitle {
            HStack(spacing: 10) {
                MistiaChip(
                    title: title,
                    tint: Color(red: 0.43, green: 0.23, blue: 0.76)
                )

                Button(mistiaLocalized(vi: "Quay lại tôi", en: "Back to me", ja: "自分に戻る")) {
                    familyContextStore.returnToSelf()
                }
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(red: 0.43, green: 0.23, blue: 0.76))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
