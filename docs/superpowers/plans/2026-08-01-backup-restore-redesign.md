# Backup & Restore Screen Redesign V2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor `ManagementBackupRestoreView` in `Mistia/Features/Management/ManagementAuthView.swift` to match Ultra-Minimalist Apple iOS 26 HIG.

**Architecture:**
- Remove emergency message card.
- Simplify `heroStatusCard` to show concise timestamp status and a small detail pill button.
- Remove redundant subtitles on action rows ("Tạo bản sao lưu ngay", "Khôi phục từ tệp...").
- Clean up restore mode options card to contain a single clean row with a menu picker, placing the restore mode description as a standard section footer outside the card.

**Tech Stack:** SwiftUI, SwiftData, Swift Package Manager.

---

### Task 1: Refactor ManagementBackupRestoreView to Ultra-Minimalist V2

**Files:**
- Modify: `Mistia/Features/Management/ManagementAuthView.swift:4821-5040`

- [ ] **Step 1: Update ManagementBackupRestoreView layout and remove subtitles/emergency card**

Modify `ManagementBackupRestoreView` in `Mistia/Features/Management/ManagementAuthView.swift`:

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
                        subtitle: nil,
                        systemImage: "square.and.arrow.up.fill",
                        tint: .blue,
                        isDisabled: isBusy,
                        action: exportSnapshot
                    )

                    ManagementProfileRowDivider()

                    backupActionRow(
                        title: L10n.management.managementauth.importSnapshot,
                        subtitle: nil,
                        systemImage: "square.and.arrow.down.fill",
                        tint: .mint,
                        isDisabled: isBusy,
                        action: { isImporting = true }
                    )
                }
            }

            // Restore Mode Section Header & Card
            VStack(alignment: .leading, spacing: 8) {
                ManagementProfileListCard(tint: cardTint) {
                    HStack {
                        Text(L10n.management.managementauth.restoreMode)
                            .font(.system(size: 15.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.primary)

                        Spacer()

                        Picker(String(), selection: $restoreMode) {
                            ForEach(MistiaBackupRestoreMode.allCases) { mode in
                                Text(mode.localizedTitle).tag(mode)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(accent)
                        .labelsHidden()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }

                // Section Footer Outside Card
                Text(restoreMode.localizedDescription)
                    .font(.system(size: 12.5, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
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

- [ ] **Step 2: Update heroStatusCard & backupActionRow**

Update `heroStatusCard` and optional subtitle support in `backupActionRow`:

```swift
    private var heroStatusCard: some View {
        ManagementProfileListCard(tint: cardTint) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(latestSummary != nil ? Color.blue.opacity(0.12) : Color.gray.opacity(0.12))
                        .frame(width: 52, height: 52)

                    Image(systemName: latestSummary != nil ? "icloud.circle.fill" : "icloud.slash")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(latestSummary != nil ? Color.blue : Color.secondary)
                }

                VStack(spacing: 4) {
                    Text(L10n.management.managementauth.backupRestore)
                        .font(.system(size: 16.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)

                    if let summary = latestSummary {
                        Text("v\(summary.manifest.appVersion) (\(summary.manifest.appBuild))")
                            .font(.system(size: 13, weight: .regular, design: .rounded))
                            .foregroundStyle(.secondary)

                        Button {
                            showSummaryDetailSheet = true
                        } label: {
                            HStack(spacing: 4) {
                                Text("\(summary.activeRecordCount) bản ghi")
                                Image(systemName: "info.circle")
                            }
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(accent)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(accent.opacity(0.1))
                            .clipShape(Capsule())
                        }
                        .padding(.top, 4)
                    } else {
                        Text("Chưa có bản sao lưu nào trên thiết bị")
                            .font(.system(size: 13, weight: .regular, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .padding(.horizontal, 16)
        }
    }

    private func backupActionRow(
        title: String,
        subtitle: String?,
        systemImage: String,
        tint: Color,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.primary)

                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 12.5, weight: .regular, design: .rounded))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                }

                Spacer()

                if isDisabled {
                    ProgressView()
                        .progressViewStyle(.circular)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
```

- [ ] **Step 3: Verify build with swift build**

Run swift build with bypass sandbox:
```bash
swift build
```

- [ ] **Step 4: Check auto_commit setting**
If `auto_commit: false`, skip git commit.
