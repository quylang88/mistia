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
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var loadedImages: [UIImage] = []

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

                // Photos Section
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(L10n.settings.feedback.photoSectionTitle)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text("\(loadedImages.count)/5")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(loadedImages.count >= 5 ? MistiaAccent.purple.color : .secondary)
                    }
                    .padding(.horizontal, 4)

                    if loadedImages.isEmpty {
                        PhotosPicker(
                            selection: $selectedPhotoItems,
                            maxSelectionCount: 5,
                            matching: .images
                        ) {
                            HStack(spacing: 10) {
                                Image(systemName: "photo.badge.plus")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(MistiaAccent.purple.color)

                                Text(L10n.settings.feedback.addPhoto)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(.primary)

                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(Color(UIColor.secondarySystemGroupedBackground))
                            .cornerRadius(16)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(Array(loadedImages.enumerated()), id: \.offset) { index, uiImage in
                                        ZStack(alignment: .topTrailing) {
                                            Image(uiImage: uiImage)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 76, height: 76)
                                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                                                )

                                            Button(action: { removeImage(at: index) }) {
                                                Image(systemName: "xmark.circle.fill")
                                                    .font(.system(size: 20))
                                                    .symbolRenderingMode(.palette)
                                                    .foregroundStyle(Color.white, Color.secondary)
                                            }
                                            .offset(x: 6, y: -6)
                                        }
                                        .padding(.top, 6)
                                        .padding(.trailing, 6)
                                    }

                                    if loadedImages.count < 5 {
                                        PhotosPicker(
                                            selection: $selectedPhotoItems,
                                            maxSelectionCount: 5,
                                            matching: .images
                                        ) {
                                            VStack(spacing: 4) {
                                                Image(systemName: "plus")
                                                    .font(.system(size: 20, weight: .semibold))
                                                    .foregroundStyle(MistiaAccent.purple.color)

                                                Text(L10n.common.add)
                                                    .font(.system(size: 11, weight: .medium))
                                                    .foregroundStyle(.secondary)
                                            }
                                            .frame(width: 76, height: 76)
                                            .background(Color(UIColor.tertiarySystemGroupedBackground))
                                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                    .strokeBorder(MistiaAccent.purple.color.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                            )
                                        }
                                        .padding(.top, 6)
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                            }
                        }
                        .background(Color(UIColor.secondarySystemGroupedBackground))
                        .cornerRadius(16)
                    }
                }
                .onChange(of: selectedPhotoItems) { _, newItems in
                    loadSelectedImages(from: newItems)
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
        CurrentDeviceInfo.current().displaySummary
    }

    private func submitFeedback() {
        guard !isSubmitDisabled else { return }
        isSubmitting = true

        Task {
            let info: [String: String]? = includeDeviceInfo
                ? CurrentDeviceInfo.current().asDictionary
                : nil

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

    private func loadSelectedImages(from items: [PhotosPickerItem]) {
        Task {
            var images: [UIImage] = []
            for item in items.prefix(5) {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    images.append(uiImage)
                }
            }
            await MainActor.run {
                loadedImages = images
            }
        }
    }

    private func removeImage(at index: Int) {
        guard index >= 0 && index < loadedImages.count else { return }
        loadedImages.remove(at: index)
        if index < selectedPhotoItems.count {
            selectedPhotoItems.remove(at: index)
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
