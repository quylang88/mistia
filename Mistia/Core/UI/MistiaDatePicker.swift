import SwiftUI

enum MistiaDatePickerMode {
    case date
    case dateAndTime
}

struct MistiaDatePickerRow: View {
    let title: String
    @Binding var selection: Date
    var mode: MistiaDatePickerMode = .date
    var selectableRange: AnyRange<Date>? = nil

    @Environment(\.calendar) private var calendar
    @State private var isPickerPresented = false

    var body: some View {
        switch mode {
        case .date:
            Button {
                isPickerPresented = true
            } label: {
                HStack(spacing: 12) {
                    Text(title)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(dateText)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
            }
            .buttonStyle(.plain)
            .datePickerPopover(
                isPresented: $isPickerPresented,
                selection: $selection,
                calendar: calendar,
                selectableRange: selectableRange
            )

        case .dateAndTime:
            HStack(spacing: 12) {
                Text(title)
                    .foregroundStyle(.primary)

                Spacer(minLength: 8)

                DatePicker(
                    "",
                    selection: $selection,
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.compact)
                .labelsHidden()
                .environment(\.calendar, calendar)
                .environment(\.locale, MistiaAppLanguage.current.locale)
                .tint(MistiaAccent.purple.color)

                Button {
                    isPickerPresented = true
                } label: {
                    Text(dateText)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
                .buttonStyle(.plain)
            }
            .datePickerPopover(
                isPresented: $isPickerPresented,
                selection: $selection,
                calendar: calendar,
                selectableRange: selectableRange
            )
        }
    }

    private var dateText: String {
        MistiaDateFormatting.fullDateString(for: selection, calendar: calendar)
    }
}

private extension View {
    func datePickerPopover(
        isPresented: Binding<Bool>,
        selection: Binding<Date>,
        calendar: Calendar,
        selectableRange: AnyRange<Date>? = nil
    ) -> some View {
        popover(isPresented: isPresented) {
            MistiaDatePickerPanel(
                selection: selection,
                calendar: calendar,
                selectableRange: selectableRange
            )
            .presentationCompactAdaptation(.sheet)
            .presentationDetents([.medium])
        }
    }
}

private struct MistiaDatePickerPanel: View {
    @Binding var selection: Date
    let calendar: Calendar
    let language: MistiaAppLanguage
    let selectableRange: AnyRange<Date>?

    @Environment(\.dismiss) private var dismiss
    @State private var draftSelection: Date

    init(selection: Binding<Date>, calendar: Calendar, selectableRange: AnyRange<Date>? = nil) {
        self._selection = selection
        self.calendar = calendar
        self.selectableRange = selectableRange
        let language = MistiaAppLanguage.current
        self.language = language

        let clampedInitial = AnyRange.clamped(selection.wrappedValue, to: selectableRange, calendar: calendar)
        _draftSelection = State(initialValue: clampedInitial)
    }

    var body: some View {
        MistiaModalScaffold(
            titleView: {
                EmptyView()
            },
            accent: MistiaAccent.purple.color,
            onSave: {
                selection = draftSelection
            }
        ) {
            MistiaCalendarView(
                selection: $draftSelection,
                calendar: calendar,
                language: language,
                selectableRange: selectableRange,
                accent: MistiaAccent.purple.color
            )
        }
    }
}
