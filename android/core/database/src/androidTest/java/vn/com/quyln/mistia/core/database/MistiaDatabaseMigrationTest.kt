package vn.com.quyln.mistia.core.database

import androidx.room.testing.MigrationTestHelper
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.IOException
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class MistiaDatabaseMigrationTest {
    @get:Rule
    val helper = MigrationTestHelper(
        InstrumentationRegistry.getInstrumentation(),
        MistiaDatabase::class.java,
    )

    @Test
    @Throws(IOException::class)
    fun migrateOneToTwoCreatesAccountScopedCategoryTranslationQueue() {
        helper.createDatabase(DATABASE_NAME, 1).close()
        helper.runMigrationsAndValidate(
            DATABASE_NAME,
            2,
            true,
            MistiaDatabase.MIGRATION_1_2,
        ).close()
    }

    private companion object {
        const val DATABASE_NAME = "mistia-migration-test"
    }
}
