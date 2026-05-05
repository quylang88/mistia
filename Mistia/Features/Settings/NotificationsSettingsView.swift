import SwiftUI
import UserNotifications
import SwiftData

struct NotificationsSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SessionStore.self) private var sessionStore

    @AppStorage(MistiaAppStorageKey.notificationsEnabled) private var notificationsEnabled = false
    @AppStorage(MistiaAppStorageKey.notificationsHadAnyGroupOn) private var notificationsHadAnyGroupOn = false
    @AppStorage(MistiaAppStorageKey.notificationsGroupRemindersEnabled) private var remindersEnabled = false
    @AppStorage(MistiaAppStorageKey.notificationsGroupFamilyEnabled) private var familyEnabled = false
    @AppStorage(MistiaAppStorageKey.notificationsReminderBudgetEnabled) private var budgetRemindersEnabled = false
    @AppStorage(MistiaAppStorageKey.notificationsReminderBillsEnabled) private var billRemindersEnabled = false
    @AppStorage(MistiaAppStorageKey.notificationsReminderCreditCardsEnabled) private var creditCardRemindersEnabled = false
    @AppStorage(MistiaAppStorageKey.notificationsReminderWalletsEnabled) private var walletRemindersEnabled = false

    var body: some View {
        MistiaPinnedTopBarScaffold(
            tone: .standard,
            title: mistiaLocalized(vi: "Thông báo", en: "Notifications", ja: "通知"),
            embedsInNavigationStack: false,
            showsLeadingAvatar: false,
            leadingSystemImage: "chevron.left",
            trailingSystemImage: nil,
            hidesSystemBackButton: true,
            onLeadingTap: { dismiss() },
            contentSpacing: 14
        ) {
            VStack(spacing: 14) {
                notificationCard {
                    notificationToggleRow(
                        title: mistiaLocalized(
                            vi: "Bật thông báo",
                            en: "Enable notifications",
                            ja: "通知を有効にする"
                        ),
                        systemImage: "bell.badge.fill",
                        accent: .coral,
                        isOn: masterEnabledBinding
                    )
                }

                textDetailLayout(
                    mistiaLocalized(
                        vi: "Khi bật, Mistia có thể gửi thông báo nhắc nhở quan trọng.",
                        en: "When enabled, Mistia can send important reminders.",
                        ja: "有効にすると、Mistia から重要なリマインダー通知が届きます。"
                    )
                )

                if notificationsEnabled {
                    notificationBlockTitle(mistiaLocalized(vi: "Nhắc nhở", en: "Reminders", ja: "リマインダー"))

                    notificationCard {
                        notificationToggleRow(
                            title: mistiaLocalized(vi: "Ngân sách", en: "Budget", ja: "予算"),
                            systemImage: "chart.pie.fill",
                            accent: .mint,
                            isOn: budgetReminderBinding
                        )

                        notificationDivider()

                        notificationToggleRow(
                            title: mistiaLocalized(vi: "Hóa đơn", en: "Bills", ja: "請求"),
                            systemImage: "calendar.badge.clock",
                            accent: .amber,
                            isOn: billReminderBinding
                        )

                        notificationDivider()

                        notificationToggleRow(
                            title: mistiaLocalized(vi: "Thẻ tín dụng", en: "Credit cards", ja: "クレジットカード"),
                            systemImage: "creditcard.fill",
                            accent: .purple,
                            isOn: creditCardReminderBinding
                        )

                        notificationDivider()

                        notificationToggleRow(
                            title: mistiaLocalized(vi: "Ví", en: "Wallets", ja: "ウォレット"),
                            systemImage: "wallet.pass.fill",
                            accent: .sky,
                            isOn: walletReminderBinding
                        )
                    }

                    textDetailLayout(
                        mistiaLocalized(
                            vi: "Mistia sẽ nhắc khi ngân sách sắp vượt mức, hóa đơn đến hạn hoặc quá hạn, sao kê thẻ cần thanh toán và ví sắp hết tiền.",
                            en: "Mistia reminds you when budgets are near the limit, bills are due or overdue, credit card statements need payment, and wallets run low.",
                            ja: "予算が上限に近いとき、請求の期限や延滞、カード明細の支払い、ウォレット残高不足を通知します。"
                        )
                    )

                    notificationCard {
                        notificationToggleRow(
                            title: mistiaLocalized(vi: "Gia đình", en: "Family", ja: "家族"),
                            systemImage: "person.2.fill",
                            accent: .indigo,
                            isOn: familyBinding
                        )
                    }

                    textDetailLayout(
                        mistiaLocalized(
                            vi: "Thông báo gia đình gồm yêu cầu quyền, thay đổi quyền và hoạt động tài chính từ các thành viên được chia sẻ.",
                            en: "Family notifications include permission requests, permission changes, and shared financial activity from members.",
                            ja: "家族通知には、権限リクエスト、権限変更、共有された家族の財務アクティビティが含まれます。"
                        )
                    )
                }
            }
        }
        .onChange(of: notificationsEnabled) { _, newValue in
            if newValue {
                Task {
                    await requestAuthorizationIfNeeded()
                    await runDueMaintenanceIfNeeded()
                }
            } else {
                Task { await MistiaLocalNotificationScheduler.clearAllScheduledReminders() }
            }
        }
        .onChange(of: remindersEnabled) { _, _ in
            Task { await runDueMaintenanceIfNeeded() }
        }
        .onChange(of: budgetRemindersEnabled) { _, _ in
            handleReminderDetailChanged()
        }
        .onChange(of: billRemindersEnabled) { _, _ in
            handleReminderDetailChanged()
        }
        .onChange(of: creditCardRemindersEnabled) { _, _ in
            handleReminderDetailChanged()
        }
        .onChange(of: walletRemindersEnabled) { _, _ in
            handleReminderDetailChanged()
        }
        .onAppear {
            guard notificationsEnabled else { return }
            initializeReminderDetailsIfNeeded()
        }
    }

    private var masterEnabledBinding: Binding<Bool> {
        Binding(
            get: { notificationsEnabled },
            set: { newValue in
                if newValue {
                    if !notificationsHadAnyGroupOn {
                        setAllReminderDetails(true)
                        updateReminderGroupFromDetails()
                        familyEnabled = false
                        notificationsHadAnyGroupOn = true
                    } else {
                        initializeReminderDetailsIfNeeded()
                    }
                    notificationsEnabled = true
                } else {
                    notificationsEnabled = false
                }
            }
        )
    }

    private var budgetReminderBinding: Binding<Bool> {
        Binding(
            get: { budgetRemindersEnabled },
            set: {
                budgetRemindersEnabled = $0
                handleReminderDetailChanged()
            }
        )
    }

    private var billReminderBinding: Binding<Bool> {
        Binding(
            get: { billRemindersEnabled },
            set: {
                billRemindersEnabled = $0
                handleReminderDetailChanged()
            }
        )
    }

    private var creditCardReminderBinding: Binding<Bool> {
        Binding(
            get: { creditCardRemindersEnabled },
            set: {
                creditCardRemindersEnabled = $0
                handleReminderDetailChanged()
            }
        )
    }

    private var walletReminderBinding: Binding<Bool> {
        Binding(
            get: { walletRemindersEnabled },
            set: {
                walletRemindersEnabled = $0
                handleReminderDetailChanged()
            }
        )
    }

    private var familyBinding: Binding<Bool> {
        Binding(
            get: { familyEnabled },
            set: { newValue in
                familyEnabled = newValue
                handleGroupToggleChanged()
            }
        )
    }

    private func handleGroupToggleChanged() {
        if remindersEnabled || familyEnabled {
            notificationsHadAnyGroupOn = true
            notificationsEnabled = true
        } else {
            notificationsEnabled = false
            notificationsHadAnyGroupOn = false
        }
    }

    private func handleReminderDetailChanged() {
        updateReminderGroupFromDetails()
        handleGroupToggleChanged()
        Task { await runDueMaintenanceIfNeeded() }
    }

    private func updateReminderGroupFromDetails() {
        remindersEnabled = budgetRemindersEnabled
            || billRemindersEnabled
            || creditCardRemindersEnabled
            || walletRemindersEnabled
    }

    private func setAllReminderDetails(_ isEnabled: Bool) {
        budgetRemindersEnabled = isEnabled
        billRemindersEnabled = isEnabled
        creditCardRemindersEnabled = isEnabled
        walletRemindersEnabled = isEnabled
    }

    private func initializeReminderDetailsIfNeeded() {
        let defaults = UserDefaults.standard
        let hasStoredDetail = MistiaNotificationReminderKind.allCases.contains {
            defaults.object(forKey: $0.storageKey) != nil
        }
        guard !hasStoredDetail, remindersEnabled else { return }
        setAllReminderDetails(true)
    }

    private func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }
    }

    private func runDueMaintenanceIfNeeded() async {
        guard notificationsEnabled else { return }
        await MistiaDueMaintenance.run(
            modelContext: modelContext,
            sessionStore: sessionStore
        )
    }

    @ViewBuilder
    private func notificationCard(@ViewBuilder content: () -> some View) -> some View {
        MistiaGlassCard(cornerRadius: 22, tint: .white.opacity(0.12), padding: 0) {
            VStack(spacing: 0) {
                content()
            }
        }
    }

    private func notificationBlockTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.top, 4)
    }

    private func textDetailLayout(_ text: String) -> some View {
        Text(text)
            .descriptionTextStyle()
            .cardDescriptionStyle()
            .fixedSize(horizontal: false, vertical: true)
    }

    private func notificationDivider() -> some View {
        Divider()
            .padding(.leading, 58)
    }

    @ViewBuilder
    private func notificationToggleRow(
        title: String,
        systemImage: String,
        accent: MistiaAccent,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 12) {
            NotificationPreferenceIcon(systemImage: systemImage, accent: accent)

            Text(title)
                .font(.system(size: 16.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)

            Spacer(minLength: 10)

            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(MistiaAccent.purple.color)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 15)
        .contentShape(Rectangle())
    }
}

private struct NotificationPreferenceIcon: View {
    let systemImage: String
    let accent: MistiaAccent

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(accent.color.opacity(0.15))

            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(accent.color)
        }
        .frame(width: 32, height: 32)
    }
}
