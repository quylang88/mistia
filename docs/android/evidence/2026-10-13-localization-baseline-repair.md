# Shared localization baseline repair — 2026-10-13

Starting HEAD 82a9313 introduced two automatically extracted catalog entries:
an empty key without translations and `%@ %@` with only a new Vietnamese
translation. Neither key meets the shared dotted-key or vi/en/ja contract.

RED: `swift Scripts/generate-android-l10n.swift --check` reported
`Invalid localization key for Android:`; strict Swift codegen reported
`Invalid localization keys: , %@ %@.`.

Removed only those two untranslated automatic extraction entries. Existing
valid translations, iOS runtime source, and generated outputs are unchanged.
A temporary-catalog probe established that generated Swift differs only in its
source-path comment and Android generation remains identical.

GREEN: with `DEVELOPER_DIR=/Library/Developer/CommandLineTools`, the Android
localization check and strict Swift localization check both exit 0 using the
real catalog path. `git diff --check` passes. The 15-entity Android contract
check also passed during this session.

This restores the required generator gate; it does not claim xcstringstool
extraction auditing or device verification. No production call or deployment.
