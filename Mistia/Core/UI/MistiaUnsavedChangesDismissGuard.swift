import SwiftUI
import UIKit

struct MistiaDismissGuardConfiguration: Equatable {
    let mode: MistiaUnsavedChangesDismissalMode
    let hasUnsavedChanges: Bool

    init(
        mode: MistiaUnsavedChangesDismissalMode,
        hasUnsavedChanges: Bool
    ) {
        self.mode = mode
        self.hasUnsavedChanges = hasUnsavedChanges
    }

    var prompt: MistiaUnsavedChangesDismissalPrompt {
        MistiaUnsavedChangesDismissalPrompt(mode: mode)
    }

    var dismissalDecision: MistiaUnsavedChangesDismissalDecision {
        MistiaUnsavedChangesDismissalDecision.make(hasUnsavedChanges: hasUnsavedChanges)
    }
}

struct MistiaGuardedDismissButton<Label: View>: View {
    @Environment(\.dismiss) private var dismiss

    let configuration: MistiaDismissGuardConfiguration
    var isDisabled = false
    @ViewBuilder let label: () -> Label

    @State private var showsDiscardConfirmation = false

    var body: some View {
        Button {
            requestDismiss()
        } label: {
            label()
        }
        .disabled(isDisabled)
        .mistiaUnsavedChangesDiscardAlert(
            prompt: configuration.prompt,
            isPresented: $showsDiscardConfirmation,
            onDiscard: { dismiss() }
        )
    }

    private func requestDismiss() {
        switch configuration.dismissalDecision {
        case .dismissImmediately:
            dismiss()
        case .confirmDiscard:
            showsDiscardConfirmation = true
        }
    }
}

struct MistiaDismissIconLabel: View {
    var body: some View {
        Image(systemName: "xmark")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.secondary)
    }
}

extension MistiaGuardedDismissButton where Label == MistiaDismissIconLabel {
    init(
        configuration: MistiaDismissGuardConfiguration,
        isDisabled: Bool = false
    ) {
        self.configuration = configuration
        self.isDisabled = isDisabled
        self.label = {
            MistiaDismissIconLabel()
        }
    }
}

private struct MistiaUnsavedChangesDismissGuardModifier: ViewModifier {
    @Environment(\.dismiss) private var dismiss

    let configuration: MistiaDismissGuardConfiguration
    @State private var showsDiscardConfirmation = false

    func body(content: Content) -> some View {
        content
            .interactiveDismissDisabled(configuration.hasUnsavedChanges)
            .background {
                MistiaPresentationDismissAttemptObserver(
                    isDismissDisabled: configuration.hasUnsavedChanges,
                    onAttempt: {
                        showsDiscardConfirmation = true
                    }
                )
                .frame(width: 0, height: 0)
            }
            .mistiaUnsavedChangesDiscardAlert(
                prompt: configuration.prompt,
                isPresented: $showsDiscardConfirmation,
                onDiscard: { dismiss() }
            )
    }
}

private struct MistiaUnsavedChangesDiscardAlertModifier: ViewModifier {
    let prompt: MistiaUnsavedChangesDismissalPrompt
    @Binding var isPresented: Bool
    let onDiscard: () -> Void

    func body(content: Content) -> some View {
        content.alert(prompt.title, isPresented: $isPresented) {
            Button(prompt.cancelButtonTitle, role: .cancel) { }
            Button(prompt.discardButtonTitle, role: .destructive) {
                onDiscard()
            }
        } message: {
            Text(prompt.message)
        }
    }
}

private struct MistiaPresentationDismissAttemptObserver: UIViewControllerRepresentable {
    let isDismissDisabled: Bool
    let onAttempt: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(isDismissDisabled: isDismissDisabled, onAttempt: onAttempt)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        context.coordinator.isDismissDisabled = isDismissDisabled
        context.coordinator.onAttempt = onAttempt

        DispatchQueue.main.async {
            uiViewController.presentationController?.delegate = context.coordinator
            uiViewController.parent?.presentationController?.delegate = context.coordinator
        }
    }

    final class Coordinator: NSObject, UIAdaptivePresentationControllerDelegate {
        var isDismissDisabled: Bool
        var onAttempt: () -> Void

        init(isDismissDisabled: Bool, onAttempt: @escaping () -> Void) {
            self.isDismissDisabled = isDismissDisabled
            self.onAttempt = onAttempt
        }

        func presentationControllerShouldDismiss(_ presentationController: UIPresentationController) -> Bool {
            !isDismissDisabled
        }

        func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
            guard isDismissDisabled else { return }
            onAttempt()
        }
    }
}

extension View {
    func mistiaUnsavedChangesDismissGuard(
        configuration: MistiaDismissGuardConfiguration
    ) -> some View {
        modifier(MistiaUnsavedChangesDismissGuardModifier(configuration: configuration))
    }

    func mistiaUnsavedChangesDiscardAlert(
        prompt: MistiaUnsavedChangesDismissalPrompt,
        isPresented: Binding<Bool>,
        onDiscard: @escaping () -> Void
    ) -> some View {
        modifier(
            MistiaUnsavedChangesDiscardAlertModifier(
                prompt: prompt,
                isPresented: isPresented,
                onDiscard: onDiscard
            )
        )
    }
}
