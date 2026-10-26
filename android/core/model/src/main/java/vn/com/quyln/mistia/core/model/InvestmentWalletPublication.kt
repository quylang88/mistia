package vn.com.quyln.mistia.core.model

import kotlinx.serialization.json.*

/** Only the owner's reserved accounting wallet can enter the investment metadata publisher. */
fun canonicalInvestmentWalletForPublication(owner:UserId,row:CloudRecord,forWrite:Boolean=false):LedgerWalletRecord {
    require(financeRawUuid(owner.value)==owner.value){"Invalid investment wallet owner"}
    require(row.entity==CloudEntity.LEDGER_WALLET.table && row.ownerUserId==owner.value && row.id==investmentSystemWalletId(owner)) {
        "Investment wallet publication identity differs"
    }
    require(row.financeRawIdentity(owner,CloudEntity.LEDGER_WALLET,true) &&
        row.payload.financeRawString("id")==row.id && row.payload.financeRawString("user_id")==owner.value) {
        "Investment wallet publication scope differs"
    }
    val wallet=investmentLinkedWalletRecord(row)
    require(wallet.kind==WalletKind.INVESTMENT && wallet.systemPurposeRawValue=="investmentProfit" && wallet.openingBalanceMinor==0L) {
        "Only canonical investment metadata is supported"
    }
    require(normalizedInvestmentChannelName(wallet.name).isNotEmpty()){"Investment wallet name is missing"}
    require(row.updatedAt==row.payload.financeRawString("updated_at") && wallet.updatedAt==row.updatedAt && wallet.deletedAt==row.deletedAt) {
        "Investment wallet timestamp authority differs"
    }
    val linked=row.payload.financeRawString("investment_linked_wallet_id")
    linked?.let{require(financeRawUuid(it)==it && it!=row.id){"Invalid investment linked wallet identity"}}
    require(wallet.investmentLinkedWalletId==linked){"Investment linked wallet identity differs"}
    if(forWrite)require(!wallet.isArchived && wallet.deletedAt==null){"Canonical investment wallet must remain active"}
    return wallet
}

enum class InvestmentWalletPublicationDependency { READY, WAITING_FOR_LINKED_WALLET, INVALID_LINK, UNREADABLE_SOURCE }

/** One Room generation of the root row/outbox and its ordinary linked-wallet dependency. */
data class InvestmentWalletPublicationSnapshot(
    val owner:UserId,val record:CloudRecord?,val pending:QueuedMutation?,val hasPendingMutation:Boolean,
    val linkedRecord:CloudRecord?=null,val linkedPending:QueuedMutation?=null,val linkedHasPendingMutation:Boolean=false,
) {
    fun matches(queued:QueuedMutation):Boolean {
        val row=record ?: return false
        return runCatching{row.id==investmentSystemWalletId(owner)}.getOrDefault(false) && pending==queued &&
            hasPendingMutation && walletPublicationQueueMatches(owner,row,queued)
    }
    fun dependency():InvestmentWalletPublicationDependency {
        val root=record?.let{runCatching{canonicalInvestmentWalletForPublication(owner,it,forWrite=true)}.getOrNull()}
            ?: return InvestmentWalletPublicationDependency.UNREADABLE_SOURCE
        val id=root.investmentLinkedWalletId
        if(id==null)return if(linkedRecord==null && linkedPending==null && !linkedHasPendingMutation)
            InvestmentWalletPublicationDependency.READY else InvestmentWalletPublicationDependency.UNREADABLE_SOURCE
        val raw=linkedRecord ?: return InvestmentWalletPublicationDependency.INVALID_LINK
        if(raw.entity!=CloudEntity.LEDGER_WALLET.table || raw.id!=id || raw.ownerUserId!=owner.value ||
            !raw.financeRawIdentity(owner,CloudEntity.LEDGER_WALLET,true))return InvestmentWalletPublicationDependency.INVALID_LINK
        val linked=runCatching{investmentLinkedWalletRecord(raw)}.getOrNull() ?: return InvestmentWalletPublicationDependency.INVALID_LINK
        if(linked.kind==null || linked.kind in setOf(WalletKind.INVESTMENT,WalletKind.CREDIT_CARD) ||
            linked.systemPurposeRawValue!=null || linked.isArchived || linked.deletedAt!=null || linked.currencyCode!=root.currencyCode)
            return InvestmentWalletPublicationDependency.INVALID_LINK
        val queued=linkedPending
        if(linkedHasPendingMutation!=(queued!=null))return InvestmentWalletPublicationDependency.UNREADABLE_SOURCE
        if(queued!=null) {
            if(!walletPublicationQueueMatches(owner,raw,queued))return InvestmentWalletPublicationDependency.UNREADABLE_SOURCE
            return InvestmentWalletPublicationDependency.WAITING_FOR_LINKED_WALLET
        }
        return InvestmentWalletPublicationDependency.READY
    }
}

private fun walletPublicationQueueMatches(owner:UserId,row:CloudRecord,queued:QueuedMutation):Boolean {
    val q=queued.mutation
    return row.entity==CloudEntity.LEDGER_WALLET.table && row.ownerUserId==owner.value && row.financeRawIdentity(owner,CloudEntity.LEDGER_WALLET,true) &&
        financeRawUuid(row.id)==row.id && q.entity==CloudEntity.LEDGER_WALLET && q.recordId==row.id && q.subjectUserId==owner.value &&
        financeRawUuid(q.deviceId)==q.deviceId && q.payload==row.payload && q.baseVersion==row.syncVersion && q.modifiedAt==row.updatedAt &&
        row.payload.financeRawString("updated_at")==row.updatedAt && row.payload.financeRawString("last_modified_by_device_id")==q.deviceId &&
        q.kind==(if(row.deletedAt==null)MutationKind.UPSERT else MutationKind.DELETE)
}

/** The server enforces this presentation and derives the balance; neither is editable root metadata. */
fun investmentWalletMetadataForComparison(payload:JsonObject):JsonObject {
    val fixed=buildJsonObject {
        put("name",JsonPrimitive("Investment Wallet"))
        put("kind_raw_value",JsonPrimitive("investment"))
        put("system_purpose_raw_value",JsonPrimitive("investmentProfit"))
        put("opening_balance_minor",JsonPrimitive(0L))
        put("icon_symbol_name",JsonPrimitive("chart.line.uptrend.xyaxis"))
        put("icon_color_hex",JsonPrimitive("#9A67FF"))
        put("institution_display_name",JsonNull);put("institution_preset_key",JsonNull)
        put("sort_order",JsonPrimitive(2147483547))
        put("is_archived",payload["is_archived"] ?: JsonPrimitive(false))
        put("archived_at",if(payload.financeRawArchived()==true)payload["archived_at"] ?: JsonNull else JsonNull)
        put("currency_code",JsonPrimitive(requireNotNull(payload.financeRawString("currency_code")?.financeReportingCode())))
        put("investment_linked_wallet_id",payload["investment_linked_wallet_id"] ?: JsonNull)
    }
    return JsonObject((payload-"current_balance_minor"-LOCAL_INVESTMENT_WALLET_PARENTS_KEY)+fixed)
}
