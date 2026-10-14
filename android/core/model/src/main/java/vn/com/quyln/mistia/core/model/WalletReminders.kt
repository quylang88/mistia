package vn.com.quyln.mistia.core.model

import java.time.Instant
import java.time.LocalTime
import java.time.ZoneId
import java.util.UUID

/** Future inbox records and native schedule targets from the same owned balance snapshot. */
data class WalletReminderPlan(val inbox:List<AppNotificationRecord>,val scheduled:List<AppNotificationRecord>)
data class WalletReminderText(val title:String,val body:String)
fun planWalletReminders(owner:UserId,wallets:List<LedgerWalletRecord>,transactions:List<LedgerTransactionRecord>,existing:List<AppNotificationRecord>,
    reference:Instant,zone:ZoneId,enabled:Boolean,archivedSharedExpenseEventIds:Set<String> = emptySet(),text:(LedgerWalletRecord,Long)->WalletReminderText):WalletReminderPlan {
    UUID.fromString(owner.value)
    existing.forEach {it.requireValidLocalNotification();require(it.ownerUserId==owner.value)}
    require(existing.map {it.key}.distinct().size==existing.size)
    val history=existing.filterNot {it.kind=="dueSoon" || it.key.startsWith("mistia.reminder.due.")}
    if(!enabled) return WalletReminderPlan(history,emptyList())
    val active=wallets.filter {it.ownerUserId==owner.value && it.deletedAt==null && !it.isArchived}
    val activeIds=active.map {it.id}.toSet()
    fun walletId(row:AppNotificationRecord):String? = row.resourceId ?: row.key.takeIf {it.startsWith("mistia.reminder.wallet.")}
        ?.removePrefix("mistia.reminder.wallet.")?.let {runCatching {UUID.fromString(it).toString()}.getOrNull()}
    val retained=history.filterNot {row -> row.kind=="lowWallet" && walletId(row)?.let {it !in activeIds}==true}.associateBy {it.key}.toMutableMap()
    val balance=TransactionWalletBalanceIndex(active,transactions.filter {record ->
        record.ownerUserId==owner.value && !(record.settlementGroupId in archivedSharedExpenseEventIds &&
            record.primaryKind==TransactionPrimaryKind.TRANSFER && record.transferSubtype==TransactionTransferSubtype.DEBT &&
            record.settlementRoleWireValue in setOf("sharedExpenseReceivable","sharedExpensePayable","sharedExpenseReceipt","sharedExpensePayment"))
    })
    val localDate=reference.atZone(zone).toLocalDate()
    val todayMorning=localDate.atTime(LocalTime.of(9,0)).atZone(zone).toInstant()
    val morning=if(todayMorning>reference) todayMorning else localDate.plusDays(1).atTime(LocalTime.of(9,0)).atZone(zone).toInstant()
    val scheduled=active.filter {it.kind==WalletKind.CASH && balance.balance(it.id)<=0}.map {wallet ->
        val copy=text(wallet,balance.balance(wallet.id))
        val incoming=AppNotificationRecord(owner.value,"mistia.reminder.wallet.${wallet.id.lowercase()}",copy.title,copy.body,"lowWallet",
            source="localReminder",resourceType="wallet",resourceId=wallet.id,createdAt=morning.toString(),updatedAt=reference.toString())
        val old=retained[incoming.key]
        incoming.copy(isRead=old?.isRead ?: false,readAt=old?.readAt,actionState=old?.actionState ?: incoming.actionState)
            .also {it.requireValidLocalNotification();retained[it.key]=it}
    }
    return WalletReminderPlan(retained.values.sortedBy {it.key},scheduled.sortedBy {it.key})
}

data class WalletReminderSnapshot(val owner:UserId,val records:Map<CloudEntity,List<CloudRecord>>,val notifications:List<AppNotificationRecord>) {
    fun requireUnchanged(other:WalletReminderSnapshot) {
        require(owner==other.owner && records.keys==other.records.keys)
        require(records.all {(entity,rows) -> rows.sortedBy {it.id}==other.records.getValue(entity).sortedBy {it.id}})
        require(notifications.associateBy {it.key}==other.notifications.associateBy {it.key})
    }
    fun plan(reference:Instant,zone:ZoneId,enabled:Boolean,text:(LedgerWalletRecord,Long)->WalletReminderText):WalletReminderPlan {
        if(!enabled) return planWalletReminders(owner,emptyList(),emptyList(),notifications,reference,zone,false,text=text)
        fun owned(entity:CloudEntity)=records.getValue(entity).filter {row ->
            require(row.ownerUserId==owner.value && row.entity==entity.table)
            require((row.payload["id"] as? kotlinx.serialization.json.JsonPrimitive)?.content==row.id)
            row.deletedAt==null && (row.payload["user_id"] as? kotlinx.serialization.json.JsonPrimitive)?.content==owner.value
        }
        val wallets=owned(CloudEntity.LEDGER_WALLET).map(LedgerWalletRecord::fromCloudRecord)
        val transactions=owned(CloudEntity.LEDGER_TRANSACTION).map(LedgerTransactionRecord::fromCloudRecord)
        val archivedEvents=owned(CloudEntity.SETTLEMENT_GROUP).filter {row ->
            (row.payload["kind_raw_value"] as? kotlinx.serialization.json.JsonPrimitive)?.content=="sharedExpense" &&
                (row.payload["is_archived"] as? kotlinx.serialization.json.JsonPrimitive)?.content=="true" &&
                (row.payload["deleted_at"]==null || row.payload["deleted_at"]==kotlinx.serialization.json.JsonNull)
        }.map {it.id}.toSet()
        return planWalletReminders(owner,wallets,transactions,notifications,reference,zone,true,archivedEvents,text)
    }
    companion object {val entities=setOf(CloudEntity.LEDGER_WALLET,CloudEntity.LEDGER_TRANSACTION,CloudEntity.SETTLEMENT_GROUP)}
}
interface WalletReminderRepository {
    suspend fun maintainWalletReminders(owner:UserId,now:String):Result<WalletReminderPlan>
}
