package vn.com.quyln.mistia.core.model

/** Presentation readset; the linked-wallet mutation/CAS contract stays three entities. */
data class InvestmentCashReadSnapshot(val owner:UserId,val rows:List<CloudRecord>) {
    fun requireScoped() {
        if(financeRawUuid(owner.value)!=owner.value || rows.any{row ->
            val entity=CloudEntity.fromTable(row.entity)
            entity==null || entity !in entities || !row.financeRawIdentity(owner,entity,true) || financeRawUuid(row.id)!=row.id
        } || rows.map{it.entity to it.id}.distinct().size!=rows.size)
            throw InvestmentCashReadException(InvestmentCashReadError.UNREADABLE_SOURCE)
    }
    fun walletSnapshot():InvestmentWalletSnapshot {
        requireScoped()
        return InvestmentWalletSnapshot(owner,rows.filter{CloudEntity.fromTable(it.entity) in InvestmentWalletSnapshot.entities})
    }
    companion object {val entities=InvestmentWalletSnapshot.entities+CloudEntity.INVESTMENT_TRADE}
}
