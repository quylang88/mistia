import SwiftUI
import UserNotifications
import SwiftData

struct NotificationsSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SessionStore.self) private var sessionStore
    @Environment(FamilyContextStore.self) private var familyContextStore

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
            title: L10n.settings.notifications.title,
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
                        title: L10n.settings.notifications.enable.title,
                        systemImage: "bell.badge.fill",
                        accent: .coral,
                        isOn: masterEnabledBinding
                    )
                }

                textDetailLayout(L10n.settings.notifications.enable.description)

                if notificationsEnabled {
                    notificationBlockTitle(L10n.settings.notifications.reminders.title)

                    notificationCard {
                        notificationToggleRow(
                            title: L10n.settings.notifications.reminders.budget,
                            systemImage: "chart.pie.fill",
                            accent: .mint,
                            isOn: budgetReminderBinding
                        )

                        notificationDivider()

                        notificationToggleRow(
                            title: L10n.settings.notifications.reminders.bills,
                            systemImage: "calendar.badge.clock",
                            accent: .amber,
                            isOn: billReminderBinding
                        )

                        notificationDivider()

                        notificationToggleRow(
                            title: L10n.settings.notifications.reminders.creditCards,
                            systemImage: "creditcard.fill",
                            accent: .purple,
                            isOn: creditCardReminderBinding
                        )

                        notificationDivider()

                        notificationToggleRow(
                            title: L10n.settings.notifications.reminders.wallets,
                            systemImage: "wallet.pass.fill",
                            accent: .sky,
                            isOn: walletReminderBinding
                        )
                    }

                    textDetailLayout(L10n.settings.notifications.reminders.description)

                    notificationCard {
                        notificationToggleRow(
                            title: L10n.settings.notifications.family.title,
                            systemImage: "person.2.fill",
                            accent: .indigo,
                            isOn: familyBinding
                        )
                    }

                    textDetailLayout(L10n.settings.notifications.family.description)
                }
            }
        }
        .onChange(of: notificationsEnabled) { _, newValue in
            if newValue {
                Task {
                    await requestAuthorizationIfNeeded()
                    await runDueMaintenanceIfNeeded()
                    if familyEnabled {
                        await familyContextStore.refreshNotifications(sessionStore: sessionStore)
                    }
                }
            } else {
                Task { await MistiaLocalNotificationScheduler.clearAllScheduledReminders() }
            }
            updateAppBadge()
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
                if newValue && notificationsEnabled {
                    Task { await familyContextStore.refreshNotifications(sessionStore: sessionStore) }
                }
                updateAppBadge()
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

    private func updateAppBadge() {
        MistiaNotificationStore.updateAppBadgeCount(
            in: modelContext,
            userID: sessionStore.activeLocalProfileUserID
        )
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
            sessionStore: sessionStore,
            familyContextStore: familyContextStore
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
        MistiaSectionFooter(text)
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

            Toggle(String(), isOn: isOn)
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
