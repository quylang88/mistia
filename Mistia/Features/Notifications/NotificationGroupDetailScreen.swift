import SwiftUI
import UIKit

struct NotificationGroupDetailScreen: View {
    @Environment(\.colorScheme) private var colorScheme

    let route: NotificationCenterGroupRoute
    let calendar: Calendar
    let uiState: MistiaUIState
    let onMarkGroupAsRead: ([UUID]) async -> Void
    let onRowTap: (UUID, NotificationCenterResourceIndex) -> Void
    let onRespond: (UUID, Bool) async -> NotificationPermissionResponseAlert
    let onFinishResponse: () -> Void

    @State private var viewID = UUID()
    @State private var responseAlert: NotificationPermissionResponseAlert?
    @State private var respondingSubmission: PermissionResponseSubmission?

    private var notificationPurpleAccent: Color {
        colorScheme == .dark ? MistiaAccent.lightPurple.color : MistiaAccent.purple.color
    }

    private var rowTitleColor: Color {
        colorScheme == .dark ? .primary.opacity(0.96) : .primary
    }

    private var rowBodyColor: Color {
        colorScheme == .dark ? .primary.opacity(0.76) : .secondary
    }

    private var permissionButtonBorder: Color {
        colorScheme == .dark ? .white.opacity(0.18) : .black.opacity(0.10)
    }

    private struct PermissionResponseSubmission: Equatable {
        let rowID: UUID
        let approve: Bool
    }

    init(
        _ route: NotificationCenterGroupRoute,
        calendar: Calendar,
        uiState: MistiaUIState,
        onMarkGroupAsRead: @escaping ([UUID]) async -> Void,
        onRowTap: @escaping (UUID, NotificationCenterResourceIndex) -> Void,
        onRespond: @escaping (UUID, Bool) async -> NotificationPermissionResponseAlert,
        onFinishResponse: @escaping () -> Void
    ) {
        self.route = route
        self.calendar = calendar
        self.uiState = uiState
        self.onMarkGroupAsRead = onMarkGroupAsRead
        self.onRowTap = onRowTap
        self.onRespond = onRespond
        self.onFinishResponse = onFinishResponse
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
        .alert(item: $responseAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text(L10n.common.ok)) {
                    if alert.dismissesDetail {
                        onFinishResponse()
                    }
                }
            )
        }
    }

    private var list: some View {
        List {
            ForEach(route.detailSections) { section in
                dayBlock(section)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 10, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
    }

    private func dayHeader(_ day: Date) -> some View {
        Text(sectionTitle(for: day))
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
    }

    private func dayBlock(_ section: NotificationCenterDetailSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            dayHeader(section.id)

            VStack(spacing: 0) {
                ForEach(Array(section.rows.enumerated()), id: \.element.id) { index, row in
                    rowView(row)

                    if index < section.rows.count - 1 {
                        Divider()
                            .padding(.leading, 62)
                    }
                }
            }
            .background(
                Color(UIColor.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
        }
    }

    private func rowView(_ row: NotificationCenterDetailRowSnapshot) -> some View {
        HStack(alignment: .top, spacing: 12) {
            icon(row.icon)
                .frame(width: 36, height: 36)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 8) {
                Text(row.title)
                    .font(.system(size: 15.5, weight: .bold, design: .rounded))
                    .foregroundStyle(rowTitleColor)
                    .fixedSize(horizontal: false, vertical: true)

                Text(row.body)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(rowBodyColor)
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
        .contentShape(Rectangle())
        .onTapGesture {
            onRowTap(row.id, route.resourceIndex)
        }
    }

    @ViewBuilder
    private func actions(for row: NotificationCenterDetailRowSnapshot) -> some View {
        switch row.action {
        case .permissionResponse:
            permissionResponseButtons(for: row)
                .padding(.top, 4)
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

    private func permissionResponseButtons(for row: NotificationCenterDetailRowSnapshot) -> some View {
        let isProcessing = respondingSubmission != nil

        return HStack(spacing: 10) {
            permissionResponseButton(
                title: L10n.notifications.notificationcenter.approve,
                systemImage: "checkmark",
                approve: true,
                isProcessing: respondingSubmission == PermissionResponseSubmission(rowID: row.id, approve: true)
            ) {
                submitPermissionResponse(rowID: row.id, approve: true)
            }

            permissionResponseButton(
                title: L10n.notifications.notificationcenter.reject,
                systemImage: "xmark",
                approve: false,
                isProcessing: respondingSubmission == PermissionResponseSubmission(rowID: row.id, approve: false)
            ) {
                submitPermissionResponse(rowID: row.id, approve: false)
            }
        }
        .disabled(isProcessing)
        .accessibilityElement(children: .contain)
    }

    private func permissionResponseButton(
        title: String,
        systemImage: String,
        approve: Bool,
        isProcessing: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let foreground: Color = approve ? .white : .red
        let fill: Color = approve ? notificationPurpleAccent : .clear

        return Button(action: action) {
            HStack(spacing: 7) {
                if isProcessing {
                    ProgressView()
                        .controlSize(.small)
                        .tint(foreground)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .bold))
                }

                Text(title)
                    .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .frame(maxWidth: .infinity, minHeight: 34)
            .foregroundStyle(foreground)
            .background(fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(approve ? Color.clear : permissionButtonBorder, lineWidth: 0.8)
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .opacity(isProcessing ? 0.72 : 1)
    }

    private func submitPermissionResponse(rowID: UUID, approve: Bool) {
        guard respondingSubmission == nil else { return }
        respondingSubmission = PermissionResponseSubmission(rowID: rowID, approve: approve)

        Task {
            let alert = await onRespond(rowID, approve)
            await MainActor.run {
                respondingSubmission = nil
                responseAlert = alert
            }
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
            .overlay {
                Capsule()
                    .strokeBorder(permissionButtonBorder, lineWidth: 0.8)
            }
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
        case .asset(let name, _):
            Image(name)
                .resizable()
                .renderingMode(.original)
                .aspectRatio(contentMode: .fit)
                .frame(width: 28, height: 28)
        case .symbol(let systemImage, let color):
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(color)
        }
    }
}
