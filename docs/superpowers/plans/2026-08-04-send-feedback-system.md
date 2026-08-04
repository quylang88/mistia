# Send Feedback & Smart Prompt System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the complete Send Feedback screen in Settings (`SendFeedbackView`), an occasional smart rating prompt on app launch (`FeedbackPromptSheet`), and the Supabase backend table (`user_feedbacks`).

**Architecture:** A modular SwiftUI feedback sheet with diagnostic collection, backed by a Supabase table with RLS. App launch rating prompts are controlled by `FeedbackPromptCoordinator` enforcing a 60-day cooldown and usage milestones.

**Tech Stack:** SwiftUI, PhotosUI (`PhotosPicker`), Supabase (PostgreSQL + RLS), SwiftData / AppStorage.

---

## File Map

### New Files
- `supabase/migrations/20260805000000_create_user_feedbacks_table.sql`
- `Mistia/Shared/Feedback/MistiaFeedbackModels.swift`
- `Mistia/Shared/Feedback/MistiaFeedbackService.swift`
- `Mistia/Features/Settings/SendFeedbackView.swift`
- `Mistia/Features/Settings/FeedbackPromptCoordinator.swift`
- `Mistia/Features/Settings/FeedbackPromptSheet.swift`
- `MistiaTests/FeedbackPromptCoordinatorTests.swift`

### Modified Files
- `Mistia/Features/Settings/SettingsView.swift` (wire feedback row to open sheet)
- `Mistia/App/RootTabView.swift` (trigger prompt coordinator check on launch)
- `Mistia/Localizable.xcstrings` (add feedback localized strings)

---

### Task 1: Supabase Database Migration for `user_feedbacks`

**Files:**
- Create: `supabase/migrations/20260805000000_create_user_feedbacks_table.sql`

- [ ] **Step 1: Write the Supabase migration SQL**

```sql
-- Migration: Create user_feedbacks table
CREATE TABLE IF NOT EXISTS public.user_feedbacks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    category TEXT NOT NULL CHECK (category IN ('bug', 'feature', 'general')),
    rating INT CHECK (rating >= 1 AND rating <= 5),
    content TEXT NOT NULL,
    device_info JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

ALTER TABLE public.user_feedbacks ENABLE ROW LEVEL SECURITY;

-- RLS Policy: Users can insert feedback records
CREATE POLICY "Users can insert feedback" ON public.user_feedbacks
    FOR INSERT WITH CHECK (auth.uid() = user_id OR user_id IS NULL);

-- RLS Policy: Authenticated users can read their own feedback records
CREATE POLICY "Users can view own feedback" ON public.user_feedbacks
    FOR SELECT USING (auth.uid() = user_id);
```

- [ ] **Step 2: Verify migration file syntax**

Verify file exists at `supabase/migrations/20260805000000_create_user_feedbacks_table.sql`.

- [ ] **Step 3: Commit (if auto_commit enabled)**

Check `.agent/config.yml` for `auto_commit` setting. Skip if `auto_commit: false`.

---

### Task 2: Core Feedback Data Models & Submission Service

**Files:**
- Create: `Mistia/Shared/Feedback/MistiaFeedbackModels.swift`
- Create: `Mistia/Shared/Feedback/MistiaFeedbackService.swift`

- [ ] **Step 1: Define DTOs and Enums in `MistiaFeedbackModels.swift`**

```swift
import Foundation

public enum MistiaFeedbackCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case bug = "bug"
    case feature = "feature"
    case general = "general"

    public var id: String { rawValue }
}

public struct MistiaFeedbackSubmission: Codable, Sendable {
    public let category: MistiaFeedbackCategory
    public let rating: Int?
    public let content: String
    public let deviceInfo: [String: String]?

    public init(
        category: MistiaFeedbackCategory,
        rating: Int? = nil,
        content: String,
        deviceInfo: [String: String]? = nil
    ) {
        self.category = category
        self.rating = rating
        self.content = content
        self.deviceInfo = deviceInfo
    }
}
```

- [ ] **Step 2: Implement `MistiaFeedbackService.swift`**

```swift
import Foundation
import Supabase

public protocol MistiaFeedbackServicing: Sendable {
    func submitFeedback(_ submission: MistiaFeedbackSubmission) async throws
}

public final class MistiaFeedbackService: MistiaFeedbackServicing, Sendable {
    public static let shared = MistiaFeedbackService()
    
    private init() {}

    public func submitFeedback(_ submission: MistiaFeedbackSubmission) async throws {
        let client = SupabaseClientProvider.shared.client
        struct FeedbackInsertDTO: Encodable {
            let category: String
            let rating: Int?
            let content: String
            let device_info: [String: String]?
        }

        let dto = FeedbackInsertDTO(
            category: submission.category.rawValue,
            rating: submission.rating,
            content: submission.content,
            device_info: submission.deviceInfo
        )

        try await client
            .from("user_feedbacks")
            .insert(dto)
            .execute()
    }
}
```

- [ ] **Step 3: Build project using swift build to ensure compilation**

Run: `swift build`
Expected: Build succeeded.

- [ ] **Step 4: Commit (if auto_commit enabled)**

Check `.agent/config.yml` for `auto_commit` setting. Skip if `auto_commit: false`.

---

### Task 3: Feedback Prompt Coordinator & Milestones

**Files:**
- Create: `Mistia/Features/Settings/FeedbackPromptCoordinator.swift`
- Create: `MistiaTests/FeedbackPromptCoordinatorTests.swift`

- [ ] **Step 1: Write unit tests for `FeedbackPromptCoordinator` in `MistiaTests/FeedbackPromptCoordinatorTests.swift`**

```swift
import XCTest
@testable import Mistia

final class FeedbackPromptCoordinatorTests: XCTestCase {
    func testShouldNotPresentPromptIfLaunchCountIsLessThanFive() {
        let userDefaults = UserDefaults(suiteName: #file)!
        userDefaults.removePersistentDomain(forName: #file)
        let coordinator = FeedbackPromptCoordinator(userDefaults: userDefaults)
        
        coordinator.recordAppLaunch() // count = 1
        XCTAssertFalse(coordinator.shouldPresentPrompt(now: Date()))
    }

    func testShouldPresentPromptWhenMilestonesMet() {
        let userDefaults = UserDefaults(suiteName: #file)!
        userDefaults.removePersistentDomain(forName: #file)
        let coordinator = FeedbackPromptCoordinator(userDefaults: userDefaults)
        
        let installDate = Date().addingTimeInterval(-4 * 86400) // 4 days ago
        coordinator.setFirstInstallDateForTesting(installDate)
        
        for _ in 1...5 {
            coordinator.recordAppLaunch()
        }
        
        XCTAssertTrue(coordinator.shouldPresentPrompt(now: Date()))
    }
}
```

- [ ] **Step 2: Implement `FeedbackPromptCoordinator.swift`**

```swift
import Foundation

@MainActor
public final class FeedbackPromptCoordinator: ObservableObject {
    public static let shared = FeedbackPromptCoordinator()

    private let userDefaults: UserDefaults

    private enum Keys {
        static let launchCount = "mistia_feedback_launch_count"
        static let firstInstallDate = "mistia_feedback_first_install_date"
        static let lastPromptDate = "mistia_feedback_last_prompt_date"
        static let optedOut = "mistia_feedback_opted_out"
    }

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if userDefaults.object(forKey: Keys.firstInstallDate) == nil {
            userDefaults.set(Date(), forKey: Keys.firstInstallDate)
        }
    }

    public func recordAppLaunch() {
        let count = userDefaults.integer(forKey: Keys.launchCount) + 1
        userDefaults.set(count, forKey: Keys.launchCount)
    }

    public func shouldPresentPrompt(now: Date = Date()) -> Bool {
        if userDefaults.bool(forKey: Keys.optedOut) { return false }

        let launchCount = userDefaults.integer(forKey: Keys.launchCount)
        guard launchCount >= 5 else { return false }

        guard let firstInstall = userDefaults.object(forKey: Keys.firstInstallDate) as? Date else { return false }
        let daysSinceInstall = Calendar.current.dateComponents([.day], from: firstInstall, to: now).day ?? 0
        guard daysSinceInstall >= 3 else { return false }

        if let lastPrompt = userDefaults.object(forKey: Keys.lastPromptDate) as? Date {
            let daysSinceLastPrompt = Calendar.current.dateComponents([.day], from: lastPrompt, to: now).day ?? 0
            if daysSinceLastPrompt < 60 { return false }
        }

        return true
    }

    public func recordPromptResponded(optOut: Bool = false) {
        userDefaults.set(Date(), forKey: Keys.lastPromptDate)
        if optOut {
            userDefaults.set(true, forKey: Keys.optedOut)
        }
    }

    func setFirstInstallDateForTesting(_ date: Date) {
        userDefaults.set(date, forKey: Keys.firstInstallDate)
    }
}
```

- [ ] **Step 3: Run unit test to verify tests pass**

Run: `swift test --filter FeedbackPromptCoordinatorTests`
Expected: All tests PASS.

- [ ] **Step 4: Commit (if auto_commit enabled)**

Check `.agent/config.yml` for `auto_commit` setting. Skip if `auto_commit: false`.

---

### Task 4: Full Feedback Sheet UI (`SendFeedbackView`)

**Files:**
- Create: `Mistia/Features/Settings/SendFeedbackView.swift`
- Modify: `Mistia/Features/Settings/SettingsView.swift`

- [ ] **Step 1: Create `SendFeedbackView.swift`**

```swift
import SwiftUI
import PhotosUI

public struct SendFeedbackView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var selectedCategory: MistiaFeedbackCategory = .bug
    @State private var contentText: String = ""
    @State private var includeDeviceInfo: Bool = true
    @State private var isSubmitting: Bool = false
    @State private var showSuccessToast: Bool = false
    @State private var selectedPhotoItem: PhotosPickerItem? = nil

    private var isSubmitDisabled: Bool {
        contentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting
    }

    public init(initialCategory: MistiaFeedbackCategory = .bug) {
        _selectedCategory = State(initialValue: initialCategory)
    }

    public var body: some View {
        MistiaPinnedTopBarScaffold(
            tone: .standard,
            title: L10n.settings.feedback.title,
            embedsInNavigationStack: false,
            showsLeadingAvatar: false,
            leadingSystemImage: "xmark",
            trailingSystemImage: nil,
            hidesSystemBackButton: true,
            onLeadingTap: { dismiss() },
            contentSpacing: 18
        ) {
            VStack(alignment: .leading, spacing: 18) {
                // Category Selector
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.settings.feedback.categoryTitle)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)

                    HStack(spacing: 8) {
                        CategoryPill(category: .bug, selected: $selectedCategory, title: L10n.settings.feedback.categoryBug)
                        CategoryPill(category: .feature, selected: $selectedCategory, title: L10n.settings.feedback.categoryFeature)
                        CategoryPill(category: .general, selected: $selectedCategory, title: L10n.settings.feedback.categoryGeneral)
                    }
                }

                // TextEditor
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.settings.feedback.contentTitle)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)

                    TextEditor(text: $contentText)
                        .frame(minHeight: 120)
                        .padding(8)
                        .background(Color(UIColor.secondarySystemGroupedBackground))
                        .cornerRadius(12)
                }

                // Photo Picker
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    HStack {
                        Image(systemName: "photo")
                        Text(selectedPhotoItem == nil ? L10n.settings.feedback.addPhoto : L10n.settings.feedback.photoAdded)
                        Spacer()
                    }
                    .padding()
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .cornerRadius(12)
                }

                // Device info toggle
                Toggle(isOn: $includeDeviceInfo) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.settings.feedback.includeDeviceInfoTitle)
                            .font(.body)
                        Text(deviceInfoPreview)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .cornerRadius(12)

                // Submit Button
                Button(action: submitFeedback) {
                    HStack {
                        if isSubmitting {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text(L10n.settings.feedback.submit)
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isSubmitDisabled ? Color.gray : Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(14)
                }
                .disabled(isSubmitDisabled)
            }
            .padding(.horizontal)
        }
        .alert(L10n.settings.feedback.successTitle, isPresented: $showSuccessToast) {
            Button(L10n.common.ok) { dismiss() }
        } message: {
            Text(L10n.settings.feedback.successMessage)
        }
    }

    private var deviceInfoPreview: String {
        "Mistia v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0") • iOS \(UIDevice.current.systemVersion)"
    }

    private func submitFeedback() {
        guard !isSubmitDisabled else { return }
        isSubmitting = true
        Task {
            let info: [String: String]? = includeDeviceInfo ? [
                "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
                "os_version": UIDevice.current.systemVersion,
                "device_model": UIDevice.current.model
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
                    showSuccessToast = true
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
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
                .font(.subheadline)
                .padding(.vertical, 8)
                .padding(.horizontal, 14)
                .background(isSelected ? Color.accentColor : Color(UIColor.secondarySystemGroupedBackground))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(20)
        }
    }
}
```

- [ ] **Step 2: Connect `SettingsView` row to present `SendFeedbackView` sheet**

In `Mistia/Features/Settings/SettingsView.swift`:
Add state `@State private var showFeedbackSheet = false`.
Update `handleTap(_ row: SettingsRowDump)`:
```swift
case .placeholder: // Or action for feedback row
    showFeedbackSheet = true
```
And add sheet modifier: `.sheet(isPresented: $showFeedbackSheet) { SendFeedbackView() }`.

- [ ] **Step 3: Run app build to verify compilation**

Run: `swift build`
Expected: Build succeeded.

- [ ] **Step 4: Commit (if auto_commit enabled)**

Check `.agent/config.yml` for `auto_commit` setting. Skip if `auto_commit: false`.

---

### Task 5: In-App Smart Rating Prompt Sheet (`FeedbackPromptSheet`)

**Files:**
- Create: `Mistia/Features/Settings/FeedbackPromptSheet.swift`
- Modify: `Mistia/App/RootTabView.swift`

- [ ] **Step 1: Create `FeedbackPromptSheet.swift`**

```swift
import SwiftUI

public struct FeedbackPromptSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedRating: Int? = nil
    @State private var showFullFeedbackSheet: Bool = false

    public var body: some View {
        VStack(spacing: 20) {
            Text("💬")
                .font(.system(size: 40))

            Text("Bạn cảm thấy Mistia thế nào?")
                .font(.title3)
                .fontWeight(.bold)

            Text("Ý kiến của bạn giúp chúng tôi hoàn thiện ứng dụng hơn mỗi ngày.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                EmojiRatingButton(emoji: "😡", rating: 1, selectedRating: $selectedRating, action: handleRating)
                EmojiRatingButton(emoji: "🙁", rating: 2, selectedRating: $selectedRating, action: handleRating)
                EmojiRatingButton(emoji: "😐", rating: 3, selectedRating: $selectedRating, action: handleRating)
                EmojiRatingButton(emoji: "😊", rating: 4, selectedRating: $selectedRating, action: handleRating)
                EmojiRatingButton(emoji: "😍", rating: 5, selectedRating: $selectedRating, action: handleRating)
            }
            .padding(.vertical, 10)

            HStack {
                Button("Để sau") {
                    FeedbackPromptCoordinator.shared.recordPromptResponded(optOut: false)
                    dismiss()
                }
                .foregroundColor(.secondary)

                Spacer()

                Button("Không hỏi lại") {
                    FeedbackPromptCoordinator.shared.recordPromptResponded(optOut: true)
                    dismiss()
                }
                .foregroundColor(.red)
            }
            .font(.footnote)
            .padding(.top, 10)
        }
        .padding(24)
        .presentationDetents([.height(300)])
        .presentationCornerRadius(24)
        .sheet(isPresented: $showFullFeedbackSheet) {
            SendFeedbackView(initialCategory: .bug)
        }
    }

    private func handleRating(_ rating: Int) {
        FeedbackPromptCoordinator.shared.recordPromptResponded(optOut: rating >= 4)
        if rating <= 3 {
            showFullFeedbackSheet = true
        } else {
            dismiss()
        }
    }
}

private struct EmojiRatingButton: View {
    let emoji: String
    let rating: Int
    @Binding var selectedRating: Int?
    let action: (Int) -> Void

    var body: some View {
        Button(action: {
            selectedRating = rating
            action(rating)
        }) {
            Text(emoji)
                .font(.system(size: 32))
                .padding(8)
                .background(selectedRating == rating ? Color.accentColor.opacity(0.2) : Color.clear)
                .clipShape(Circle())
        }
    }
}
```

- [ ] **Step 2: Trigger `FeedbackPromptCoordinator` in `RootTabView`**

In `Mistia/App/RootTabView.swift`:
Add `@State private var showPromptSheet = false`.
In `.onAppear` / `.task`:
```swift
FeedbackPromptCoordinator.shared.recordAppLaunch()
if FeedbackPromptCoordinator.shared.shouldPresentPrompt() {
    showPromptSheet = true
}
```
Add `.sheet(isPresented: $showPromptSheet) { FeedbackPromptSheet() }`.

- [ ] **Step 3: Run `swift build` and unit tests**

Run: `swift build && swift test`
Expected: All targets compile clean, unit tests PASS.

- [ ] **Step 4: Commit (if auto_commit enabled)**

Check `.agent/config.yml` for `auto_commit` setting. Skip if `auto_commit: false`.
