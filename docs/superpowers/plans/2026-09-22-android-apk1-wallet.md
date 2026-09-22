# Android APK 1 Wallet Slice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add complete offline create/edit/archive behavior for non-credit wallets, with account-scoped atomic Room outbox persistence and an iOS-parity Compose list/editor.

**Architecture:** `FinanceRepository` exposes typed wallet records to Compose and owns draft validation/JSON encoding. `RoomLocalStore` remains the source of truth and writes the wallet row plus coalesced outbox row in one Room transaction; no cloud push is added or enabled in this plan. Credit-card/profile behavior, wallet push, categories, transactions/FX and receipts each get a separate follow-up plan and commit series.

**Tech Stack:** Kotlin 2.2.21, Jetpack Compose Material 3, Room 2.8.5, kotlinx.serialization JSON, JUnit 4, AndroidX instrumented tests.

**Spec:** `docs/android/SESSION-HANDOFF-2026-09-22.md`, `docs/android/ios-parity-baseline.md`, `contracts/schema/cloud-entities.json`, and the original requirements at `/Users/quyln/.codex/attachments/1b6bfcfe-49b2-4465-bafe-41003c98d45a/pasted-text.txt`.

## Global Constraints

- Android remains native Kotlin/Compose; no KMP and no iOS runtime changes for Android.
- Money is signed `Long` minor units; currency codes are uppercase ISO-4217-shaped strings.
- Cleared optional wallet fields are explicit JSON `null`; UUIDs are lowercase canonical strings and timestamps are UTC ISO-8601.
- Wallet record and outbox writes are atomic and isolated by signed-in `owner_user_id`.
- `Mistia/Localizable.xcstrings` is the only source of static UI copy; generated resources are never edited manually.
- Cloud wallet push remains disabled until its separate serializer/retry/conflict and Samsung gate passes.
- Tasks 1–3 are internal RED/GREEN checkpoints of one vertical slice; the slice ends with tests, diff/parity review, evidence/progress update, `git diff --check`, and one commit after Task 3.

## Review Focus

- Account A wallet rows and outbox entries must never be observed through account B.
- Clearing a bank name must encode both institution keys as JSON `null`, not omit them or write empty strings.
- Editing preserves `id`, `created_at`, and base `sync_version`; it changes `updated_at` and coalesces the outbox row.
- `creditCard` and `investment` kinds are not writable through this slice; they remain visible but route to later dedicated flows.
- Archive is a local `is_archived=true` upsert matching iOS, not a hard delete or `deleted_at` tombstone.

---

### Task 1: Typed wallet contract and validation

**Files:**
- Create: `android/core/model/src/main/java/vn/com/quyln/mistia/core/model/WalletModels.kt`
- Create: `android/core/model/src/test/java/vn/com/quyln/mistia/core/model/WalletModelsTest.kt`

**Interfaces:**
- Consumes: existing `CloudRecord`, `PendingMutation`, `CloudEntity.LEDGER_WALLET`, `UserId`.
- Produces: `WalletKind`, `LedgerWalletRecord`, `WalletDraft`, `WalletValidationException`, and `WalletDraft.toMutation(...)`.

- [x] **Step 1: Write the failing model tests**

```kotlin
class WalletModelsTest {
    @Test fun `bank without institution is rejected`() {
        val error = assertFailsWith<WalletValidationException> {
            WalletDraft(name = "", kind = WalletKind.BANK, currencyCode = "jpy")
                .toMutation(UserId(OWNER), null, DEVICE, NOW)
        }
        assertEquals(WalletValidationError.BANK_INSTITUTION_REQUIRED, error.reason)
    }

    @Test fun `clearing bank details emits explicit nulls`() {
        val existing = walletRecord(kind = WalletKind.BANK, institutionDisplayName = "MUFG")
        val mutation = WalletDraft(
            name = "Cash",
            kind = WalletKind.CASH,
            currencyCode = "jpy",
            openingBalanceMinor = 9007199254740993L,
        ).toMutation(UserId(OWNER), existing, DEVICE, NOW)

        assertEquals(JsonNull, mutation.record.payload["institution_display_name"])
        assertEquals(JsonNull, mutation.record.payload["institution_preset_key"])
        assertEquals("JPY", mutation.record.payload["currency_code"]?.jsonPrimitive?.content)
        assertEquals(9007199254740993L, mutation.record.payload["opening_balance_minor"]?.jsonPrimitive?.long)
    }

    @Test fun `editing preserves identity creation and base version`() {
        val existing = walletRecord(id = "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", syncVersion = 7)
        val mutation = WalletDraft(name = "Travel", kind = WalletKind.CASH, currencyCode = "JPY")
            .toMutation(UserId(OWNER), existing, DEVICE, NOW)

        assertEquals("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", mutation.record.id)
        assertEquals("2026-01-01T00:00:00.000Z", mutation.record.payload["created_at"]?.jsonPrimitive?.content)
        assertEquals(7, mutation.pending.baseVersion)
        assertEquals(NOW, mutation.pending.modifiedAt)
    }

    @Test fun `credit card and investment require dedicated flows`() {
        listOf(WalletKind.CREDIT_CARD, WalletKind.INVESTMENT).forEach { kind ->
            val error = assertFailsWith<WalletValidationException> {
                WalletDraft(name = "Blocked", kind = kind, currencyCode = "JPY")
                    .toMutation(UserId(OWNER), null, DEVICE, NOW)
            }
            assertEquals(WalletValidationError.DEDICATED_FLOW_REQUIRED, error.reason)
        }
    }
}
```

- [x] **Step 2: Run the test and verify RED**

  Run: `cd android && JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home ./gradlew :core:model:testDebugUnitTest --tests '*WalletModelsTest'`

  Expected: Kotlin compilation fails because `WalletDraft`, `WalletKind`, and `WalletValidationException` do not exist.

- [x] **Step 3: Implement the typed contract**

```kotlin
enum class WalletKind(val wireValue: String, val defaultIcon: String, val defaultColorHex: String) {
    CASH("cash", "mistia.wallet.cash", "#2DAA9E"),
    PAY_PAY("payPay", "mistia.wallet.paypay", "#F26A5A"),
    BANK("bank", "mistia.wallet.bank", "#5B7BFF"),
    CREDIT_CARD("creditCard", "mistia.wallet.credit_card", "#7C85A3"),
    E_WALLET("eWallet", "mistia.wallet.e_wallet", "#F26A5A"),
    PREPAID("prepaid", "mistia.wallet.prepaid", "#FFB347"),
    INVESTMENT("investment", "mistia.wallet.investment", "#9A67FF"),
    CRYPTO("crypto", "mistia.wallet.crypto", "#F59B3F"),
    OTHER("other", "mistia.wallet.other", "#8A8A8E"),
}

data class WalletMutation(
    val record: CloudRecord,
    val pending: PendingMutation,
)

```

  `toMutation` normalizes UUID/currency, trims user text, chooses the iOS default name/icon/color, carries the existing creation timestamp and base version, encodes every contract field, and emits explicit `JsonNull` for cleared optionals.

- [x] **Step 4: Run the focused model test and full model suite**

  Run: `cd android && JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home ./gradlew :core:model:testDebugUnitTest`

  Expected: every core-model test passes with zero failures.

### Task 2: Atomic Room wallet and outbox persistence

**Files:**
- Create: `android/core/database/src/test/java/vn/com/quyln/mistia/core/database/WalletRepositoryTest.kt`
- Create: `android/core/database/src/androidTest/java/vn/com/quyln/mistia/core/database/WalletRoomTest.kt`
- Modify: `android/core/database/src/main/java/vn/com/quyln/mistia/core/database/MistiaDatabase.kt`
- Modify: `android/core/database/src/main/java/vn/com/quyln/mistia/core/database/Repositories.kt`
- Modify: `android/core/model/src/main/java/vn/com/quyln/mistia/core/model/Contracts.kt`
- Modify: `android/gradle/libs.versions.toml`
- Modify: `android/core/database/build.gradle.kts`

**Interfaces:**
- Consumes: Task 1 `WalletMutation` and typed `FinanceRepository` signatures.
- Produces: typed `FinanceRepository` methods, `LocalStore.record(...)`, `LocalStore.commitMutation(...)`, transactional DAO write, and repository implementations.

- [x] **Step 1: Write the failing Room tests**

```kotlin
class WalletRepositoryTest {
    @Test fun `save writes owner scoped record and outbox together`() = runTest {
        val repository = repository(inMemoryDatabase())
        repository.saveWallet(UserId(OWNER_A), cashDraft("Tokyo cash"), DEVICE, NOW).getOrThrow()

        assertEquals(listOf("Tokyo cash"), repository.observeWallets(UserId(OWNER_A)).first().map { it.name })
        assertTrue(repository.observeWallets(UserId(OWNER_B)).first().isEmpty())
        assertEquals(listOf(WALLET_ID), database.syncOutboxDao().recordIds(OWNER_A, "ledger_wallets"))
        assertTrue(database.syncOutboxDao().recordIds(OWNER_B, "ledger_wallets").isEmpty())
    }

    @Test fun `editing coalesces one outbox row and keeps base version`() = runTest {
        seedRemoteWallet(syncVersion = 4)
        repository.saveWallet(UserId(OWNER_A), editDraft(WALLET_ID, "Renamed"), DEVICE, NOW).getOrThrow()
        repository.saveWallet(UserId(OWNER_A), editDraft(WALLET_ID, "Final"), DEVICE, LATER).getOrThrow()

        val outbox = database.syncOutboxDao().rows(OWNER_A)
        assertEquals(1, outbox.size)
        assertEquals(4, outbox.single().baseVersion)
        assertEquals("Final", repository.observeWallets(UserId(OWNER_A)).first().single().name)
    }

    @Test fun `archive is an upsert and disappears from active wallet flow`() = runTest {
        val saved = repository.saveWallet(UserId(OWNER_A), cashDraft("Cash"), DEVICE, NOW).getOrThrow()
        repository.archiveWallet(UserId(OWNER_A), RecordId(saved.id), DEVICE, LATER).getOrThrow()

        assertTrue(repository.observeWallets(UserId(OWNER_A)).first().isEmpty())
        assertEquals("upsert", database.syncOutboxDao().rows(OWNER_A).single().kind)
    }
}
```

  The unit test uses a real-behavior in-memory `LocalStore` fake that persists records/outbox by owner. Add an AndroidX `WalletRoomTest` with `Room.inMemoryDatabaseBuilder`, `AndroidJUnit4`, and the same account/coalescing/archive assertions against the generated DAO; compile it now and run it on Samsung when ADB returns.

- [x] **Step 2: Run the database test and verify RED**

  Run: `cd android && JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home ./gradlew :core:database:testDebugUnitTest --tests '*WalletRepositoryTest'`

  Expected: compilation fails because local record lookup, outbox rows, and atomic mutation APIs do not exist.

- [x] **Step 3: Implement the transactional storage boundary**

```kotlin
@Dao
interface WalletMutationDao {
    @Transaction
    suspend fun commit(record: CloudRecordEntity, outbox: SyncOutboxEntity) {
        upsertRecord(record)
        upsertOutbox(outbox)
    }
}

interface LocalStore {
    fun observe(entity: String, ownerUserId: UserId): Flow<List<CloudRecord>>
    suspend fun record(ownerUserId: UserId, entity: String, recordId: String): CloudRecord?
    suspend fun commitMutation(record: CloudRecord, mutation: PendingMutation)
    // Existing pull/count/account methods remain unchanged.
}

interface FinanceRepository {
    fun observe(entity: CloudEntity, ownerUserId: UserId): Flow<List<CloudRecord>>
    fun observeWallets(ownerUserId: UserId): Flow<List<LedgerWalletRecord>>
    fun observeEntityCounts(ownerUserId: UserId): Flow<List<EntityCount>>
    suspend fun saveWallet(ownerUserId: UserId, draft: WalletDraft, deviceId: String, now: String): Result<LedgerWalletRecord>
    suspend fun archiveWallet(ownerUserId: UserId, walletId: RecordId, deviceId: String, now: String): Result<Unit>
}
```

  `commitMutation` verifies identical owner/entity/id across both values, writes `has_pending_mutation=true`, and coalesces by the existing outbox primary key. `OfflineFirstFinanceRepository` maps active non-archived rows to `LedgerWalletRecord`, looks up an existing row before encoding an edit, and delegates exactly one `commitMutation` call.

- [x] **Step 4: Run the focused and full database suites**

  Run: `cd android && JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home ./gradlew :core:database:testDebugUnitTest :core:database:compileDebugAndroidTestKotlin :core:model:testDebugUnitTest`

  Expected: every model/database test passes with zero failures.

### Task 3: iOS-parity wallet list and editor

**Files:**
- Create: `android/feature/management/src/main/java/vn/com/quyln/mistia/feature/management/WalletEditor.kt`
- Create: `android/feature/management/src/test/java/vn/com/quyln/mistia/feature/management/WalletEditorStateTest.kt`
- Modify: `android/feature/management/src/main/java/vn/com/quyln/mistia/feature/management/ManagementScreen.kt`
- Modify: `android/feature/management/build.gradle.kts`
- Modify: `android/app/src/main/java/vn/com/quyln/mistia/MainActivity.kt`
- Modify: `docs/android/android-parity-progress.md`
- Create: `docs/android/evidence/2026-09-22-apk1-wallet-offline.md`

**Interfaces:**
- Consumes: Task 2 typed repository methods and generated localization resources.
- Produces: `WalletEditorState`, `WalletEditorSheet`, grouped wallet rows/empty state, add/edit/archive actions, and slice evidence.

- [x] **Step 1: Write the failing editor-state tests**

```kotlin
class WalletEditorStateTest {
    @Test fun `selecting a kind applies its default icon until customized`() {
        val changed = WalletEditorState.new().selectKind(WalletKind.BANK)
        assertEquals("mistia.wallet.bank", changed.iconSymbolName)
        assertEquals("#5B7BFF", changed.iconColorHex)
    }

    @Test fun `custom icon survives later kind change`() {
        val changed = WalletEditorState.new()
            .customizeIcon("account_balance", "#123456")
            .selectKind(WalletKind.BANK)
        assertEquals("account_balance", changed.iconSymbolName)
        assertEquals("#123456", changed.iconColorHex)
    }

    @Test fun `bank save exposes localized validation reason`() {
        val result = WalletEditorState.new().selectKind(WalletKind.BANK).toDraft()
        assertEquals(WalletEditorValidation.BANK_INSTITUTION_REQUIRED, result.validation)
    }
}
```

- [x] **Step 2: Run the management test and verify RED**

  Run: `cd android && JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home ./gradlew :feature:management:testDebugUnitTest --tests '*WalletEditorStateTest'`

  Expected: compilation fails because `WalletEditorState` does not exist.

- [x] **Step 3: Implement the editor state and Compose UI**

  `ManagementScreen` observes `observeWallets(ownerUserId)` and renders iOS-like grouped background, 22dp cards, colored circular icons, wallet name/type/current opening balance, empty state and add footer. `WalletEditorSheet` provides name, supported kind, opening balance, currency and conditional bank fields; credit-card selection emits the dedicated-flow message and investment is not offered. Save/archive call repository methods through a coroutine scope and keep validation/errors on-screen. Static text references generated `R.string` keys already present in the shared catalog.

- [x] **Step 4: Run focused tests, full Android checks and parity checks**

  Run:

```bash
cd android
JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home ./gradlew testDebugUnitTest :app:lintDebug :app:assembleDebug
cd ..
swift Scripts/check-android-contracts.swift
swift Scripts/generate-android-l10n.swift --check
swift Scripts/generate-l10n.swift --input Mistia/Localizable.xcstrings --output Mistia/Shared/CoreLogic/L10n.generated.swift --strict-keys --check
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
git diff --check
```

  Expected: 0 test failures, 0 lint errors, APK assembled, 15 contract entities accepted, both localization checks unchanged, 597 Swift tests pass, and no whitespace errors.

- [x] **Step 5: Review diff and behavior against iOS**

  Compare the complete diff to `LedgerWallet`, `LedgerWalletKind`, `ManagementWalletEditorSheet`, and `walletsSection`. Verify field names/defaults, explicit nulls, archive semantics, account isolation, grouped hierarchy, spacing, purple palette, dark mode, icons, loading/empty/error/populated states. Fix every Critical/Important finding and rerun Step 4.

- [x] **Step 6: Update evidence and commit the vertical slice**

  Evidence records the commands/results, source commit, Samsung offline status, unverified cloud push, and the reused-scratch Swift root cause versus fresh-scratch pass. Update progress without promoting APK 1 or enabling wallet cloud writes.

```bash
git add android docs/android docs/superpowers/plans/2026-09-22-android-apk1-wallet.md
git commit -m "feat(android): add offline wallet management"
```
