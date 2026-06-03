import SwiftUI
import UIKit

struct NotificationGroupDetailScreen: View {
    @Environment(\.colorScheme) private var colorScheme

    let route: NotificationCenterGroupRoute
    let calendar: Calendar
    let uiState: MistiaUIState
    let onMarkGroupAsRead: ([UUID]) async -> Void
    let onRowTap: (UUID, NotificationCenterResourceIndex) -> Void
    let onRespond: (UUID, Bool) -> Void

    @State private var viewID = UUID()

    private var notificationPurpleAccent: Color {
        colorScheme == .dark ? MistiaAccent.lightPurple.color : MistiaAccent.purple.color
    }

    private var actionFill: Color {
        colorScheme == .dark ? .white.opacity(0.11) : .black.opacity(0.07)
    }

    init(
        _ route: NotificationCenterGroupRoute,
        calendar: Calendar,
        uiState: MistiaUIState,
        onMarkGroupAsRead: @escaping ([UUID]) async -> Void,
        onRowTap: @escaping (UUID, NotificationCenterResourceIndex) -> Void,
        onRespond: @escaping (UUID, Bool) -> Void
    ) {
        self.route = route
        self.calendar = calendar
        self.uiState = uiState
        self.onMarkGroupAsRead = onMarkGroupAsRead
        self.onRowTap = onRowTap
        self.onRespond = onRespond
    }

    var body: some View {
        ZStack {
            Color(UIColor.systemGroupedBackground)
                .ignoresSafeArea()

            list
        }
        .navigationTitle(route.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: route.id) {
            await onMarkGroupAsRead(route.unreadRowIDs)
        }
        .onAppear {
            uiState.requestQuickCreateHidden(true, id: viewID)
        }
        .onDisappear {
            uiState.requestQuickCreateHidden(false, id: viewID)
        }
    }

    private var list: some View {
        List {
            ForEach(route.detailItems) { item in
                itemView(item)
                    .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
    }

    @ViewBuilder
    private func itemView(_ item: NotificationCenterDetailItem) -> some View {
        switch item.kind {
        case .dayHeader(let day):
            dayHeader(day)
        case .row(let row):
            rowView(row)
        }
    }

    private func dayHeader(_ day: Date) -> some View {
        Text(sectionTitle(for: day))
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .padding(.top, 8)
    }

    private func rowView(_ row: NotificationCenterDetailRowSnapshot) -> some View {
        HStack(alignment: .top, spacing: 12) {
            icon(row.icon)
                .frame(width: 36, height: 36)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 8) {
                Text(row.title)
                    .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(row.body)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                actions(for: row)

                HStack {
                    Spacer(minLength: 0)

                    Text(row.createdAt, style: .time)
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(14)
        .background(
            Color(UIColor.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture {
            onRowTap(row.id, route.resourceIndex)
        }
    }

    @ViewBuilder
    private func actions(for row: NotificationCenterDetailRowSnapshot) -> some View {
        switch row.action {
        case .permissionResponse:
            HStack(spacing: 8) {
                actionButton(
                    title: L10n.notifications.notificationcenter.approve,
                    systemImage: "checkmark.circle.fill",
                    foreground: notificationPurpleAccent
                ) {
                    onRespond(row.id, true)
                }

                actionButton(
                    title: L10n.notifications.notificationcenter.reject,
                    systemImage: "xmark.circle.fill",
                    foreground: .red
                ) {
                    onRespond(row.id, false)
                }
            }
            .padding(.top, 2)
        case .primary(let title, let systemImage):
            actionButton(
                title: title,
                systemImage: systemImage,
                foreground: notificationPurpleAccent
            ) {
                onRowTap(row.id, route.resourceIndex)
            }
            .padding(.top, 2)
        case nil:
            EmptyView()
        }
    }

    private func actionButton(
        title: String,
        systemImage: String,
        foreground: Color,
        action: @escaping () -> Void
    ) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(foreground)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(actionFill, in: Capsule())
            .contentShape(Capsule())
            .onTapGesture(perform: action)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
    }

    private func sectionTitle(for day: Date) -> String {
        let referenceDay = calendar.startOfDay(for: Date())
        let dayDelta = calendar.dateComponents([.day], from: day, to: referenceDay).day ?? 0
        return MistiaDateFormatting.relativeDayLabel(for: dayDelta)
            ?? MistiaDateFormatting.fullDateString(for: day, calendar: calendar)
    }

    @ViewBuilder
    private func icon(_ snapshot: NotificationCenterIconSnapshot) -> some View {
        switch snapshot {
        case .finance(let icon, let colorHex):
            MistiaFinanceIconView(
                icon: icon,
                fallbackColor: Color(hex: colorHex),
                size: 32
            )
        case .asset(let name, let color):
            ZStack {
                Circle()
                    .fill(color.opacity(0.12))

                Image(name)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
                    .foregroundStyle(color)
            }
        case .symbol(let systemImage, let color):
            ZStack {
                Circle()
                    .fill(color.opacity(0.12))

                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(color)
            }
        }
    }
}
