#!/usr/bin/env python3
"""Run the real local notification migration/DAO SQL against SQLite."""
import json
import pathlib
import re
import sqlite3
import unittest
ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'android/core/database/src/main/java/vn/com/quyln/mistia/core/database/MistiaDatabase.kt'
NOTIFICATION = ROOT / 'android/core/database/src/main/java/vn/com/quyln/mistia/core/database/LocalNotifications.kt'

class NotificationStoreTests(unittest.TestCase):
    def store(self):
        db = sqlite3.connect(':memory:')
        self.addCleanup(db.close)
        schema = json.loads((ROOT / 'android/core/database/schemas/vn.com.quyln.mistia.core.database.MistiaDatabase/4.json').read_text())['database']
        for entity in schema['entities']:
            db.execute(entity['createSql'].replace('${TABLE_NAME}', entity['tableName']))
        db.execute("INSERT INTO sync_outbox(owner_user_id,entity,record_id,kind,payload_json,modified_at,base_version,device_id,attempt_count,remote_identity_observed,next_attempt_at_epoch_millis,last_error) VALUES ('owner','ledger_transactions','ledger','upsert','{\"minor\":9007199254740993}','2026-10-14T00:00:00Z',9007199254740993,'device',2,1,999,'retry')")
        match = re.search(r'val MIGRATION_4_5 =.*?override fun migrate.*?\{(.*?)\n            \}', SOURCE.read_text(), re.S)
        self.assertIsNotNone(match, 'Missing production 4-to-5 notification migration')
        for sql in re.findall(r'db.execSQL\("([^"]+)"\)', match[1]):
            db.execute(sql)
        return db

    def test_migration_preserves_exact_outbox_and_schema_shape(self):
        db = self.store()
        self.assertEqual((9007199254740993, '{"minor":9007199254740993}', 2, 1, 999, 'retry'), db.execute('SELECT base_version,payload_json,attempt_count,remote_identity_observed,next_attempt_at_epoch_millis,last_error FROM sync_outbox').fetchone())
        schema = json.loads((ROOT / 'android/core/database/schemas/vn.com.quyln.mistia.core.database.MistiaDatabase/5.json').read_text())['database']
        table = next(row for row in schema['entities'] if row['tableName']=='local_app_notifications')
        expected = sqlite3.connect(':memory:')
        self.addCleanup(expected.close)
        expected.execute(table['createSql'].replace('${TABLE_NAME}', table['tableName']))
        self.assertEqual(expected.execute('PRAGMA table_info(local_app_notifications)').fetchall(), db.execute('PRAGMA table_info(local_app_notifications)').fetchall())

    def test_same_key_is_partitioned_by_owner_without_cloud_outbox(self):
        db = self.store()
        db.execute("INSERT INTO local_app_notifications VALUES ('owner','same-key','{\"isRead\":false}')")
        db.execute("INSERT INTO local_app_notifications VALUES ('viewer','same-key','{\"isRead\":true}')")
        self.assertEqual(2,db.execute('SELECT count(*) FROM local_app_notifications').fetchone()[0])
        self.assertEqual(1,db.execute('SELECT count(*) FROM sync_outbox').fetchone()[0])

    def test_actual_clear_account_sql_does_not_remove_other_owner(self):
        db = self.store()
        db.executemany('INSERT INTO local_app_notifications VALUES (?,?,?)',[('owner','same-key','{}'),('viewer','same-key','{}')])
        source=NOTIFICATION.read_text()
        sql=re.search(r'@Query\("([^"]+)"\)\s*suspend fun deleteAccount',source)[1]
        db.execute(sql,dict(ownerUserId='owner'))
        self.assertEqual([('viewer',)],db.execute('SELECT owner_user_id FROM local_app_notifications').fetchall())

if __name__=='__main__': unittest.main()
