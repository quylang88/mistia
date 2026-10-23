package vn.com.quyln.mistia.core.model

/** All ordinary-save validation and investment money inputs read under one owner/Room transaction. */
data class TransactionInvestmentSaveSnapshot(val owner:UserId,val recordsByEntity:Map<CloudEntity,List<CloudRecord>>) {
    fun requireValid() {
        require(recordsByEntity.keys==entities){"Incomplete ordinary/investment save dependencies"}
        transactionSnapshot().requireValid()
        investmentSnapshot().requireScoped()
    }
    private fun requireShape(){require(recordsByEntity.keys==entities){"Incomplete ordinary/investment save dependencies"}}
    fun transactionSnapshot():TransactionSaveSnapshot {requireShape();return TransactionSaveSnapshot(owner,recordsByEntity.filterKeys{it in TransactionSaveSnapshot.entities})}
    fun investmentSnapshot():InvestmentCashReadSnapshot {requireShape();return InvestmentCashReadSnapshot(owner,InvestmentCashReadSnapshot.entities.flatMap{recordsByEntity.getValue(it)})}
    fun requireUnchanged(current:TransactionInvestmentSaveSnapshot) {
        requireValid();current.requireValid()
        require(owner==current.owner && recordsByEntity.all{(entity,rows)->rows.sortedBy{it.id}==current.recordsByEntity.getValue(entity).sortedBy{it.id}}){"Ordinary/investment save dependencies changed"}
    }
    companion object {val entities=TransactionSaveSnapshot.entities+InvestmentCashReadSnapshot.entities}
}
