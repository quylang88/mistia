# Settlement Participant Input Row Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Hide the current user from the participant input section and place each participant name and paid amount field on one row.

**Architecture:** Reuse the existing `nonSelfParticipants` collection so settlement data remains unchanged. Simplify `SharedExpenseParticipantPaidInputRow` to a single horizontal layout with the existing localized paid-amount placeholder.

**Tech Stack:** SwiftUI, Mistia shared currency input component.

---

### Task 1: Simplify Participant Input Rendering

**Files:**
- Modify: `Mistia/Features/Transactions/SettlementSheets.swift:2314`

- [ ] **Step 1: Remove the self participant row**

Render only `nonSelfParticipants` inside `participantInputSection`. Do not change
`participantInputs`, `baseParticipantInputs`, or split calculation logic.

- [ ] **Step 2: Simplify the input row API**

Remove `currencyCode` and `lockedPaidMinor` from
`SharedExpenseParticipantPaidInputRow`, leaving only:

```swift
let participantName: String
@Binding var paidText: String
```

- [ ] **Step 3: Use a single horizontal row**

Render the participant name on the leading side and
`MistiaCurrencyInputField(L10n.transactions.settlement.paidAmount, ...)` on the
trailing side. Do not render a separate paid-amount label.

- [ ] **Step 4: Verify formatting**

Run:

```bash
git diff --check
```

Expected: exit code 0.

- [ ] **Step 5: Verify compilation**

Run:

```bash
xcodebuild -project Mistia.xcodeproj -scheme Mistia \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.
