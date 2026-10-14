package vn.com.quyln.mistia.core.model

import java.time.Instant
import java.time.ZoneId
import org.junit.Assert.*
import org.junit.Test

class WalletRemindersTest {
    private val owner=UserId(OWNER)
    private val zone=ZoneId.of("Asia/Tokyo")
    private fun plan(wallets:List<LedgerWalletRecord> = listOf(wallet(SOURCE_WALLET_ID,WalletKind.CASH,0)),
        transactions:List<LedgerTransactionRecord> = emptyList(),existing:List<AppNotificationRecord> = emptyList(),
        reference:String="2026-10-14T00:00:00Z",enabled:Boolean=true,calendar:ZoneId=zone,archived:Set<String> = emptySet())=
        planWalletReminders(owner,wallets,transactions,existing,Instant.parse(reference),calendar,enabled,archived) {wallet,balance ->
            WalletReminderText("Low balance","${wallet.name}: $balance ${wallet.currencyCode}")
        }
    private fun row(id:String=SOURCE_WALLET_ID)=AppNotificationRecord(OWNER,"mistia.reminder.wallet.$id","Old","Body","lowWallet",
        source="localReminder",resourceType="wallet",resourceId=id,createdAt="2026-10-13T00:00:00Z",updatedAt="2026-10-13T00:00:00Z")
    @Test fun `only owned live unarchived cash wallets at or below zero are scheduled`() {
        val cash=wallet(SOURCE_WALLET_ID,WalletKind.CASH,0)
        val others=listOf(cash.copy(id=DESTINATION_WALLET_ID,openingBalanceMinor=1),cash.copy(id=PROFILE_ID,isArchived=true),
            cash.copy(id=TRANSACTION_ID,deletedAt=NOW),cash.copy(id=DEVICE,ownerUserId="99999999-9999-9999-9999-999999999999"),
            cash.copy(id="77777777-7777-7777-7777-777777777777",kindWireValue=WalletKind.BANK.wireValue))
        assertEquals(listOf(SOURCE_WALLET_ID),plan(listOf(cash)+others).scheduled.map {it.resourceId})
    }
    @Test fun `next morning is today before nine and tomorrow at or after nine`() {
        assertEquals("2026-10-14T00:00:00Z",plan(reference="2026-10-13T23:59:59Z").scheduled.single().createdAt)
        assertEquals("2026-10-15T00:00:00Z",plan().scheduled.single().createdAt)
        assertEquals("2026-10-15T00:00:00Z",plan(reference="2026-10-14T01:00:00Z").scheduled.single().createdAt)
    }
    @Test fun `morning uses local civil date across daylight saving changes`() {
        val ny=ZoneId.of("America/New_York")
        assertEquals("2026-03-08T13:00:00Z",plan(reference="2026-03-07T15:00:00Z",calendar=ny).scheduled.single().createdAt)
        assertEquals("2026-11-01T14:00:00Z",plan(reference="2026-10-31T14:00:00Z",calendar=ny).scheduled.single().createdAt)
    }
    @Test fun `balance remains exact above double integer precision and ignores foreign draft archived transactions`() {
        val cash=wallet(SOURCE_WALLET_ID,WalletKind.CASH,9007199254740993L)
        val expense=transaction(TRANSACTION_ID,TransactionPrimaryKind.EXPENSE,9007199254740994L)
        val ignored=listOf(expense.copy(id=PROFILE_ID,ownerUserId="99999999-9999-9999-9999-999999999999"),
            expense.copy(id=DEVICE,entryStatusWireValue="draft"),expense.copy(id=DESTINATION_WALLET_ID,isArchived=true))
        assertEquals("cash: -1 JPY",plan(listOf(cash),listOf(expense)+ignored).scheduled.single().body)
    }
    @Test fun `rescheduling updates morning and copy while preserving existing read history`() {
        val old=row().copy(isRead=true,readAt=NOW,actionState="resolved")
        val result=plan(existing=listOf(old)).inbox.single()
        assertEquals("2026-10-15T00:00:00Z",result.createdAt);assertEquals("Low balance",result.title)
        assertTrue(result.isRead);assertEquals(NOW,result.readAt);assertEquals("resolved",result.actionState)
        assertEquals(listOf(result),plan(existing=listOf(old)).scheduled)
        assertTrue(notificationGroups(owner,listOf(result),Instant.parse("2026-10-14T23:59:00Z")).isEmpty())
    }
    @Test fun `stale wallet and obsolete due soon records are removed while unrelated history survives`() {
        val missing=row(DESTINATION_WALLET_ID)
        val other=row().copy(key="bill",kind="billAutoPaymentSucceeded",resourceType="bill")
        val obsolete=row().copy(key="mistia.reminder.due.legacy",kind="dueSoon")
        val result=plan(existing=listOf(row(),missing,other,obsolete)).inbox
        assertEquals(setOf(row().key,other.key),result.map {it.key}.toSet())
    }
    @Test fun `disabled wallet reminders preserve wallet history but remove obsolete due soon rows`() {
        val old=row();val obsolete=old.copy(key="obsolete",kind="dueSoon")
        val result=plan(wallets=emptyList(),existing=listOf(old,obsolete),enabled=false)
        assertEquals(listOf(old),result.inbox);assertTrue(result.scheduled.isEmpty())
    }
    @Test fun `archived shared expense debt effects are excluded while other event records remain`() {
        val cash=wallet(SOURCE_WALLET_ID,WalletKind.CASH,100)
        val debt=transaction(TRANSACTION_ID,TransactionPrimaryKind.TRANSFER,100).copy(transferSubtypeWireValue="debt",debtIntentWireValue="repay",
            settlementGroupId=PROFILE_ID,settlementRoleWireValue="sharedExpensePayment")
        assertEquals(1,plan(listOf(cash),listOf(debt)).scheduled.size)
        assertTrue(plan(listOf(cash),listOf(debt),archived=setOf(PROFILE_ID)).scheduled.isEmpty())
        assertEquals(1,plan(listOf(cash),listOf(debt.copy(settlementRoleWireValue="sharedExpensePaid")),archived=setOf(PROFILE_ID)).scheduled.size)
    }
    @Test fun `recovered positive balance keeps inbox history but no native schedule`() {
        val old=row();val result=plan(listOf(wallet(SOURCE_WALLET_ID,WalletKind.CASH,1)),existing=listOf(old))
        assertEquals(listOf(old),result.inbox);assertTrue(result.scheduled.isEmpty())
    }
    private fun wallet(id: String, kind: WalletKind, openingBalanceMinor: Long) = LedgerWalletRecord(
        id = id,
        ownerUserId = OWNER,
        name = kind.wireValue,
        kindWireValue = kind.wireValue,
        iconSymbolName = kind.defaultIcon,
        iconColorHex = kind.defaultColorHex,
        currencyCode = "JPY",
        openingBalanceMinor = openingBalanceMinor,
        institutionDisplayName = null,
        institutionPresetKey = null,
        sortOrder = 0,
        isArchived = false,
        archivedAt = null,
        createdAt = NOW,
        updatedAt = NOW,
        deletedAt = null,
        syncVersion = 0,
        lastModifiedByDeviceId = DEVICE,
        systemPurposeRawValue = null,
        investmentLinkedWalletId = null,
    )

    private fun transaction(
        id: String,
        kind: TransactionPrimaryKind,
        amount: Long,
        sourceWalletId: String = SOURCE_WALLET_ID,
        destinationWalletId: String? = null,
        destinationAmount: Long? = null,
    ) = LedgerTransactionRecord(
        id = id,
        ownerUserId = OWNER,
        primaryKindWireValue = kind.wireValue,
        transferSubtypeWireValue = if (kind == TransactionPrimaryKind.TRANSFER) {
            TransactionTransferSubtype.INTERNAL_TRANSFER.wireValue
        } else null,
        debtIntentWireValue = null,
        entryStatusWireValue = TransactionEntryStatus.POSTED.wireValue,
        title = "Record",
        note = null,
        amountMinor = amount,
        sourceCurrencyCode = "JPY",
        destinationCurrencyCode = destinationWalletId?.let { "JPY" },
        destinationAmountMinor = destinationAmount,
        reportingCurrencyCode = null,
        reportingAmountMinor = null,
        conversionModeWireValue = null,
        exchangeRateDecimalString = null,
        exchangeRateProvider = null,
        exchangeRateDate = null,
        occurredAt = if (id == TRANSACTION_ID) "2030-01-01T00:00:00Z" else "2020-01-01T00:00:00Z",
        createdAt = NOW,
        updatedAt = NOW,
        createdByUserId = OWNER,
        lastModifiedByUserId = OWNER,
        counterpartyName = null,
        normalizedCounterpartyKey = null,
        settlementGroupId = null,
        settlementObligationId = null,
        settlementRoleWireValue = null,
        reportingExpenseMinor = null,
        reportingIncomeMinor = null,
        sourceWalletId = sourceWalletId,
        destinationWalletId = destinationWalletId,
        categoryId = null,
        deletedAt = null,
        isArchived = false,
        archivedAt = null,
        syncVersion = 0,
        lastModifiedByDeviceId = DEVICE,
    )

    private fun debtLend(id: String, amount: Long) =
        transaction(id, TransactionPrimaryKind.TRANSFER, amount).copy(
            transferSubtypeWireValue = TransactionTransferSubtype.DEBT.wireValue,
            debtIntentWireValue = TransactionDebtIntent.LEND.wireValue,
            destinationWalletId = null,
            destinationCurrencyCode = null,
        )

    private companion object {
        const val OWNER = "11111111-1111-1111-1111-111111111111"
        const val TRANSACTION_ID = "22222222-2222-2222-2222-222222222222"
        const val SOURCE_WALLET_ID = "33333333-3333-3333-3333-333333333333"
        const val DESTINATION_WALLET_ID = "44444444-4444-4444-4444-444444444444"
        const val PROFILE_ID = "55555555-5555-5555-5555-555555555555"
        const val DEVICE = "66666666-6666-6666-6666-666666666666"
        const val NOW = "2026-09-23T12:00:00Z"
    }
}
