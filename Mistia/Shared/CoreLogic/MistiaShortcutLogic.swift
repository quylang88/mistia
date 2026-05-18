import Foundation

enum MistiaShortcutKind: String, CaseIterable, Codable, Identifiable {
    case backupRestore
    case archivedItems
    case familyOverview
    case familyMember
    case receiptScan
    case syncNow

    var id: String { rawValue }
}

struct MistiaShortcutSelection: Equatable, Codable {
    var kind: MistiaShortcutKind
    var memberUserID: UUID?

    init(
        kind: MistiaShortcutKind,
        memberUserID: UUID? = nil
    ) {
        self.kind = kind
        self.memberUserID = kind == .familyMember ? memberUserID : nil
    }

    init(
        storedKindRawValue: String,
        storedMemberUserIDRawValue: String
    ) {
        self.init(
            kind: MistiaShortcutKind(rawValue: storedKindRawValue) ?? .backupRestore,
            memberUserID: UUID(uuidString: storedMemberUserIDRawValue)
        )
    }

    static let backupRestore = MistiaShortcutSelection(kind: .backupRestore)
    static let archivedItems = MistiaShortcutSelection(kind: .archivedItems)
    static let familyOverview = MistiaShortcutSelection(kind: .familyOverview)
    static let receiptScan = MistiaShortcutSelection(kind: .receiptScan)
    static let syncNow = MistiaShortcutSelection(kind: .syncNow)

    var storedKindRawValue: String {
        kind.rawValue
    }

    var storedMemberUserIDRawValue: String {
        guard kind == .familyMember else { return "" }
        return memberUserID?.uuidString.lowercased() ?? ""
    }
}

struct MistiaShortcutMemberContext: Equatable {
    let userID: UUID
    let displayName: String
    let initials: String
    let avatarURL: URL?
    let canView: Bool
    let isCurrentUser: Bool
}

struct MistiaShortcutResolveInput: Equatable {
    let currentUserInitials: String
    let currentUserAvatarURL: URL?
    let familyID: UUID?
    let canOpenFamilyHome: Bool
    let members: [MistiaShortcutMemberContext]
}

enum MistiaShortcutIconContent: Equatable {
    case systemImage(String)
    case currentUserAvatar(initials: String, avatarURL: URL?)
    case memberAvatar(initials: String, avatarURL: URL?)
}

enum MistiaShortcutResolvedAction: Equatable {
    case backupRestore
    case archivedItems
    case familyOverview(familyID: UUID)
    case memberOverview(userID: UUID)
    case receiptScan
    case syncNow
}

struct MistiaShortcutPresentation: Equatable {
    let title: String
    let accessibilityLabel: String
    let icon: MistiaShortcutIconContent
    let action: MistiaShortcutResolvedAction
}

struct MistiaShortcutResolution: Equatable {
    let selection: MistiaShortcutSelection
    let presentation: MistiaShortcutPresentation
}

enum MistiaShortcutLogic {
    static func resolve(
        selection: MistiaShortcutSelection,
        input: MistiaShortcutResolveInput
    ) -> MistiaShortcutResolution {
        let normalizedSelection = MistiaShortcutSelection(
            kind: selection.kind,
            memberUserID: selection.memberUserID
        )

        switch normalizedSelection.kind {
        case .backupRestore:
            return MistiaShortcutResolution(
                selection: .backupRestore,
                presentation: MistiaShortcutPresentation(
                    title: mistiaLocalized(vi: "Sao lưu & Khôi phục", en: "Backup & Restore", ja: "バックアップ & 復元"),
                    accessibilityLabel: mistiaLocalized(vi: "Mở Sao lưu & Khôi phục", en: "Open backup and restore", ja: "バックアップと復元を開く"),
                    icon: .systemImage("externaldrive.fill.badge.icloud"),
                    action: .backupRestore
                )
            )

        case .archivedItems:
            return MistiaShortcutResolution(
                selection: .archivedItems,
                presentation: MistiaShortcutPresentation(
                    title: mistiaLocalized(vi: "Mục đã lưu trữ", en: "Archived items", ja: "アーカイブ済みアイテム"),
                    accessibilityLabel: mistiaLocalized(vi: "Mở Mục đã lưu trữ", en: "Open archived items", ja: "アーカイブ済みアイテムを開く"),
                    icon: .systemImage("archivebox.fill"),
                    action: .archivedItems
                )
            )

        case .familyOverview:
            guard input.canOpenFamilyHome, let familyID = input.familyID else {
                return MistiaShortcutResolution(
                    selection: .backupRestore,
                    presentation: backupRestorePresentation()
                )
            }

            return MistiaShortcutResolution(
                selection: .familyOverview,
                presentation: MistiaShortcutPresentation(
                    title: mistiaLocalized(vi: "Tổng quan gia đình", en: "Family overview", ja: "家族の概要"),
                    accessibilityLabel: mistiaLocalized(vi: "Mở tổng quan gia đình", en: "Open family overview", ja: "家族の概要を開く"),
                    icon: .systemImage("person.2.fill"),
                    action: .familyOverview(familyID: familyID)
                )
            )

        case .familyMember:
            guard let memberUserID = normalizedSelection.memberUserID,
                  let member = input.members.first(where: { $0.userID == memberUserID }),
                  member.canView,
                  !member.isCurrentUser else {
                return MistiaShortcutResolution(
                    selection: .backupRestore,
                    presentation: backupRestorePresentation()
                )
            }

            return MistiaShortcutResolution(
                selection: MistiaShortcutSelection(kind: .familyMember, memberUserID: member.userID),
                presentation: MistiaShortcutPresentation(
                    title: member.displayName,
                    accessibilityLabel: mistiaLocalized(
                        vi: "Xem nhanh \(member.displayName)",
                        en: "Quick view \(member.displayName)",
                        ja: "\(member.displayName) をすぐ見る"
                    ),
                    icon: .memberAvatar(initials: member.initials, avatarURL: member.avatarURL),
                    action: .memberOverview(userID: member.userID)
                )
            )

        case .receiptScan:
            return MistiaShortcutResolution(
                selection: .receiptScan,
                presentation: MistiaShortcutPresentation(
                    title: mistiaLocalized(vi: "Quét bill", en: "Scan receipt", ja: "レシート読取"),
                    accessibilityLabel: mistiaLocalized(vi: "Mở quét bill", en: "Open receipt scan", ja: "レシート読取を開く"),
                    icon: .systemImage("doc.viewfinder"),
                    action: .receiptScan
                )
            )

        case .syncNow:
            return MistiaShortcutResolution(
                selection: .syncNow,
                presentation: MistiaShortcutPresentation(
                    title: mistiaLocalized(vi: "Đồng bộ ngay", en: "Sync now", ja: "今すぐ同期"),
                    accessibilityLabel: mistiaLocalized(vi: "Đồng bộ ngay", en: "Sync now", ja: "今すぐ同期"),
                    icon: .systemImage("arrow.triangle.2.circlepath.icloud.fill"),
                    action: .syncNow
                )
            )
        }
    }

    private static func backupRestorePresentation() -> MistiaShortcutPresentation {
        MistiaShortcutPresentation(
            title: mistiaLocalized(vi: "Sao lưu & Khôi phục", en: "Backup & Restore", ja: "バックアップ & 復元"),
            accessibilityLabel: mistiaLocalized(vi: "Mở Sao lưu & Khôi phục", en: "Open backup and restore", ja: "バックアップと復元を開く"),
            icon: .systemImage("externaldrive.fill.badge.icloud"),
            action: .backupRestore
        )
    }
}
