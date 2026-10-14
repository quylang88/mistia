package vn.com.quyln.mistia.core.model

import java.time.Instant
import kotlinx.coroutines.flow.Flow

enum class NotificationGroupId { ACTION_REQUESTS,ACCESS,FAMILY_CASHFLOW,FAMILY_DATA,BILLS,CREDIT_CARDS,WALLETS,BUDGETS }
data class NotificationGroup(val id:NotificationGroupId,val rows:List<AppNotificationRecord>,val unreadCount:Int) {
    val latest:AppNotificationRecord get()=rows.last()
}
fun notificationGroups(owner:UserId,rows:List<AppNotificationRecord>,reference:Instant):List<NotificationGroup> {
    fun group(row:AppNotificationRecord):NotificationGroupId? = when(row.kind) {
        "permissionRequestReceived" -> if(row.actionState=="pending") NotificationGroupId.ACTION_REQUESTS else NotificationGroupId.ACCESS
        "familyTransactionRequestReceived" -> if(row.actionState=="pending") NotificationGroupId.ACTION_REQUESTS else NotificationGroupId.FAMILY_CASHFLOW
        "permissionRequestApproved","permissionRequestRejected","permissionRevoked","permissionPolicyChanged","accessIssue" -> NotificationGroupId.ACCESS
        "familyTransactionRequestApproved","familyTransactionRequestRejected" -> NotificationGroupId.FAMILY_CASHFLOW
        "familyActivity" -> if(row.resourceType in setOf("transaction","family_transfer","debt")) NotificationGroupId.FAMILY_CASHFLOW else NotificationGroupId.FAMILY_DATA
        "familyPlaceholder" -> NotificationGroupId.FAMILY_DATA
        "billPaymentRequired","billAutoPaymentSucceeded","billAutoPaymentFailed","billOverdue" -> NotificationGroupId.BILLS
        "creditCardStatementReady","creditCardAutoPaymentSucceeded","creditCardAutoPaymentFailed" -> NotificationGroupId.CREDIT_CARDS
        "lowWallet" -> NotificationGroupId.WALLETS
        "budgetWarning" -> NotificationGroupId.BUDGETS
        else -> null
    }
    return rows.filter {it.ownerUserId==owner.value && !(it.source in setOf("system","localReminder") && Instant.parse(it.createdAt)>reference)}
        .mapNotNull {row -> group(row)?.let {it to row}}.groupBy({it.first},{it.second}).map {(id,items) ->
            NotificationGroup(id,items.sortedWith(compareBy({Instant.parse(it.createdAt)},{it.key})),items.count {!it.isRead})
        }.sortedWith(compareByDescending<NotificationGroup> {Instant.parse(it.latest.createdAt)}.thenBy {it.latest.key})
}
interface AppNotificationRepository {
    fun observeAppNotifications(owner:UserId):Flow<List<AppNotificationRecord>>
    /** Null keys means the visible snapshot at invocation; new/replaced arrivals stay unread. */
    suspend fun markNotificationsRead(owner:UserId,keys:Set<String>?,now:String):Result<Unit>
}
