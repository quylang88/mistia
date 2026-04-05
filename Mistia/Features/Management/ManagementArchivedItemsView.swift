import SwiftUI
import SwiftData

struct ManagementArchivedItemsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(SessionStore.self) private var sessionStore

    @Query(filter: #Predicate<LedgerTransaction> { $0.isArchived == true })
    private var archivedTransactions: [LedgerTransaction]

    @Query(filter: #Predicate<LedgerWallet> { $0.isArchived == true })
    private var archivedWallets: [LedgerWallet]

    @Query(filter: #Predicate<TransactionCategory> { $0.isArchived == true })
    private var archivedCategories: [TransactionCategory]

    var body: some View {
        MistiaPinnedTopBarScaffold(
            tone: .standard,
            title: mistiaLocalized(vi: "Mục đã lưu trữ", en: "Archived items", ja: "アーカイブ済みアイテム"),
            embedsInNavigationStack: false,
            showsLeadingAvatar: false,
            leadingSystemImage: "chevron.left",
            hidesSystemBackButton: true,
            onLeadingTap: { dismiss() },
            contentSpacing: 16
        ) {
            if archivedTransactions.isEmpty && archivedWallets.isEmpty && archivedCategories.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                        .frame(height: 80)
                    
                    Image(systemName: "archivebox")
                        .font(.system(size: 64, weight: .regular))
                        .foregroundStyle(.tertiary)
                    
                    Text(mistiaLocalized(vi: "Không có mục lưu trữ", en: "No archived items", ja: "アーカイブなし"))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    
                    Text(mistiaLocalized(vi: "Bạn chưa có mục nào được lưu trữ. Các mục được lưu trữ sẽ tự động xoá sau 30 ngày.", en: "You don't have any archived items yet. Archived items are automatically deleted after 30 days.", ja: "アーカイブされたアイテムはまだありません。アーカイブされたアイテムは30日後に自動的に削除されます。"))
                        .font(.system(size: 15, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            } else {
                if !archivedTransactions.isEmpty {
                    ManagementSection(title: mistiaLocalized(vi: "Giao dịch", en: "Transactions", ja: "取引"), titleColor: sectionLabelColor) {
                        ForEach(archivedTransactions) { transaction in
                            ArchivedItemRow(title: transaction.title.isEmpty ? mistiaLocalized(vi: "Giao dịch không tên", en: "Unnamed transaction", ja: "無名取引") : transaction.title, subtitle: transaction.amountMinor.description, icon: "dollarsign.circle", onRestore: {
                                transaction.isArchived = false
                                transaction.archivedAt = nil
                                transaction.updatedAt = .now
                                saveAndSync(entity: .transaction, id: transaction.id, updatedAt: transaction.updatedAt)
                            }, onDelete: {
                                let id = transaction.id
                                modelContext.delete(transaction)
                                saveAndSyncDelete(entity: .transaction, id: id)
                            })
                        }
                    }
                }

                if !archivedWallets.isEmpty {
                    ManagementSection(title: mistiaLocalized(vi: "Ví", en: "Wallets", ja: "ウォレット"), titleColor: sectionLabelColor) {
                        ForEach(archivedWallets) { wallet in
                            ArchivedItemRow(title: wallet.name, subtitle: wallet.kind.title, icon: wallet.iconSymbolName, onRestore: {
                                wallet.isArchived = false
                                wallet.updatedAt = .now
                                saveAndSync(entity: .wallet, id: wallet.id, updatedAt: wallet.updatedAt)
                            }, onDelete: {
                                let id = wallet.id
                                modelContext.delete(wallet)
                                saveAndSyncDelete(entity: .wallet, id: id)
                            })
                        }
                    }
                }

                if !archivedCategories.isEmpty {
                    ManagementSection(title: mistiaLocalized(vi: "Danh mục", en: "Categories", ja: "カテゴリ"), titleColor: sectionLabelColor) {
                        ForEach(archivedCategories) { category in
                            ArchivedItemRow(title: category.name, subtitle: category.kind.title, icon: category.iconSymbolName, onRestore: {
                                category.isArchived = false
                                category.updatedAt = .now
                                saveAndSync(entity: .category, id: category.id, updatedAt: category.updatedAt)
                            }, onDelete: {
                                let id = category.id
                                modelContext.delete(category)
                                saveAndSyncDelete(entity: .category, id: id)
                            })
                        }
                    }
                }
            }
        }
    }

    private var sectionLabelColor: Color {
        colorScheme == .dark ? .white.opacity(0.66) : Color(red: 0.36, green: 0.37, blue: 0.43)
    }

    private func saveAndSync(entity: MistiaSyncEntity, id: UUID, updatedAt: Date) {
        do {
            try modelContext.save()
            sessionStore.recordUpsert(entity: entity, recordID: id, modifiedAt: updatedAt)
        } catch {
            print("Failed to save and sync restore: \(error)")
        }
    }

    private func saveAndSyncDelete(entity: MistiaSyncEntity, id: UUID) {
        do {
            try modelContext.save()
            sessionStore.recordDelete(entity: entity, recordID: id, modifiedAt: .now)
        } catch {
            print("Failed to save and sync delete: \(error)")
        }
    }
}

private struct ArchivedItemRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let onRestore: () -> Void
    let onDelete: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.gray.opacity(0.14))

                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.gray)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Menu {
                Button(mistiaLocalized(vi: "Khôi phục", en: "Restore", ja: "復元")) {
                    onRestore()
                }
                Button(mistiaLocalized(vi: "Xóa vĩnh viễn", en: "Delete permanently", ja: "完全に削除"), role: .destructive) {
                    onDelete()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(colorScheme == .dark ? .white.opacity(0.018) : .white.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
    }
}
