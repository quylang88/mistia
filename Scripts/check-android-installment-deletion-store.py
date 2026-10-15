#!/usr/bin/env python3
"""Exercise the production 5-to-6 migration and deletion-batch DAO SQL in SQLite.
This does not execute Kotlin/Room transactions or replace device instrumentation.
"""
import json
import pathlib
import re
import sqlite3
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'android/core/database/src/main/java/vn/com/quyln/mistia/core/database/MistiaDatabase.kt'
DAO = ROOT / 'android/core/database/src/main/java/vn/com/quyln/mistia/core/database/InstallmentDeletionStore.kt'
SCHEMAS = ROOT / 'android/core/database/schemas/vn.com.quyln.mistia.core.database.MistiaDatabase'
A = '11111111-1111-1111-1111-111111111111'
B = '99999999-9999-9999-9999-999999999999'
PLAN = '22222222-2222-2222-2222-222222222222'
BATCH = '33333333-3333-3333-3333-333333333333'
NEW = '44444444-4444-4444-4444-444444444444'
CLOCK = '2026-10-15T00:00:00Z'

class DeletionStoreTests(unittest.TestCase):
    def store(self):
        db = sqlite3.connect(':memory:')
        db.execute('PRAGMA foreign_keys=ON')
        self.addCleanup(db.close)
        for entity in json.loads((SCHEMAS / '5.json').read_text())['database']['entities']:
            db.execute(entity['createSql'].replace('${TABLE_NAME}', entity['tableName']))
            for index in entity.get('indices', []):
                db.execute(index['createSql'].replace('${TABLE_NAME}', entity['tableName']))
        db.execute('INSERT INTO cloud_records VALUES (?,?,?,?,?,?,?,?,?)', (A, 'installment_plans', PLAN, '{"amount":9007199254740993}', CLOCK, CLOCK, 9007199254740993, 1, 0))
        db.execute('INSERT INTO sync_outbox VALUES (?,?,?,?,?,?,?,?,?,?,?,?)', (A, 'installment_plans', PLAN, 'delete', '{"amount":9007199254740993}', CLOCK, 9007199254740993, BATCH, 7, 99, 'http_503', 1))
        db.execute('INSERT INTO local_app_notifications VALUES (?,?,?)', (A, 'keep', '{"isRead":false}'))
        db.commit()
        match = re.search(r'val MIGRATION_5_6 =.*?override fun migrate.*?\{(.*?)\n            \}', SOURCE.read_text(), re.S)
        self.assertIsNotNone(match, 'Missing production 5-to-6 deletion batch migration')
        statements = re.findall(r'db.execSQL\("([^"]+)"\)', match[1])
        self.assertEqual(4, len(statements))
        for sql in statements: db.execute(sql)
        db.commit()
        return db

    def query(self, name):
        match = re.search(r'@Query\("([^"]+)"\)\s*suspend fun ' + name + r'\(', DAO.read_text())
        self.assertIsNotNone(match, 'Missing actual DAO query ' + name)
        return match[1]

    def insert(self, db, owner=A, batch=BATCH, plan=PLAN):
        payload = json.dumps({'version': 9007199254740993, 'cycle_ids': ['cycle'], 'pending_before': None})
        db.execute('INSERT INTO installment_delete_batches(owner_user_id,plan_id,batch_id,payload_json) VALUES (?,?,?,?)', (owner, plan, batch, payload))

    def test_migration_preserves_old_money_queue_notifications_and_leaves_legacy_intents_unproven(self):
        db = self.store()
        self.assertEqual((9007199254740993, 7, 1, 99, 'http_503'), db.execute('SELECT base_version,attempt_count,remote_identity_observed,next_attempt_at_epoch_millis,last_error FROM sync_outbox').fetchone())
        self.assertEqual('{"amount":9007199254740993}', db.execute('SELECT payload_json FROM cloud_records').fetchone()[0])
        self.assertEqual('{"isRead":false}', db.execute('SELECT payload_json FROM local_app_notifications').fetchone()[0])
        self.assertEqual(0, db.execute('SELECT count(*) FROM installment_delete_batches').fetchone()[0])

    def test_migration_shape_and_index_match_exported_room_schema(self):
        db = self.store()
        expected = sqlite3.connect(':memory:'); self.addCleanup(expected.close)
        for table in (t for t in json.loads((SCHEMAS / '6.json').read_text())['database']['entities'] if t['tableName'] in ('installment_delete_batches', 'installment_delete_chunks')):
            name = table['tableName']
            expected.execute(table['createSql'].replace('${TABLE_NAME}', name))
            for index in table.get('indices', []): expected.execute(index['createSql'].replace('${TABLE_NAME}', name))
            for pragma in ('table_info', 'index_list', 'foreign_key_list'):
                self.assertEqual(expected.execute(f'PRAGMA {pragma}({name})').fetchall(), db.execute(f'PRAGMA {pragma}({name})').fetchall())

    def test_actual_owner_lookup_and_account_clear_do_not_touch_other_owner(self):
        db = self.store(); self.insert(db); self.insert(db, owner=B)
        for owner in (A, B): db.execute('INSERT INTO installment_delete_chunks VALUES (?,?,?,?,?)', (owner, PLAN, BATCH, 0, b'chunk'))
        row = db.execute(self.query('record'), {'ownerUserId': A, 'planId': PLAN}).fetchone()
        self.assertIn(A, row); self.assertNotIn(B, row)
        db.execute(self.query('deleteAccount'), {'ownerUserId': A})
        self.assertEqual([(B,)], db.execute('SELECT owner_user_id FROM installment_delete_batches').fetchall())
        self.assertEqual([(B,)], db.execute('SELECT owner_user_id FROM installment_delete_chunks').fetchall())

    def test_actual_exact_delete_cannot_remove_another_or_newer_batch(self):
        db = self.store(); self.insert(db, batch=NEW)
        for owner, batch in [(B, NEW), (A, BATCH)]:
            self.assertEqual(0, db.execute(self.query('deleteExact'), {'ownerUserId': owner, 'planId': PLAN, 'batchId': batch}).rowcount)
        self.assertEqual(1, db.execute(self.query('deleteExact'), {'ownerUserId': A, 'planId': PLAN, 'batchId': NEW}).rowcount)

    def test_batch_identity_is_unique_per_owner_but_partitioned_between_owners(self):
        db = self.store(); self.insert(db)
        with self.assertRaises(sqlite3.IntegrityError): self.insert(db, plan=NEW)
        self.insert(db, owner=B)
        self.assertEqual(2, db.execute('SELECT count(*) FROM installment_delete_batches').fetchone()[0])

    def test_sql_transaction_rolls_back_batch_and_record_when_outbox_insert_fails(self):
        db = self.store()
        db.execute("CREATE TRIGGER reject_delete_batch_outbox BEFORE INSERT ON sync_outbox BEGIN SELECT RAISE(ABORT, 'fixture'); END")
        db.commit()
        with self.assertRaises(sqlite3.IntegrityError):
            with db:
                self.insert(db)
                db.execute('INSERT INTO installment_delete_chunks VALUES (?,?,?,?,?)', (A, PLAN, BATCH, 0, b'chunk'))
                db.execute("UPDATE cloud_records SET payload_json='changed' WHERE owner_user_id=?", (A,))
                db.execute('INSERT INTO sync_outbox VALUES (?,?,?,?,?,?,?,?,?,?,?,?)', (A, 'due_occurrence_records', NEW, 'delete', '{}', CLOCK, 0, BATCH, 0, 0, None, 0))
        self.assertEqual(0, db.execute('SELECT count(*) FROM installment_delete_batches').fetchone()[0])
        self.assertEqual('{"amount":9007199254740993}', db.execute('SELECT payload_json FROM cloud_records').fetchone()[0])
        self.assertEqual(0, db.execute('SELECT count(*) FROM installment_delete_chunks').fetchone()[0])
        self.assertEqual(1, db.execute('SELECT count(*) FROM sync_outbox').fetchone()[0])

    def test_chunk_rows_follow_owner_scope_and_exact_parent_delete_cascades(self):
        db = self.store(); self.insert(db); self.insert(db, owner=B)
        for owner in (A, B):
            db.execute('INSERT INTO installment_delete_chunks VALUES (?,?,?,?,?)', (owner, PLAN, BATCH, 0, b'chunk'))
        self.assertEqual(0, db.execute(self.query('deleteExact'), {'ownerUserId': A, 'planId': PLAN, 'batchId': NEW}).rowcount)
        self.assertEqual(2, db.execute('SELECT count(*) FROM installment_delete_chunks').fetchone()[0])
        self.assertEqual(1, db.execute(self.query('deleteExact'), {'ownerUserId': A, 'planId': PLAN, 'batchId': BATCH}).rowcount)
        self.assertEqual([(B,)], db.execute('SELECT owner_user_id FROM installment_delete_chunks').fetchall())

if __name__ == '__main__': unittest.main()
