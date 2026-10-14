#!/usr/bin/env python3
"""Execute the production Room outbox predicates against SQLite (no device needed)."""
import json
import pathlib
import re
import sqlite3
import unittest

SOURCE = pathlib.Path(__file__).resolve().parents[1] / 'android/core/database/src/main/java/vn/com/quyln/mistia/core/database/MistiaDatabase.kt'
DAO = SOURCE.read_text().split('interface SyncOutboxDao {', 1)[1].split('@Dao', 1)[0]
QUERIES = dict((name, sql) for sql, name in re.findall(r'@Query\(\s*"""(.*?)"""\s*\)\s*suspend fun (\w+)', DAO, re.S))


class OutboxCompareAndSwapTests(unittest.TestCase):
    def execute(self, method, *, replacement=None, sent=None):
        row = dict(ownerUserId='owner', entity='ledger_transactions', recordId='record',
                   kind='delete', payloadJson='{"amount_minor":9007199254740993}',
                   modifiedAt='2026-10-14T00:00:00Z', baseVersion=9007199254740993,
                   deviceId='device', attemptCount=0, remoteIdentityObserved=0)
        sent_values = row | (sent or {})
        row.update(replacement or {})
        db = sqlite3.connect(':memory:')
        self.addCleanup(db.close)
        schema_dir = pathlib.Path(__file__).resolve().parents[1] / 'android/core/database/schemas/vn.com.quyln.mistia.core.database.MistiaDatabase'
        schema = json.loads((schema_dir / '5.json').read_text())['database']
        table = next(item for item in schema['entities'] if item['tableName'] == 'sync_outbox')
        db.execute(table['createSql'].replace('${TABLE_NAME}', 'sync_outbox'))
        db.execute("""INSERT INTO sync_outbox(owner_user_id,entity,record_id,kind,payload_json,modified_at,
            base_version,device_id,attempt_count,remote_identity_observed,next_attempt_at_epoch_millis,last_error)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, NULL)""", tuple(row.values()))
        changed = db.execute(QUERIES[method], sent_values | dict(nextAttemptAtEpochMillis=99, errorCode='old_failure')).rowcount
        return changed, db.execute('SELECT kind, payload_json, attempt_count FROM sync_outbox').fetchall()

    def test_changed_payload_rejects_old_ack_and_failure(self):
        for method in ('deleteExact', 'markFailureExact'):
            with self.subTest(method=method):
                count, rows = self.execute(method, replacement=dict(payloadJson='{"amount_minor":9007199254740994}'))
                self.assertEqual(0, count)
                self.assertEqual(0, rows[0][2])

    def test_changed_kind_rejects_old_ack_and_failure(self):
        for method in ('deleteExact', 'markFailureExact'):
            with self.subTest(method=method):
                count, _ = self.execute(method, replacement=dict(kind='upsert'))
                self.assertEqual(0, count)

    def test_changed_remote_provenance_rejects_old_ack_and_failure(self):
        for method in ('deleteExact', 'markFailureExact'):
            with self.subTest(method=method):
                count, _ = self.execute(method, replacement=dict(remoteIdentityObserved=1))
                self.assertEqual(0, count)

    def test_matching_snapshot_accepts_ack_and_failure(self):
        for payload in (None, '{"amount_minor":9007199254740993}'):
            for method in ('deleteExact', 'markFailureExact'):
                with self.subTest(method=method, payload=payload):
                    count, _ = self.execute(method, replacement=dict(payloadJson=payload), sent=dict(payloadJson=payload))
                    self.assertEqual(1, count)

    def test_null_payload_is_not_a_wildcard(self):
        for method in ('deleteExact', 'markFailureExact'):
            with self.subTest(method=method):
                count, _ = self.execute(method, sent=dict(payloadJson=None))
                self.assertEqual(0, count)


class TranslationTaskCompareAndSwapTests(unittest.TestCase):
    def test_replaced_device_rejects_old_delete_and_failure(self):
        dao = SOURCE.read_text().split('interface CategoryTranslationOutboxDao {', 1)[1].split('@Dao', 1)[0]
        queries = dict((name, sql) for sql, name in re.findall(r'@Query\(\s*"""(.*?)"""\s*\)\s*suspend fun (\w+)', dao, re.S))
        for method in ('deleteExact', 'markFailureExact'):
            with self.subTest(method=method), sqlite3.connect(':memory:') as db:
                db.execute("""CREATE TABLE category_translation_outbox(owner_user_id TEXT, category_id TEXT,
                    input_name TEXT, source_language TEXT, saved_updated_at TEXT, device_id TEXT,
                    attempt_count INTEGER, next_attempt_at_epoch_millis INTEGER, last_error TEXT)""")
                db.execute("INSERT INTO category_translation_outbox VALUES ('owner','category','name','vi','clock','new-device',0,0,NULL)")
                params = dict(ownerUserId='owner', categoryId='category', inputName='name', sourceLanguage='vi',
                              savedUpdatedAt='clock', deviceId='old-device', attemptCount=0, nextAttemptAtEpochMillis=99, errorCode='old')
                self.assertEqual(0, db.execute(queries[method], params).rowcount)


class OutboxProvenanceMigrationTests(unittest.TestCase):
    def test_actual_three_to_four_sql_preserves_payload_version_and_retry(self):
        schema_path = pathlib.Path(__file__).resolve().parents[1] / 'android/core/database/schemas/vn.com.quyln.mistia.core.database.MistiaDatabase/3.json'
        schema = json.loads(schema_path.read_text())['database']
        table = next(item for item in schema['entities'] if item['tableName'] == 'sync_outbox')
        body = SOURCE.read_text().split('val MIGRATION_3_4 =', 1)[1].split('val MIGRATION_', 1)[0]
        statements = re.findall(r'db\.execSQL\("([^"\n]+)"\)', body)
        self.assertTrue(statements)
        with sqlite3.connect(':memory:') as db:
            db.execute(table['createSql'].replace('${TABLE_NAME}', 'sync_outbox'))
            payload = '{"amount_minor":9007199254740993}'
            db.execute('INSERT INTO sync_outbox VALUES (?,?,?,?,?,?,?,?,?,?,?)',
                       ('owner','ledger_transactions','record','delete',payload,'clock',9007199254740993,'device',3,99,'network_io'))
            for statement in statements:
                db.execute(statement)
            self.assertEqual((payload,9007199254740993,3,99,'network_io',1), db.execute(
                'SELECT payload_json,base_version,attempt_count,next_attempt_at_epoch_millis,last_error,remote_identity_observed FROM sync_outbox').fetchone())


if __name__ == '__main__':
    unittest.main()
