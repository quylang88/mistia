# Settlement Inline Share Edit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace always-visible participant share inputs with explicit inline edit/save controls while allowing independent manual shares and displaying any total allocation difference.

**Architecture:** `SettlementLogic` will calculate the automatic equal split first, then overlay each committed manual share without changing any other participant. `SettlementSplitCalculatorSheet` will own one active draft at a time and commit it into the existing override dictionary. The shared UIKit-backed currency field will gain opt-in focus and select-all behavior so the inline editor opens the number pad with the current amount selected.

**Tech Stack:** Swift 6, SwiftUI, UIKit `UITextField`, XCTest, Apple String Catalog.

---

### Task 1: Preserve Automatic Shares When One Participant Is Edited

**Files:**
- Modify: `Tests/MistiaCoreLogicTests/SettlementLogicTests.swift`
- Modify: `MistiaTests/TransactionLogicTests.swift`
- Modify: `Mistia/Shared/CoreLogic/TransactionLogic.swift`

- [ ] **Step 1: Replace obsolete validation tests with failing independent-override tests**

Add the following tests to
`Tests/MistiaCoreLogicTests/SettlementLogicTests.swift`:

```swift
func testManualShareOverrideDoesNotRedistributeOtherParticipants() {
    let organizerID = UUID()
    let secondID = UUID()
    let thirdID = UUID()
    let participants = [
        SettlementParticipantInput(id: organizerID, name: "Me", paidMinor: 9_000),
        SettlementParticipantInput(id: secondID, name: "An", paidMinor: 0, shareOverrideMinor: 4_000),
        SettlementParticipantInput(id: thirdID, name: "Binh", paidMinor: 0)
    ]

    let result = SettlementLogic.sharedExpenseSettlement(
        participants: participants,
        organizerID: organizerID
    )

    XCTAssertEqual(result.participants.map(\.shareMinor), [3_000, 4_000, 3_000])
}

func testManualSharesMayExceedTotalPaidAndReportPositiveDifference() {
    let participants = [
        SettlementParticipantInput(name: "Me", paidMinor: 6_000, shareOverrideMinor: 4_000),
        SettlementParticipantInput(name: "An", paidMinor: 0, shareOverrideMinor: 3_000)
    ]

    let result = SettlementLogic.sharedExpenseSettlement(
        participants: participants,
        organizerID: participants[0].id
    )

    XCTAssertEqual(SettlementLogic.totalShareDifference(for: result), 1_000)
}

func testManualSharesMayRemainBelowTotalPaidAndReportNegativeDifference() {
    let participants = [
        SettlementParticipantInput(name: "Me", paidMinor: 6_000, shareOverrideMinor: 4_000),
        SettlementParticipantInput(name: "An", paidMinor: 0, shareOverrideMinor: 1_000)
    ]

    let result = SettlementLogic.sharedExpenseSettlement(
        participants: participants,
        organizerID: participants[0].id
    )

    XCTAssertEqual(SettlementLogic.totalShareDifference(for: result), -1_000)
}
```

- [ ] **Step 2: Run the focused tests and confirm RED**

Run:

```bash
swift test --filter SettlementLogicTests
```

Expected: compilation fails because `totalShareDifference(for:)` does not
exist, and the independent-override expectation does not match current
redistribution behavior.

- [ ] **Step 3: Change the split algorithm**

In `SettlementLogic.sharedExpenseSettlement`, calculate an automatic share for
every participant from `totalPaid / participantCount`, assign the remainder to
the organizer, and then use:

```swift
let share = participant.shareOverrideMinor ?? automaticShare
```

Do not subtract explicit shares before calculating automatic shares.

Add:

```swift
static func totalShareDifference(
    for result: SettlementSharedExpenseResult
) -> Int64 {
    result.participants.reduce(Int64.zero) { $0 + $1.shareMinor }
        - result.totalPaidMinor
}
```

Remove `SettlementShareOverrideValidation` and
`shareOverrideValidation(for:)` if no remaining callers exist.

Replace the two obsolete validation tests in
`MistiaTests/TransactionLogicTests.swift` with the same independent-override
and total-difference expectations so the Xcode test target remains aligned with
the SwiftPM core-logic tests.

- [ ] **Step 4: Run the focused tests and confirm GREEN**

Run:

```bash
swift test --filter SettlementLogicTests
```

Expected: all selected tests pass.

- [ ] **Step 5: Commit core logic**

```bash
git add Tests/MistiaCoreLogicTests/SettlementLogicTests.swift \
  MistiaTests/TransactionLogicTests.swift \
  Mistia/Shared/CoreLogic/TransactionLogic.swift
git commit -m "fix: preserve independent settlement shares"
```

### Task 2: Add Opt-In Currency Field Autofocus

**Files:**
- Modify: `Mistia/Shared/Modifiers/KeyboardModifiers.swift`

- [ ] **Step 1: Extend the public currency field API**

Add optional properties and initializer arguments:

```swift
var requestsFocus: Bool = false
var selectsAllOnFocus: Bool = false
```

Pass both values to `MistiaCurrencyUITextField`.

- [ ] **Step 2: Implement UIKit focus and selection**

Add the same properties to `MistiaCurrencyUITextField`. In `updateUIView`,
after formatting the text:

```swift
guard requestsFocus, !uiView.isFirstResponder else { return }

DispatchQueue.main.async {
    guard requestsFocus else { return }
    uiView.becomeFirstResponder()
    if selectsAllOnFocus {
        uiView.selectAll(nil)
    }
}
```

Keep both defaults `false` so existing currency fields do not change behavior.

- [ ] **Step 3: Verify compilation**

Run:

```bash
xcodebuild -project Mistia.xcodeproj -scheme Mistia \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit shared input support**

```bash
git add Mistia/Shared/Modifiers/KeyboardModifiers.swift
git commit -m "feat: support focused currency input editing"
```

### Task 3: Build Commit-Based Inline Share Rows

**Files:**
- Modify: `Mistia/Features/Transactions/SettlementSheets.swift`

- [ ] **Step 1: Add active draft state**

Add:

```swift
@State private var editingShareParticipantID: UUID?
@State private var editingShareText = ""
```

Update the dismissal guard so an active editor counts as unsaved:

```swift
|| editingShareParticipantID != nil
```

- [ ] **Step 2: Remove share-total validation gates**

Delete the `shareOverrideValidation` property and its message helper. Change:

```swift
private var canFinalizeSplit: Bool {
    !nonSelfParticipants.isEmpty
        && allInputsProvided
        && editingShareParticipantID == nil
}
```

Allow `suggestionsForSelf` whenever all paid inputs are present. Remove the
validation message row and validation guard from `finalizeSplit`.

- [ ] **Step 3: Add edit, save, and automatic-reset actions**

Add:

```swift
private func beginEditingShare(_ participant: SettlementParticipantResult) {
    editingShareText = String(participant.shareMinor)
    editingShareParticipantID = participant.id
}

private func commitEditingShare(for participantID: UUID) {
    let trimmed = editingShareText.trimmingCharacters(in: .whitespacesAndNewlines)
    shareTextsByParticipantID[participantID] = trimmed.isEmpty ? "0" : editingShareText
    editingShareParticipantID = nil
    editingShareText = ""
}

private func resetDraftSharesToAutomatic() {
    shareTextsByParticipantID = [:]
    editingShareParticipantID = nil
    editingShareText = ""
}
```

Add:

```swift
private var totalShareDifferenceMinor: Int64 {
    SettlementLogic.totalShareDifference(for: splitResult)
}
```

- [ ] **Step 4: Replace the result row call**

Pass display/edit state and closures into
`SharedExpenseParticipantShareEditRow`:

```swift
SharedExpenseParticipantShareEditRow(
    participant: participant,
    currencyCode: currencyCode,
    adjustmentDeltaMinor: manualShareDelta(
        for: participant.id,
        baseShareMinor: baseShareMinor
    ),
    isEditing: editingShareParticipantID == participant.id,
    isAnotherRowEditing: editingShareParticipantID != nil
        && editingShareParticipantID != participant.id,
    editingText: $editingShareText,
    onEdit: { beginEditingShare(participant) },
    onSave: { commitEditingShare(for: participant.id) }
)
```

Remove `shareEditTextBinding`.

- [ ] **Step 5: Add informational total difference and draft reset**

After participant rows, show this only when the difference is nonzero:

```swift
if totalShareDifferenceMinor != 0 {
    Label(
        L10n.transactions.settlement.totalShareDifference(
            formattedSignedDifference(totalShareDifferenceMinor)
        ),
        systemImage: "info.circle"
    )
    .font(.system(size: 13, weight: .semibold, design: .rounded))
    .foregroundStyle(.secondary)
}
```

When `shareTextsByParticipantID` is not empty, add:

```swift
Button {
    resetDraftSharesToAutomatic()
} label: {
    Label(
        L10n.transactions.settlement.recalculateSplit,
        systemImage: "arrow.counterclockwise"
    )
}
```

- [ ] **Step 6: Redesign `SharedExpenseParticipantShareEditRow`**

Replace the separate paid/share blocks with one horizontal row:

```swift
HStack(spacing: 8) {
    VStack(alignment: .leading, spacing: 5) {
        Text(participant.name)
        if let adjustmentDeltaMinor {
            Text(
                L10n.transactions.settlement.manualShareAdjustmentBadge(
                    formattedAdjustmentDelta(adjustmentDeltaMinor)
                )
            )
        }
    }

    Spacer(minLength: 8)

    if isEditing {
        MistiaCurrencyInputField(
            L10n.transactions.settlement.share,
            text: $editingText,
            font: .mistiaRounded(size: 16, weight: .semibold),
            showsCalculatorButton: false,
            requestsFocus: true,
            selectsAllOnFocus: true
        )
        .multilineTextAlignment(.trailing)
        .frame(width: 132, minHeight: 36)
    } else {
        Text(participant.shareMinor.formattedCurrency(code: currencyCode))
    }

    Button(action: isEditing ? onSave : onEdit) {
        Image(systemName: isEditing ? "checkmark" : "pencil")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(MistiaAccent.checkmarkPurple.color)
            .frame(width: 30, height: 30)
            .background {
                Circle().fill(Color(UIColor.tertiarySystemFill))
            }
    }
    .buttonStyle(.plain)
    .disabled(isAnotherRowEditing)
}
```

Keep the existing signed adjustment formatting and colors. Remove the net
amount from this participant row because settlement suggestions below already
show the resulting pay/receive amounts.

- [ ] **Step 7: Build and inspect compiler feedback**

Run:

```bash
xcodebuild -project Mistia.xcodeproj -scheme Mistia \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 8: Commit inline row implementation**

```bash
git add Mistia/Features/Transactions/SettlementSheets.swift
git commit -m "feat: edit settlement shares inline"
```

### Task 4: Localize New Inline Share Copy

**Files:**
- Modify: `Mistia/Localizable.xcstrings`
- Regenerate: `Mistia/Shared/CoreLogic/L10n.generated.swift`
- Modify: `Mistia/Features/Transactions/SettlementSheets.swift`

- [ ] **Step 1: Add String Catalog keys**

Add `vi`, `en`, and `ja` values:

```text
transactions.settlement.editParticipantShare
vi: Sửa phần chia của %@
en: Edit %@'s share
ja: %@ の負担額を編集

transactions.settlement.saveParticipantShare
vi: Lưu phần chia của %@
en: Save %@'s share
ja: %@ の負担額を保存

transactions.settlement.totalShareDifference
vi: Chênh lệch tổng %@
en: Total difference %@
ja: 合計差額 %@
```

Remove the obsolete validation keys:

```text
transactions.settlement.allManualSharesMustMatchTotalPaid
transactions.settlement.manualShareTotalExceedsTotalPaid
```

- [ ] **Step 2: Apply accessibility labels**

On the inline icon button use:

```swift
.accessibilityLabel(
    isEditing
        ? L10n.transactions.settlement.saveParticipantShare(participant.name)
        : L10n.transactions.settlement.editParticipantShare(participant.name)
)
```

- [ ] **Step 3: Regenerate and validate localization**

Run:

```bash
swift Scripts/generate-l10n.swift \
  --input Mistia/Localizable.xcstrings \
  --output Mistia/Shared/CoreLogic/L10n.generated.swift

swift Scripts/generate-l10n.swift \
  --input Mistia/Localizable.xcstrings \
  --output Mistia/Shared/CoreLogic/L10n.generated.swift \
  --strict-keys \
  --check

/Users/quylang/.codex/skills/mistia-string-catalog-l10n/scripts/check_mistia_l10n.sh
```

Expected: all commands exit 0.

- [ ] **Step 4: Commit localization**

```bash
git add Mistia/Localizable.xcstrings \
  Mistia/Shared/CoreLogic/L10n.generated.swift \
  Mistia/Features/Transactions/SettlementSheets.swift
git commit -m "feat: localize settlement share editing"
```

### Task 5: Final Verification

**Files:**
- Verify all files changed by Tasks 1-4.

- [ ] **Step 1: Run focused logic tests**

```bash
swift test --filter SettlementLogicTests
```

Expected: all selected tests pass.

- [ ] **Step 2: Run localization checks**

```bash
swift Scripts/generate-l10n.swift \
  --input Mistia/Localizable.xcstrings \
  --output Mistia/Shared/CoreLogic/L10n.generated.swift \
  --strict-keys \
  --check

/Users/quylang/.codex/skills/mistia-string-catalog-l10n/scripts/check_mistia_l10n.sh
```

Expected: both commands exit 0.

- [ ] **Step 3: Build the app target**

```bash
xcodebuild -project Mistia.xcodeproj -scheme Mistia \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Check the complete diff**

```bash
git diff --check
git status --short
git log --oneline -6
```

Expected: no whitespace errors; only intentional files are changed; all
implementation commits are present.
