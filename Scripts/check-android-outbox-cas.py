#!/usr/bin/env python3
"""Execute the production Room outbox predicates against SQLite (no device needed)."""
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
                   deviceId='device', attemptCount=0)
        sent_values = row | (sent or {})
        row.update(replacement or {})
        db = sqlite3.connect(':memory:')
        self.addCleanup(db.close)
        db.execute('''CREATE TABLE sync_outbox(owner_user_id TEXT, entity TEXT, record_id TEXT,
            kind TEXT, payload_json TEXT, modified_at TEXT, base_version INTEGER, device_id TEXT,
            attempt_count INTEGER, next_attempt_at_epoch_millis INTEGER, last_error TEXT)''')
        db.execute('INSERT INTO sync_outbox VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, NULL)', tuple(row.values()))
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


if __name__ == '__main__':
    unittest.main()
