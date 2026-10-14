package vn.com.quyln.mistia.core.sync

import kotlinx.coroutines.CancellationException
import vn.com.quyln.mistia.core.model.*

/** Inbox commits remain durable even if the independent OS scheduling step needs retry. */
class NativeScheduledWalletReminderRepository(private val local:WalletReminderRepository,private val native:NativeWalletReminderCoordinator):WalletReminderRepository {
    override suspend fun maintainWalletReminders(owner:UserId,now:String):Result<WalletReminderPlan> = try {
        val plan=local.maintainWalletReminders(owner,now).getOrThrow()
        native.reconcile(owner,plan)
        Result.success(plan)
    } catch(cancelled:CancellationException) {throw cancelled}
      catch(error:Exception) {Result.failure(error)}
}
