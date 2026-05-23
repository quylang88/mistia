import SwiftUI
import UIKit

struct MistiaNativeSegmentedControl<Option: Hashable>: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale
    @Binding var selection: Option

    let options: [Option]
    let title: (Option) -> String
    var isEnabled: (Option) -> Bool = { _ in true }
    var accent: Color = Color(red: 0.43, green: 0.23, blue: 0.76)

    var body: some View {
        MistiaSegmentedControlRepresentable(
            selection: $selection,
            options: options,
            title: title,
            isEnabled: isEnabled,
            localeIdentifier: locale.identifier,
            selectedSegmentTintColor: selectedSegmentTintColor,
            backgroundColor: backgroundColor,
            selectedTextColor: selectedTextColor,
            normalTextColor: normalTextColor
        )
        .frame(maxWidth: .infinity)
        .frame(height: 32)
    }

    private var selectedSegmentTintColor: UIColor {
        if colorScheme == .dark {
            return UIColor(red: 0.34, green: 0.18, blue: 0.60, alpha: 0.92)
        }
        return UIColor(accent).withAlphaComponent(0.98)
    }

    private var backgroundColor: UIColor {
        return UIColor.secondarySystemGroupedBackground
    }

    private var selectedTextColor: UIColor {
        if colorScheme == .dark {
            return UIColor.white
        }
        return UIColor.white
    }

    private var normalTextColor: UIColor {
        if colorScheme == .dark {
            return UIColor(red: 0.94, green: 0.94, blue: 0.97, alpha: 0.96)
        }
        return UIColor(white: 0.28, alpha: 1)
    }
}

private struct MistiaSegmentedControlRepresentable<Option: Hashable>: UIViewRepresentable {
    @Binding var selection: Option

    let options: [Option]
    let title: (Option) -> String
    let isEnabled: (Option) -> Bool
    let localeIdentifier: String
    let selectedSegmentTintColor: UIColor
    let backgroundColor: UIColor
    let selectedTextColor: UIColor
    let normalTextColor: UIColor

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection, options: options, isEnabled: isEnabled)
    }

    func makeUIView(context: Context) -> UISegmentedControl {
        let control = UISegmentedControl(items: options.map(title))
        control.addTarget(
            context.coordinator,
            action: #selector(Coordinator.valueChanged(_:)),
            for: .valueChanged
        )
        control.apportionsSegmentWidthsByContent = false
        control.selectedSegmentIndex = max(0, options.firstIndex(of: selection) ?? 0)
        for (index, option) in options.enumerated() {
            control.setEnabled(isEnabled(option), forSegmentAt: index)
        }
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        updateAppearance(for: control)
        return control
    }

    func updateUIView(_ control: UISegmentedControl, context: Context) {
        context.coordinator.selection = $selection
        context.coordinator.options = options
        context.coordinator.isEnabled = isEnabled

        if control.numberOfSegments != options.count {
            control.removeAllSegments()
            for (index, option) in options.enumerated() {
                control.insertSegment(withTitle: title(option), at: index, animated: false)
            }
        } else {
            for (index, option) in options.enumerated() {
                let nextTitle = title(option)
                if control.titleForSegment(at: index) != nextTitle {
                    control.setTitle(nextTitle, forSegmentAt: index)
                }
            }
        }
        for (index, option) in options.enumerated() {
            control.setEnabled(isEnabled(option), forSegmentAt: index)
        }

        control.selectedSegmentIndex = options.firstIndex(of: selection) ?? UISegmentedControl.noSegment
        updateAppearance(for: control)
    }

    private func updateAppearance(for control: UISegmentedControl) {
        control.selectedSegmentTintColor = selectedSegmentTintColor
        control.backgroundColor = backgroundColor

        let normalAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: normalTextColor,
            .font: UIFont.systemFont(ofSize: 13, weight: .semibold)
        ]
        let selectedAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: selectedTextColor,
            .font: UIFont.systemFont(ofSize: 13, weight: .semibold)
        ]

        control.setTitleTextAttributes(normalAttributes, for: .normal)
        control.setTitleTextAttributes(selectedAttributes, for: .selected)
    }

    final class Coordinator: NSObject {
        var selection: Binding<Option>
        var options: [Option]
        var isEnabled: (Option) -> Bool

        init(
            selection: Binding<Option>,
            options: [Option],
            isEnabled: @escaping (Option) -> Bool
        ) {
            self.selection = selection
            self.options = options
            self.isEnabled = isEnabled
        }

        @objc func valueChanged(_ control: UISegmentedControl) {
            guard control.selectedSegmentIndex != UISegmentedControl.noSegment,
                  options.indices.contains(control.selectedSegmentIndex),
                  isEnabled(options[control.selectedSegmentIndex]) else {
                return
            }

            selection.wrappedValue = options[control.selectedSegmentIndex]
        }
    }
}
