# Send Feedback System Design Spec

**Date:** 2026-08-04  
**Status:** Draft  
**Target:** SwiftUI App (`Mistia`) & Supabase Backend  

---

## 1. Overview & Objectives

The Feedback System in **Mistia** allows users to submit bug reports, feature requests, or general comments directly within the application, as well as periodically asking active users for brief satisfaction ratings without causing prompt fatigue.

### Goals
1. **Full Feedback Screen (`SendFeedbackView`)**: Accessible via `Settings` -> `Gửi feedback`. Provides detailed inputs for category selection, text message, optional photo attachment, and auto-generated system diagnostics.
2. **Smart In-App Feedback Prompt (`FeedbackPromptSheet`)**: An occasional, unintrusive rating prompt shown on app launch after specific usage milestones (frequency capped at once every 60 days).
3. **Supabase Backend Integration**: Securely stores feedback records in a dedicated PostgreSQL table (`user_feedbacks`) with appropriate RLS policies.

---

## 2. System Architecture & Components

```mermaid
flowchart TD
    subgraph App UI
        SettingsView["SettingsView"] -->|Tap 'Gửi feedback'| SendFeedbackView["SendFeedbackView Sheet"]
        RootTabView["RootTabView / Launch"] -->|Check Milestones| FeedbackPromptCoordinator["FeedbackPromptCoordinator"]
        FeedbackPromptCoordinator -->|Trigger Capped Prompt| FeedbackPromptSheet["FeedbackPromptSheet (Popup)"]
        FeedbackPromptSheet -->|Low Rating (1-3 stars)| SendFeedbackView
    end

    subgraph Data Layer
        SendFeedbackView -->|Submit Payload| FeedbackService["FeedbackService"]
        FeedbackService -->|Insert Row| SupabaseTable["Supabase Table: user_feedbacks"]
    end
```

---

## 3. Component Details

### A. Full Feedback View (`SendFeedbackView`)
- **Location**: `Mistia/Features/Settings/SendFeedbackView.swift`
- **UI Structure**:
  - `MistiaPinnedTopBarScaffold` with "Hủy" (Dismiss) and "Gửi" (Submit).
  - **Category Picker**: `Segmented` or pill buttons (`🐛 Báo lỗi`, `💡 Ý tưởng`, `💬 Khác`).
  - **Content TextEditor**: Multi-line text field with placeholder and 1000-character limit counter.
  - **Photo Attachment**: Optional image selection using `PhotosPicker`.
  - **System Diagnostics Toggle**: "Gửi kèm thông tin thiết bị" (default: `true`). Shows preview of collected info: App version (`Bundle.main`), OS version (`UIDevice.current.systemVersion`), Device model (`UIDevice.current.model`), User ID (`Supabase.auth.user.id`).
  - **Submit Button**: Submits payload with loading animation indicator and presents success toast.

### B. Smart In-App Feedback Prompt (`FeedbackPromptSheet` & Coordinator)
- **Location**: `Mistia/Features/Settings/FeedbackPromptCoordinator.swift` & `FeedbackPromptSheet.swift`
- **Milestone & Capping Rules**:
  - **Launch Count**: Must have opened the app $\ge 5$ times.
  - **App Age**: Account/Install age $\ge 3$ days.
  - **Cooldown**: Minimum 60 days between prompts.
  - **Dismiss / Never Ask Again**: If user taps "Không hỏi lại" or submits rating, set flag `hasOptedOutFeedbackPrompt = true` in `@AppStorage`.
- **Interactions**:
  - 5 Emoji Ratings: 😡 (1), 🙁 (2), 😐 (3), 😊 (4), 😍 (5).
  - **1-3 Stars**: Transitions directly to `SendFeedbackView` with category pre-selected as "Báo lỗi" or "Khác" so the user can detail their issue.
  - **4-5 Stars**: Shows a "Cảm ơn bạn! 💖" message and presents an optional button to review on the App Store (if configured) or submit quick praise.

### C. Backend Database Migration (`user_feedbacks`)
- **Location**: `supabase/migrations/20260805000000_create_user_feedbacks_table.sql`
- **Schema**:
  ```sql
  CREATE TABLE public.user_feedbacks (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
      category TEXT NOT NULL CHECK (category IN ('bug', 'feature', 'general')),
      rating INT CHECK (rating >= 1 AND rating <= 5),
      content TEXT NOT NULL,
      device_info JSONB DEFAULT '{}'::jsonb,
      created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
  );

  ALTER TABLE public.user_feedbacks ENABLE ROW LEVEL SECURITY;

  -- Allow authenticated and anonymous users to insert their own feedback
  CREATE POLICY "Users can insert feedback" ON public.user_feedbacks
      FOR INSERT WITH CHECK (auth.uid() = user_id OR user_id IS NULL);
  ```

---

## 4. Localized Strings & Assets

Localizable keys in `Localizable.xcstrings`:
- `settings.feedback.title`: "Gửi feedback" / "Send feedback" / "フィードバック"
- `settings.feedback.category.bug`: "🐛 Báo lỗi" / "🐛 Bug Report"
- `settings.feedback.category.feature`: "💡 Ý tưởng" / "💡 Feature Request"
- `settings.feedback.category.general`: "💬 Khác" / "💬 General"
- `settings.feedback.device_info.title`: "Đính kèm thông tin thiết bị" / "Include device information"
- `settings.feedback.submit.success`: "Cảm ơn bạn đã đóng góp ý kiến!" / "Thank you for your feedback!"

---

## 5. Verification Plan

### Automated Tests
- Unit tests for `FeedbackPromptCoordinator`: Test milestone counting, 60-day cooldown logic, and opt-out flags (`MistiaTests/FeedbackPromptTests.swift`).
- Test Supabase feedback submission DTO encoding.

### Manual Verification
1. Tap "Gửi feedback" in Settings -> Verify `SendFeedbackView` sheet opens with category selector, text editor, diagnostics toggle, and submit button.
2. Submit feedback -> Verify entry is inserted into Supabase `user_feedbacks` table.
3. Simulate app opens -> Verify `FeedbackPromptSheet` appears only when criteria are met and respects cooldown.
