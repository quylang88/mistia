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

    @Test
    @Throws(IOException::class)
    fun migrateTwoToThreeCreatesLocalTransactionReceiptMetadata() {
        helper.createDatabase(DATABASE_NAME, 2).close()
        helper.runMigrationsAndValidate(
            DATABASE_NAME,
            3,
            true,
            MistiaDatabase.MIGRATION_2_3,
        ).close()
    }

    @Test
    fun migrateThreeToFourPreservesOutboxAndDistinguishesUnknownZeroBase() {
        val db=helper.createDatabase(DATABASE_NAME,3)
        db.execSQL("""INSERT INTO sync_outbox(owner_user_id,entity,record_id,kind,payload_json,modified_at,base_version,
            device_id,attempt_count,next_attempt_at_epoch_millis,last_error) VALUES
            ('owner','transaction_categories','zero','upsert','{}','clock',0,'device',3,99,'network_io'),
            ('owner','ledger_transactions','known','delete','{}','clock',9007199254740993,'device',2,88,'http_503')""")
        db.close()
        val migrated=helper.runMigrationsAndValidate(DATABASE_NAME,4,true,MistiaDatabase.MIGRATION_3_4)
        migrated.query("SELECT record_id,base_version,attempt_count,remote_identity_observed FROM sync_outbox ORDER BY record_id").use {cursor ->
            org.junit.Assert.assertTrue(cursor.moveToFirst())
            org.junit.Assert.assertEquals("known",cursor.getString(0))
            org.junit.Assert.assertEquals(9007199254740993L,cursor.getLong(1))
            org.junit.Assert.assertEquals(2,cursor.getInt(2))
            org.junit.Assert.assertEquals(1,cursor.getInt(3))
            org.junit.Assert.assertTrue(cursor.moveToNext())
            org.junit.Assert.assertEquals("zero",cursor.getString(0))
            org.junit.Assert.assertEquals(0L,cursor.getLong(1))
            org.junit.Assert.assertEquals(3,cursor.getInt(2))
            org.junit.Assert.assertEquals(0,cursor.getInt(3))
        }
        migrated.close()
    }

    @Test
    fun migrateFourToFiveCreatesLocalNotificationsWithoutRewritingPendingMoney() {
        val db=helper.createDatabase(DATABASE_NAME,4)
        db.execSQL("""INSERT INTO sync_outbox(owner_user_id,entity,record_id,kind,payload_json,modified_at,base_version,
            device_id,attempt_count,remote_identity_observed,next_attempt_at_epoch_millis,last_error) VALUES
            ('owner','ledger_transactions','known','delete','{}','clock',9007199254740993,'device',2,1,88,'http_503')""")
        db.close()
        val migrated=helper.runMigrationsAndValidate(DATABASE_NAME,5,true,MistiaDatabase.MIGRATION_4_5)
        migrated.query("SELECT base_version,remote_identity_observed,attempt_count FROM sync_outbox").use {cursor ->
            org.junit.Assert.assertTrue(cursor.moveToFirst())
            org.junit.Assert.assertEquals(9007199254740993L,cursor.getLong(0))
            org.junit.Assert.assertEquals(1,cursor.getInt(1))
            org.junit.Assert.assertEquals(2,cursor.getInt(2))
        }
        migrated.query("SELECT count(*) FROM local_app_notifications").use {cursor ->
            org.junit.Assert.assertTrue(cursor.moveToFirst());org.junit.Assert.assertEquals(0,cursor.getInt(0))
        }
        migrated.close()
    }

    @Test
    fun migrateFiveToSixPreservesLegacyQueueWithoutInventingCausalMembership() {
        val db = helper.createDatabase(DATABASE_NAME, 5)
        db.execSQL("""INSERT INTO sync_outbox(owner_user_id,entity,record_id,kind,payload_json,modified_at,base_version,
            device_id,attempt_count,remote_identity_observed,next_attempt_at_epoch_millis,last_error) VALUES
            ('owner','installment_plans','known','delete','{}','clock',9007199254740993,'device',7,1,99,'http_503')""")
        db.close()
        val migrated = helper.runMigrationsAndValidate(DATABASE_NAME, 6, true, MistiaDatabase.MIGRATION_5_6)
        migrated.query("SELECT base_version,attempt_count,remote_identity_observed FROM sync_outbox").use { cursor ->
            org.junit.Assert.assertTrue(cursor.moveToFirst()); org.junit.Assert.assertEquals(9007199254740993L, cursor.getLong(0))
            org.junit.Assert.assertEquals(7, cursor.getInt(1)); org.junit.Assert.assertEquals(1, cursor.getInt(2))
        }
        migrated.query("SELECT count(*) FROM installment_delete_batches").use { cursor ->
            org.junit.Assert.assertTrue(cursor.moveToFirst()); org.junit.Assert.assertEquals(0, cursor.getInt(0))
        }
        migrated.close()
    }

    private companion object {
        const val DATABASE_NAME = "mistia-migration-test"
    }
}
