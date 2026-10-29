package vn.com.quyln.mistia.core.database

import java.time.ZoneId
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import vn.com.quyln.mistia.core.model.*

internal class OfflineCreditCardStatementPaymentRepository(private val store:LocalStore,private val zone:()->ZoneId):CreditCardStatementPaymentRepository {
    override suspend fun payCreditCardStatement(owner:UserId,request:CreditCardStatementPaymentRequest,deviceId:String,now:String):Result<SavedCreditCardStatementPayment> = try {
        currentCoroutineContext().ensureActive()
        val capturedZone=zone()
        val source=store.creditCardStatementPaymentSnapshot(owner)
        require(source.owner==owner)
        planCreditCardStatementPayment(source,request,deviceId,now,capturedZone)
        currentCoroutineContext().ensureActive()
        Result.success(store.commitCreditCardStatementPayment(source,request,deviceId,now,capturedZone).payment)
    }catch(cancelled:CancellationException){throw cancelled}catch(error:Exception){Result.failure(error)}
}
