# Backup & Restore Screen Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign `ManagementBackupRestoreView` in `Mistia/Features/Management/ManagementAuthView.swift` according to iOS 26 native minimalist standards with a Hero Status card, streamlined Grouped Action list, compact Menu Picker for Restore Mode, and a summary breakdown sheet.

**Architecture:** Refactor `ManagementBackupRestoreView` body and subcomponents. Add `@State private var showSummaryDetailSheet = false`. Replace the top emergency message card and noisy summary text block with a sleek Hero Status card, compact actions card, and menu picker options card. Add a detail sheet to present `latestSummary.localizedBreakdown`.

**Tech Stack:** SwiftUI, SwiftData, Swift Package Manager.

---

### Task 1: Redesign ManagementBackupRestoreView Layout & Components

**Files:**
- Modify: `Mistia/Features/Management/ManagementAuthView.swift:4821-4988`

- [ ] **Step 1: Add summary detail sheet state and build Hero Status Card & Menu Picker**

Update `ManagementBackupRestoreView` state and body layout in `Mistia/Features/Management/ManagementAuthView.swift`:

```swift
// Add new state variable inside ManagementBackupRestoreView:
@State private var showSummaryDetailSheet = false
```

Replace the content of `MistiaPinnedTopBarScaffold` with:

```swift
        MistiaPinnedTopBarScaffold(
            tone: isModalPresentation ? .modal : .standard,
            title: L10n.management.managementauth.backupRestore,
            embedsInNavigationStack: false,
            showsLeadingAvatar: false,
            leadingSystemImage: isModalPresentation ? "xmark" : "chevron.left",
            trailingSystemImage: nil,
            hidesSystemBackButton: true,
            onLeadingTap: { dismiss() },
            contentSpacing: 18,
            contentBottomPadding: isModalPresentation ? 40 : 150
        ) {
            // Hero Status Card
            heroStatusCard

            // Action Group Card
            ManagementProfileListCard(tint: cardTint) {
                VStack(spacing: 0) {
                    backupActionRow(
                        title: L10n.management.managementauth.createSnapshot,
                        subtitle: L10n.management.managementauth.exportTheCurrentLocalDataIntoA,
                        systemImage: "square.and.arrow.up.fill",
                        tint: .blue,
                        isDisabled: isBusy,
                        action: exportSnapshot
                    )

                    ManagementProfileRowDivider()

                    backupActionRow(
                        title: L10n.management.managementauth.importSnapshot,
                        subtitle: restoreMode == .merge
                            ? L10n.management.managementauth.importTheFileAndLetSnapshotValues
                            : L10n.management.managementauth.importTheFileAndReplaceTheCurrent,
                        systemImage: "square.and.arrow.down.fill",
                        tint: .mint,
                        isDisabled: isBusy,
                        action: { isImporting = true }
                    )
                }
            }

            // Restore Mode Options Card with Menu Picker
            ManagementProfileListCard(tint: cardTint) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.management.managementauth.restoreMode)
                                .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                                .foregroundStyle(.primary)

                            Text(restoreMode.localizedDescription)
                                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        Spacer()

                        Picker(String(), selection: $restoreMode) {
                            ForEach(MistiaBackupRestoreMode.allCases) { mode in
                                Text(mode.localizedTitle).tag(mode)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(accent)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }

            if sessionStore.isManualSyncRequiredAfterRestore {
                ManagementInlineMessageCard(
                    title: L10n.management.managementauth.waitingForYourReviewBeforeSync,
                    message: L10n.management.managementauth.autoSyncIsPausedAfterTheRestore,
                    accent: .orange
                )
            }

            if let latestRestoreResult, let safetySnapshotURL = latestRestoreResult.safetySnapshotURL {
                ManagementProfileListCard(tint: cardTint) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L10n.management.managementauth.internalSafetySnapshot)
                            .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)

                        Text(
                            L10n.management.managementauth.mistiaCreatedASafetySnapshotBeforeReplacing
                        )
                        .descriptionTextStyle()

                        Button {
                            shareItem = TransactionShareItem(url: safetySnapshotURL)
                        } label: {
                            Label(
                                L10n.management.managementauth.shareSafetySnapshot,
                                systemImage: "square.and.arrow.up"
                            )
                            .font(.system(size: 14.5, weight: .semibold, design: .rounded))
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(accent)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 15)
                }
            }
        }
```

- [ ] **Step 2: Define heroStatusCard and summary detail sheet helper**

Add `heroStatusCard` property and detail sheet modifier inside `ManagementBackupRestoreView`:

```swift
    private var heroStatusCard: some View {
        ManagementProfileListCard(tint: cardTint) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(latestSummary != nil ? Color.green.opacity(0.15) : Color.blue.opacity(0.15))
                            .frame(width: 44, height: 44)

                        Image(systemName: latestSummary != nil ? "checkmark.shield.fill" : "clock.arrow.circlepath")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(latestSummary != nil ? Color.green : Color.blue)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(latestSummary != nil ? L10n.management.managementauth.latestSnapshotSummary : L10n.management.managementauth.backupRestore)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)

                        if let summary = latestSummary {
                            Text("v\(summary.manifest.appVersion) (\(summary.manifest.appBuild)) • \(summary.activeRecordCount) bản ghi")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        } else {
                            Text(L10n.management.managementauth.createAMistiabackupFileToCaptureThe)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }

                    Spacer()
                }

                if let summary = latestSummary {
                    Divider()

                    HStack {
                        Label("Sẵn sàng khôi phục", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.green)

                        Spacer()

                        Button {
                            showSummaryDetailSheet = true
                        } label: {
                            Text("Chi tiết")
                                .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                                .foregroundStyle(accent)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
        }
        .sheet(isPresented: $showSummaryDetailSheet) {
            if let summary = latestSummary {
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(L10n.management.managementauth.backupFormatVValueAppValueValue(String(describing: summary.manifest.backupFormatVersion), String(describing: summary.manifest.appVersion), String(describing: summary.manifest.appBuild), String(describing: summary.manifest.localSchemaVersion)))
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)

                            Text(summary.localizedBreakdown)
                                .font(.system(size: 14, weight: .regular, design: .rounded))
                                .foregroundStyle(.primary)
                        }
                        .padding(20)
                    }
                    .navigationTitle(L10n.management.managementauth.latestSnapshotSummary)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(L10n.common.ok) {
                                showSummaryDetailSheet = false
                            }
                        }
                    }
                }
                .presentationDetents([.medium])
            }
        }
    }
```

- [ ] **Step 3: Verify build with swift build or Xcode scheme**

Run swift build or check compilation:
```bash
swift build
```
Expected output: Build succeeds with 0 errors.

- [ ] **Step 4: Commit (if auto_commit enabled)**

Check `.agent/config.yml` for `auto_commit`. Since `auto_commit: false`, skip git commit and print message.
