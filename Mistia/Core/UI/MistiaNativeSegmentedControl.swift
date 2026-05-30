import SwiftUI
import UIKit

struct MistiaNativeSegmentedControl<Option: Hashable>: View {
    @Environment(\.locale) private var locale
    @Binding var selection: Option

    let options: [Option]
    let title: (Option) -> String
    var isEnabled: (Option) -> Bool = { _ in true }

    var body: some View {
        MistiaSegmentedControlRepresentable(
            selection: $selection,
            options: options,
            title: title,
            isEnabled: isEnabled,
            localeIdentifier: locale.identifier
        )
        .frame(maxWidth: .infinity)
        .frame(height: 32)
    }
}

private struct MistiaSegmentedControlRepresentable<Option: Hashable>: UIViewRepresentable {
    @Binding var selection: Option

    let options: [Option]
    let title: (Option) -> String
    let isEnabled: (Option) -> Bool
    let localeIdentifier: String

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
