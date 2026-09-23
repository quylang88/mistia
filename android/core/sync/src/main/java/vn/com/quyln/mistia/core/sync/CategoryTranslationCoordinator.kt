package vn.com.quyln.mistia.core.sync

import java.io.IOException
import java.time.Instant
import kotlin.math.min
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import vn.com.quyln.mistia.core.model.CategoryNameTranslations
import vn.com.quyln.mistia.core.model.CategoryNameTranslator
import vn.com.quyln.mistia.core.model.CloudEntity
import vn.com.quyln.mistia.core.model.LocalStore
import vn.com.quyln.mistia.core.model.MutationKind
import vn.com.quyln.mistia.core.model.PendingMutation
import vn.com.quyln.mistia.core.model.QueuedCategoryTranslation
import vn.com.quyln.mistia.core.model.TransactionCategoryRecord
import vn.com.quyln.mistia.core.model.UserId
import vn.com.quyln.mistia.core.network.SupabaseHttpException

data class CategoryTranslationSummary(
    val translated: Int = 0,
    val staleResponses: Int = 0,
    val retryableFailures: Int = 0,
)

class CategoryTranslationCoordinator(
    private val localStore: LocalStore,
    private val translator: CategoryNameTranslator,
    private val deviceIdProvider: () -> String = { "" },
    private val nowEpochMillis: () -> Long = System::currentTimeMillis,
    private val nowIsoString: () -> String = { Instant.now().toString() },
) {
    private val mutex = Mutex()

    suspend fun translatePending(
        ownerUserId: UserId,
        accessToken: String,
    ): CategoryTranslationSummary = mutex.withLock {
        val now = nowEpochMillis()
        var summary = CategoryTranslationSummary()
        deviceIdProvider().takeIf(String::isNotBlank)?.let { deviceId ->
            localStore.enqueueMissingCategoryTranslations(ownerUserId, deviceId)
        }
        val tasks = localStore.pendingCategoryTranslations(ownerUserId, now)
        for (task in tasks) {
            summary = try {
                when (translateOne(task, ownerUserId, accessToken)) {
                    TranslationOutcome.TRANSLATED -> summary.copy(translated = summary.translated + 1)
                    TranslationOutcome.STALE -> summary.copy(staleResponses = summary.staleResponses + 1)
                }
            } catch (error: Exception) {
                if (error is CancellationException) throw error
                // iOS deliberately leaves every failed translation pending so a later
                // maintenance pass can recover from refreshed auth/configuration as well
                // as transient transport and service failures.
                val retryAt = now + retryDelayMillis(task.attemptCount)
                val recorded = localStore.recordCategoryTranslationFailure(task, retryAt, error.safeCode())
                if (!recorded) summary.copy(staleResponses = summary.staleResponses + 1)
                else summary.copy(retryableFailures = summary.retryableFailures + 1)
            }
        }
        return summary
    }

    private suspend fun translateOne(
        task: QueuedCategoryTranslation,
        ownerUserId: UserId,
        accessToken: String,
    ): TranslationOutcome {
        val pending = task.translation
        require(pending.ownerUserId == ownerUserId.value) { "Translation owner does not match session" }
        val local = localStore.record(
            ownerUserId,
            CloudEntity.TRANSACTION_CATEGORY.table,
            pending.categoryId,
        )
        if (local == null || local.updatedAt != pending.savedUpdatedAt) {
            localStore.discardCategoryTranslation(task)
            return TranslationOutcome.STALE
        }

        val category = TransactionCategoryRecord.fromCloudRecord(local)
        val fallback = CategoryNameTranslations(
            category.name,
            category.nameEnglish,
            category.nameJapanese,
        )
        val translated = translator.translate(
            pending.inputName,
            pending.sourceLanguage,
            accessToken,
        ).mergedWithFallback(fallback)
        if (translated == fallback) throw NoTranslationChangeException()

        val updatedAt = nowIsoString()
        val translatedRecord = category.copy(
            name = translated.name,
            nameEnglish = translated.nameEnglish,
            nameJapanese = translated.nameJapanese,
            updatedAt = updatedAt,
            lastModifiedByDeviceId = pending.deviceId,
        ).toCloudRecord()
        val mutation = PendingMutation(
            entity = CloudEntity.TRANSACTION_CATEGORY,
            recordId = translatedRecord.id,
            subjectUserId = translatedRecord.ownerUserId,
            kind = MutationKind.UPSERT,
            payload = translatedRecord.payload,
            modifiedAt = updatedAt,
            baseVersion = translatedRecord.syncVersion,
            deviceId = pending.deviceId,
        )
        return if (localStore.applyCategoryTranslation(task, translatedRecord, mutation)) {
            TranslationOutcome.TRANSLATED
        } else {
            TranslationOutcome.STALE
        }
    }

    private fun Throwable.safeCode(): String = when (this) {
        is SupabaseHttpException -> "http_$statusCode"
        is NoTranslationChangeException -> "translation_unchanged"
        is IOException -> "network_io"
        is IllegalArgumentException -> "invalid_translation"
        else -> "unexpected_failure"
    }

    private fun retryDelayMillis(attemptCount: Int): Long {
        val exponent = min(attemptCount.coerceAtLeast(0), 10)
        return min(30_000L * (1L shl exponent), 6L * 60L * 60L * 1_000L)
    }

    private class NoTranslationChangeException : IOException()
    private enum class TranslationOutcome { TRANSLATED, STALE }
}
