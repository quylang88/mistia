package vn.com.quyln.mistia.core.model

/** Private immutable Storage objects; publication and local cache lifecycle belong to the caller. */
interface InvestmentProductImageRemote {
    suspend fun download(
        owner: UserId,
        assetId: String,
        path: String,
        isCurrent: () -> Boolean = { true },
    ): Result<ByteArray?>

    suspend fun upload(
        owner: UserId,
        assetId: String,
        path: String,
        bytes: ByteArray,
        isCurrent: () -> Boolean = { true },
    ): Result<Unit>

    suspend fun delete(
        owner: UserId,
        assetId: String,
        path: String,
        isCurrent: () -> Boolean = { true },
    ): Result<Unit>
}
