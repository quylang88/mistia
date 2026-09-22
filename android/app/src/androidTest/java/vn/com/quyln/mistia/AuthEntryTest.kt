package vn.com.quyln.mistia

import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.performClick
import org.junit.Rule
import org.junit.Test
import vn.com.quyln.mistia.core.designsystem.R as DesignR

/** Signed-out UI only; never submits credentials or writes financial data. */
class AuthEntryTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()

    @Test fun offersGoogleAndEmailWithEmailRegistrationAndRecovery() {
        compose.onNodeWithText(compose.activity.getString(DesignR.string.management_managementauth_continue_with_google)).assertIsDisplayed()
        compose.onNodeWithText(compose.activity.getString(DesignR.string.management_managementauth_continue_with_email)).performClick()
        compose.onNodeWithText(compose.activity.getString(DesignR.string.management_managementauth_forgot_password)).assertIsDisplayed()
        compose.onNodeWithText(compose.activity.getString(DesignR.string.management_managementauth_sign_up_now)).performClick()
        compose.onNodeWithText(compose.activity.getString(DesignR.string.management_managementauth_confirm_password)).assertIsDisplayed()
    }
}
