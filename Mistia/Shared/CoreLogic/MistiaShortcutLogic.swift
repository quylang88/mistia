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

    var requiresRemoteAction: Bool {
        switch self {
        case .familyOverview, .memberOverview, .receiptScan, .syncNow:
            return true
        case .backupRestore, .archivedItems:
            return false
        }
    }
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
                    title: L10n.settings.shortcut.option.backupRestore.title,
                    accessibilityLabel: L10n.settings.shortcut.option.backupRestore.accessibility,
                    icon: .systemImage("externaldrive.badge.icloud"),
                    action: .backupRestore
                )
            )

        case .archivedItems:
            return MistiaShortcutResolution(
                selection: .archivedItems,
                presentation: MistiaShortcutPresentation(
                    title: L10n.settings.shortcut.option.archivedItems.title,
                    accessibilityLabel: L10n.settings.shortcut.option.archivedItems.accessibility,
                    icon: .systemImage("archivebox"),
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
                    title: L10n.settings.shortcut.option.familyOverview.title,
                    accessibilityLabel: L10n.settings.shortcut.option.familyOverview.accessibility,
                    icon: .systemImage("person.3"),
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
                    accessibilityLabel: L10n.settings.shortcut.member.quickViewAccessibility(member.displayName),
                    icon: .memberAvatar(initials: member.initials, avatarURL: member.avatarURL),
                    action: .memberOverview(userID: member.userID)
                )
            )

        case .receiptScan:
            return MistiaShortcutResolution(
                selection: .receiptScan,
                presentation: MistiaShortcutPresentation(
                    title: L10n.settings.shortcut.option.receiptScan.title,
                    accessibilityLabel: L10n.settings.shortcut.option.receiptScan.accessibility,
                    icon: .systemImage("doc.viewfinder"),
                    action: .receiptScan
                )
            )

        case .syncNow:
            return MistiaShortcutResolution(
                selection: .syncNow,
                presentation: MistiaShortcutPresentation(
                    title: L10n.settings.shortcut.option.syncNow.title,
                    accessibilityLabel: L10n.settings.shortcut.option.syncNow.accessibility,
                    icon: .systemImage("arrow.triangle.2.circlepath.icloud"),
                    action: .syncNow
                )
            )
        }
    }

    private static func backupRestorePresentation() -> MistiaShortcutPresentation {
        MistiaShortcutPresentation(
            title: L10n.settings.shortcut.option.backupRestore.title,
            accessibilityLabel: L10n.settings.shortcut.option.backupRestore.accessibility,
            icon: .systemImage("externaldrive.badge.icloud"),
            action: .backupRestore
        )
    }
}
