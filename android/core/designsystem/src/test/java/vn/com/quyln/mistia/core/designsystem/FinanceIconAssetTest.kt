package vn.com.quyln.mistia.core.designsystem

import org.junit.Assert.*
import org.junit.Test

class FinanceIconAssetTest {
    @Test fun `internet token resolves its actual colorful wifi artwork instead of the broad house group`() {
        val resolved=financeIconAsset("mistia.category.expense.home_bills.internet");assertNotNull("Registered source artwork must resolve",resolved);val icon=resolved!!
        assertEquals("ic_fluent_wifi_24_color",icon.assetName);assertFalse(icon.template);assertTrue(icon.drawableRes!=0)
    }
    @Test fun `planning loan retains the vault artwork and its registered descriptor color`() {
        val resolved=financeIconAsset("mistia.plan.loan");assertNotNull("Registered source artwork must resolve",resolved);val icon=resolved!!
        assertEquals("ic_fluent_vault_24_color",icon.assetName);assertEquals("#5B7BFF",icon.primaryHex);assertFalse(icon.template)
    }
    @Test fun `filled template keeps template semantics and source primary color`() {
        val resolved=financeIconAsset("mistia.category.expense.family_children.baby_food");assertNotNull("Registered source artwork must resolve",resolved);val icon=resolved!!
        assertEquals("ic_fluent_bowl_salad_24_filled",icon.assetName);assertTrue(icon.template)
        assertEquals("#FFB347",icon.primaryHex)
    }
    @Test fun `inactive historical housing token resolves the shared home fallback`() {
        val resolved=financeIconAsset("mistia.category.legacy.housing");assertNotNull("Registered source artwork must resolve",resolved);val icon=resolved!!
        assertEquals("ic_fluent_building_home_24_color",icon.assetName)
    }
    @Test fun `unregistered old system symbols stay available to the existing fallback renderer`() {
        assertNull(financeIconAsset("wifi"));assertNull(financeIconAsset("future.finance.token"));assertNull(financeIconAsset(""))
    }
}
