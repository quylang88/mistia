import SwiftUI

enum MistiaDatePickerMode {
    case date
    case dateAndTime
}

struct MistiaDatePickerRow: View {
    let title: String
    @Binding var selection: Date
    var mode: MistiaDatePickerMode = .date
    var selectableRange: ClosedRange<Date>? = nil

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
        selectableRange: ClosedRange<Date>? = nil
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
    let selectableRange: ClosedRange<Date>?

    @Environment(\.dismiss) private var dismiss
    @State private var draftSelection: Date

    init(selection: Binding<Date>, calendar: Calendar, selectableRange: ClosedRange<Date>? = nil) {
        self._selection = selection
        self.calendar = calendar
        self.selectableRange = selectableRange
        let language = MistiaAppLanguage.current
        self.language = language

        let clampedInitial = Self.clamped(selection.wrappedValue, to: selectableRange, calendar: calendar)
        _draftSelection = State(initialValue: clampedInitial)
    }

    private static func clamped(_ date: Date, to range: ClosedRange<Date>?, calendar: Calendar) -> Date {
        guard let range else { return date }
        let day = calendar.startOfDay(for: date)
        let lower = calendar.startOfDay(for: range.lowerBound)
        let upper = calendar.startOfDay(for: range.upperBound)
        if day < lower { return lower }
        if day > upper { return upper }
        return date
    }

    var body: some View {
        MistiaModalScaffold(
            titleView: {
                monthYearPicker
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
            .calendarHeaderHidden()
        }
    }

    private var monthYearPicker: some View {
        Button {
            isMonthYearPickerPresented = true
        } label: {
            HStack(spacing: 6) {
                Text(MistiaDateFormatting.monthYearString(for: draftSelection, calendar: calendar))
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
            .frame(height: 34)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isMonthYearPickerPresented) {
            MistiaMonthYearWheelPicker(
                selection: $draftSelection,
                calendar: calendar,
                language: language,
                selectableRange: selectableRange
            )
            .presentationCompactAdaptation(.popover)
        }
    }

    @State private var isMonthYearPickerPresented = false
}
