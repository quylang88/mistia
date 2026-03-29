import Foundation

struct ManagementScreenDump: Decodable {
    let headerTitle: String
    let profile: ManagementProfileDump
    let accountsSectionTitle: String
    let accounts: [ManagementAccountItemDump]
    let addAccountLabel: String
    let categoriesSectionTitle: String
    let categoryGroupTitle: String
    let categories: [ManagementCategoryItemDump]
    let addCategoryLabel: String
    let dataSectionTitle: String
    let dataActions: [ManagementActionItemDump]
}

struct ManagementProfileDump: Decodable {
    let name: String
    let email: String
    let initials: String
}

struct ManagementAccountItemDump: Decodable, Identifiable {
    let name: String
    let icon: String
    let accent: MistiaAccent
    let trailingAmount: Int?
    let subtitle: String?
    let footnote: String?

    var id: String { name }
}

struct ManagementCategoryItemDump: Decodable, Identifiable {
    let name: String
    let icon: String
    let accent: MistiaAccent
    let amount: Int

    var id: String { name }
}

struct ManagementActionItemDump: Decodable, Identifiable {
    let title: String
    let icon: String
    let accent: MistiaAccent

    var id: String { title }
}
