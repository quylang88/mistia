package vn.com.quyln.mistia.feature.management

import java.time.*
import org.junit.Assert.*
import org.junit.Test
import vn.com.quyln.mistia.core.model.*

class StatementPaymentSourceTest {
    @Test fun `Postgres rounded birth and ACK metadata keep the same statement consent target`() {
        val owner=UserId("11111111-1111-1111-1111-111111111111")
        val device="22222222-2222-2222-2222-222222222222"
        val card=LedgerWalletRecord.fromCloudRecord(WalletDraft(id="33333333-3333-3333-3333-333333333333",name="Card",kind=WalletKind.CASH,currencyCode="JPY").toMutation(owner,null,device,"2026-08-01T00:00:00.123456700Z").record).copy(kindWireValue="creditCard")
        val profile=CreditCardProfileRecord("44444444-4444-4444-4444-444444444444",owner.value,"Issuer","visa","1234",1000,10,26,null,card.id,null,true,card.createdAt,card.updatedAt,null,0,device)
        val expected=CreditCardStatement(CreditCardAccount(card,profile),YearMonth.of(2026,9),Instant.parse("2026-10-10T00:00:00Z"),Instant.parse("2026-10-26T00:00:00Z"),70,930,DueStatus.PENDING,null,CreditCardStatementState.PAYABLE)
        val ack=expected.copy(account=CreditCardAccount(card.copy(createdAt="2026-08-01T00:00:00.123457Z",updatedAt="2026-10-22T00:00:00Z",syncVersion=9007199254740993),profile.copy(createdAt="2026-08-01T00:00:00.123457Z",syncVersion=9007199254740993)))
        assertTrue(sameStatementPaymentTarget(ack,expected))
        assertFalse(sameStatementPaymentTarget(ack.copy(amountMinor=80),expected))
        assertFalse(sameStatementPaymentTarget(ack.copy(account=ack.account.copy(wallet=ack.account.wallet.copy(currencyCode="VND"))),expected))
    }
}
