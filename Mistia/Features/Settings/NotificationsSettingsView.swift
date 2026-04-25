import SwiftUI
import UserNotifications
import SwiftData

struct NotificationsSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @AppStorage(MistiaAppStorageKey.notificationsEnabled) private var notificationsEnabled = false
    @AppStorage(MistiaAppStorageKey.notificationsHadAnyGroupOn) private var notificationsHadAnyGroupOn = false
    @AppStorage(MistiaAppStorageKey.notificationsGroupRemindersEnabled) private var remindersEnabled = false
    @AppStorage(MistiaAppStorageKey.notificationsGroupFamilyEnabled) private var familyEnabled = false

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
                settingsCard {
                    Toggle(
                        mistiaLocalized(
                            vi: "Bật thông báo",
                            en: "Enable notifications",
                            ja: "通知を有効にする"
                        ),
                        isOn: masterEnabledBinding
                    )
                    .tint(MistiaAccent.purple.color)
                    .toggleStyle(.switch)

                    Text(mistiaLocalized(
                        vi: "Khi bật, Mistia có thể gửi thông báo nhắc nhở quan trọng.",
                        en: "When enabled, Mistia can send important reminders.",
                        ja: "有効にすると、Mistia から重要なリマインダー通知が届きます。"
                    ))
                    .descriptionTextStyle()
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
                }

                if notificationsEnabled {
                    settingsCard {
                        groupToggleRow(
                            title: mistiaLocalized(vi: "Nhắc nhở", en: "Reminders", ja: "リマインダー"),
                            subtitle: mistiaLocalized(
                                vi: "Hóa đơn, thẻ credit, ví sắp hết tiền",
                                en: "Bills, credit cards, low wallet balance",
                                ja: "請求、クレカ、残高低下"
                            ),
                            isOn: remindersBinding
                        )

                        Divider().opacity(0.35)

                        groupToggleRow(
                            title: mistiaLocalized(vi: "Gia đình", en: "Family", ja: "家族"),
                            subtitle: mistiaLocalized(
                                vi: "Hoạt động từ thành viên trong gia đình (đang phát triển)",
                                en: "Family activity (coming soon)",
                                ja: "家族アクティビティ（開発中）"
                            ),
                            isOn: familyBinding
                        )
                    }
                }
            }
        }
        .onChange(of: notificationsEnabled) { _, newValue in
            if newValue {
                Task {
                    await requestAuthorizationIfNeeded()
                    await rescheduleIfNeeded()
                }
            } else {
                Task { await MistiaLocalNotificationScheduler.clearAllScheduledReminders() }
            }
        }
        .onChange(of: remindersEnabled) { _, _ in
            Task { await rescheduleIfNeeded() }
        }
    }

    private var masterEnabledBinding: Binding<Bool> {
        Binding(
            get: { notificationsEnabled },
            set: { newValue in
                if newValue {
                    if !notificationsHadAnyGroupOn {
                        remindersEnabled = true
                        familyEnabled = false
                        notificationsHadAnyGroupOn = true
                    }
                    notificationsEnabled = true
                } else {
                    notificationsEnabled = false
                }
            }
        )
    }

    private var remindersBinding: Binding<Bool> {
        Binding(
            get: { remindersEnabled },
            set: { newValue in
                remindersEnabled = newValue
                handleGroupToggleChanged()
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

    private func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }
    }

    private func rescheduleIfNeeded() async {
        guard notificationsEnabled, remindersEnabled else { return }
        await MistiaLocalNotificationScheduler.rescheduleReminders(modelContext: modelContext)
    }

    @ViewBuilder
    private func settingsCard(@ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(16)
        .background(
            Color(UIColor.secondarySystemGroupedBackground)
                .opacity(0.62),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
    }

    @ViewBuilder
    private func groupToggleRow(
        title: String,
        subtitle: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(.headline, design: .rounded))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 10)

            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(MistiaAccent.purple.color)
        }
        .contentShape(Rectangle())
    }
}

