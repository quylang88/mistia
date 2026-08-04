import SwiftUI
import PhotosUI

struct SendFeedbackView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var selectedCategory: MistiaFeedbackCategory = .bug
    @State private var contentText: String = ""
    @State private var includeDeviceInfo: Bool = true
    @State private var isSubmitting: Bool = false
    @State private var showSuccessAlert: Bool = false
    @State private var showErrorAlert: Bool = false
    @State private var errorMessage: String? = nil
    @State private var selectedPhotoItem: PhotosPickerItem? = nil

    private let maxCharacterCount = 1000

    private var isSubmitDisabled: Bool {
        contentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting
    }

    init(initialCategory: MistiaFeedbackCategory = .bug) {
        _selectedCategory = State(initialValue: initialCategory)
    }

    var body: some View {
        MistiaPinnedTopBarScaffold(
            tone: .standard,
            title: L10n.settings.feedback.title,
            embedsInNavigationStack: false,
            showsLeadingAvatar: false,
            leadingSystemImage: "chevron.left",
            trailingSystemImage: nil,
            hidesSystemBackButton: true,
            onLeadingTap: { dismiss() },
            contentSpacing: 18
        ) {
            VStack(alignment: .leading, spacing: 18) {
                // Category Selector
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.settings.feedback.categoryTitle)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)

                    HStack(spacing: 8) {
                        CategoryPill(category: .bug, selected: $selectedCategory, title: L10n.settings.feedback.categoryBug)
                        CategoryPill(category: .feature, selected: $selectedCategory, title: L10n.settings.feedback.categoryFeature)
                        CategoryPill(category: .general, selected: $selectedCategory, title: L10n.settings.feedback.categoryGeneral)
                    }
                }

                // Feedback Content & TextEditor
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(L10n.settings.feedback.contentTitle)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text("\(contentText.count)/\(maxCharacterCount)")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(contentText.count >= maxCharacterCount ? .red : .secondary)
                    }
                    .padding(.horizontal, 4)

                    ZStack(alignment: .topLeading) {
                        if contentText.isEmpty {
                            Text(L10n.settings.feedback.contentPlaceholder)
                                .font(.system(size: 15, weight: .regular))
                                .foregroundStyle(.secondary.opacity(0.7))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .allowsHitTesting(false)
                        }

                        TextEditor(text: $contentText)
                            .font(.system(size: 15, weight: .regular))
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .frame(minHeight: 120, maxHeight: 180)
                    }
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .cornerRadius(16)
                    .onChange(of: contentText) { _, newValue in
                        if newValue.count > maxCharacterCount {
                            contentText = String(newValue.prefix(maxCharacterCount))
                        }
                    }
                }

                // Photos Picker
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    HStack(spacing: 10) {
                        Image(systemName: selectedPhotoItem == nil ? "photo.badge.plus" : "photo.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(selectedPhotoItem == nil ? .secondary : MistiaAccent.purple.color)

                        Text(selectedPhotoItem == nil ? L10n.settings.feedback.addPhoto : L10n.settings.feedback.photoAdded)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.primary)

                        Spacer()

                        if selectedPhotoItem != nil {
                            Button(action: { selectedPhotoItem = nil }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .cornerRadius(16)
                }

                // Include Device Info
                VStack(alignment: .leading, spacing: 6) {
                    Toggle(isOn: $includeDeviceInfo) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.settings.feedback.includeDeviceInfoTitle)
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .foregroundStyle(.primary)

                            Text(deviceInfoPreview)
                                .font(.system(size: 12, weight: .regular))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(MistiaAccent.purple.color)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .cornerRadius(16)

                // Submit Button
                Button(action: submitFeedback) {
                    HStack(spacing: 8) {
                        if isSubmitting {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text(L10n.settings.feedback.submit)
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(isSubmitDisabled ? Color.gray.opacity(0.4) : MistiaAccent.purple.color)
                    .foregroundColor(.white)
                    .cornerRadius(16)
                }
                .disabled(isSubmitDisabled)
            }
        }
        .alert(L10n.settings.feedback.successTitle, isPresented: $showSuccessAlert) {
            Button(L10n.common.ok) {
                dismiss()
            }
        } message: {
            Text(L10n.settings.feedback.successMessage)
        }
        .alert(L10n.common.error, isPresented: $showErrorAlert) {
            Button(L10n.common.ok, role: .cancel) {}
        } message: {
            Text(errorMessage ?? L10n.common.unknownError)
        }
    }

    private var deviceInfoPreview: String {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let osVersion = UIDevice.current.systemVersion
        return "Mistia v\(appVersion) • iOS \(osVersion) • \(DeviceModelResolver.currentMarketingName)"
    }

    private func submitFeedback() {
        guard !isSubmitDisabled else { return }
        isSubmitting = true

        Task {
            let info: [String: String]? = includeDeviceInfo ? [
                "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
                "os_version": UIDevice.current.systemVersion,
                "device_model": DeviceModelResolver.currentMarketingName
            ] : nil

            let submission = MistiaFeedbackSubmission(
                category: selectedCategory,
                content: contentText,
                deviceInfo: info
            )

            do {
                try await MistiaFeedbackService.shared.submitFeedback(submission)
                await MainActor.run {
                    isSubmitting = false
                    showSuccessAlert = true
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    errorMessage = error.localizedDescription
                    showErrorAlert = true
                }
            }
        }
    }
}

private struct CategoryPill: View {
    let category: MistiaFeedbackCategory
    @Binding var selected: MistiaFeedbackCategory
    let title: String

    var isSelected: Bool { selected == category }

    var body: some View {
        Button(action: { selected = category }) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .padding(.vertical, 8)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(isSelected ? MistiaAccent.purple.color : Color(UIColor.secondarySystemGroupedBackground))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(22)
        }
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
