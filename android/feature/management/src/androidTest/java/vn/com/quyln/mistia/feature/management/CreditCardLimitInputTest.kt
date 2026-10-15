package vn.com.quyln.mistia.feature.management

import android.content.Context
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.time.Instant
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import org.junit.*
import org.junit.rules.ExternalResource
import org.junit.rules.RuleChain
import org.junit.runner.RunWith
import vn.com.quyln.mistia.core.database.*
import vn.com.quyln.mistia.core.designsystem.MistiaTheme
import vn.com.quyln.mistia.core.designsystem.R
import vn.com.quyln.mistia.core.model.*

@RunWith(AndroidJUnit4::class)
class CreditCardLimitInputTest {
    private val compose = createComposeRule()
    @get:Rule val rules = RuleChain.outerRule(object : ExternalResource() {
        override fun after() { if (::db.isInitialized) db.close() }
    }).around(compose)
    private lateinit var db: MistiaDatabase
    private val owner = UserId("11111111-1111-1111-1111-111111111111")
    private val device = "22222222-2222-2222-2222-222222222222"

    @Test fun jpyLimitGroupsDuringTypingAndReopensWithoutLosingMinorUnits() = exactLimitWorkflow("JPY")
    @Test fun vndLimitGroupsDuringTypingAndReopensWithoutLosingMinorUnits() = exactLimitWorkflow("VND")

    private fun exactLimitWorkflow(currency: String) {
        val context = ApplicationProvider.getApplicationContext<Context>()
        db = Room.inMemoryDatabaseBuilder(context, MistiaDatabase::class.java).allowMainThreadQueries().build()
        val store = RoomLocalStore(db)
        val repo = OfflineFirstFinanceRepository(store)
        val visible = mutableStateOf(true)
        val card = mutableStateOf<CreditCardAccount?>(null)
        compose.setContent { MistiaTheme(darkTheme = false) { if (visible.value) CreditCardEditorSheet(owner.value,
            card.value?.wallet, card.value?.profile, emptyList(), 0,
            onDismiss = { visible.value = false },
            onSave = { draft -> repo.saveCreditCard(owner, draft, device, Instant.now().toString()).onSuccess { card.value = it } },
        ) } }
        val amount = hasText(context.getString(R.string.management_management_credit_limit)) and hasSetTextAction()
        compose.onNodeWithTag("card.name").performScrollTo().performTextReplacement("Exact card")
        if (currency == "VND") compose.onNodeWithText("VND").performScrollTo().performClick()
        compose.onNode(amount).performScrollTo().performTextReplacement("9007199254740993")
        compose.onNode(amount).assertTextContains("9,007,199,254,740,993")
        Assert.assertTrue(runBlocking { repo.observeCreditCardProfiles(owner).first().isEmpty() })
        compose.onNodeWithTag("card.save").performScrollTo().performClick()
        compose.waitUntil(5000) { !visible.value }
        val created = runBlocking { CreditCardAccount(repo.observeWallets(owner).first().single(), repo.observeCreditCardProfiles(owner).first().single()) }
        Assert.assertEquals(9007199254740993L, created.profile.creditLimitMinor)
        Assert.assertEquals(currency, created.wallet.currencyCode)
        Assert.assertEquals(0L, created.wallet.openingBalanceMinor)
        compose.runOnIdle { card.value = created; visible.value = true }
        compose.onNode(amount).performScrollTo().assertTextContains("9,007,199,254,740,993")
        compose.onNode(amount).performTextReplacement("1375")
        compose.onNode(amount).assertTextContains("1,375")
        compose.onNodeWithTag("card.save").performScrollTo().performClick()
        compose.waitUntil(5000) { !visible.value }
        val edited = runBlocking { CreditCardAccount(repo.observeWallets(owner).first().single(), repo.observeCreditCardProfiles(owner).first().single()) }
        Assert.assertEquals(created.wallet.id, edited.wallet.id)
        Assert.assertEquals(created.profile.id, edited.profile.id)
        Assert.assertEquals(1375L, edited.profile.creditLimitMinor)
        Assert.assertEquals(0L, edited.wallet.syncVersion)
        Assert.assertEquals(0L, edited.profile.syncVersion)
        Assert.assertEquals(1, runBlocking { store.pendingMutations(owner, CloudEntity.LEDGER_WALLET, Long.MAX_VALUE).size })
        Assert.assertEquals(1, runBlocking { store.pendingMutations(owner, CloudEntity.CREDIT_CARD_PROFILE, Long.MAX_VALUE).size })
        val queued = runBlocking { store.pendingMutations(owner, CloudEntity.CREDIT_CARD_PROFILE, Long.MAX_VALUE).single().mutation }
        Assert.assertEquals(0L, queued.baseVersion)
        Assert.assertEquals(1375L, queued.payload!!["credit_limit_minor"]!!.jsonPrimitive.long)
        Assert.assertTrue(runBlocking { repo.observeTransactions(owner).first().isEmpty() })
    }
}
