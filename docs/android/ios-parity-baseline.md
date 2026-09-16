# iOS → Android parity baseline

This matrix is the acceptance inventory for the independent Android runtime. “Same” means the same business result, Supabase record, owner/subject scope and derived balance; presentation may follow Android-native conventions.

| Area | Required states and side effects | APK gate | Current Android state |
|---|---|---:|---|
| Authentication | signed out, loading, invalid credentials, email confirmation, reset, Google token exchange, restored/expired session | 0 | email/password, reset API, restore/refresh and Google exchange contract implemented; Google Credential UI pending |
| Initial sync | empty/empty, cloud-only, device-only, merge safely, use device, use cloud, retry, offline | 0–1 | fresh-install cloud pull and durable retry implemented; write choices remain gated |
| Overview | loading, empty, populated, dark mode, recent transactions, upcoming items, budget watchlist | 0–2 | read-only entity summary and recent transactions implemented |
| Transactions | expense, income, internal transfer, debt, family transfer, FX, cleared optional fields, archive/delete | 0–3 | cloud list read-only implemented |
| Planning | budgets, goals, bills, installments, cards, due occurrence, paid/skipped/archive | 0–2 | read-only counts implemented |
| Management | wallets, cards, categories, hierarchy, balance adjustment, archive, data tools | 0–RC | wallet/category read-only and sync/account actions implemented |
| Family | family state, membership, roles, invites/deep links, permission requests/grants, notifications | 0–3 | family read models and deep-link routing implemented |
| Investment resale | channels, assets, product images, buy/sell, independent unit FIFO, cash postings | 0–4 | asset/trade read-only implemented |
| Notifications | local due reminders, permission, family inbox, remote sign-out | 2–RC | Android permission contract scaffolded |
| Security/data | app lock, account isolation, Keystore, backup V1, export/import/delete | 0–RC | session/device ID in Keystore and owner-isolated Room mirror implemented |

## Baseline capture checklist

For every iOS flow, capture light and dark appearances at default and large Dynamic Type for: initial/loading, empty, populated, validation error, network error, destructive confirmation and success. Store approved references under `docs/android/baseline/<flow>/<appearance>/` and never include real financial or account data.

Android visual gates use a Pixel at API 26, a Pixel at API 31+, the current Android API and one physical Samsung device. Functional parity is verified across an iPhone and Android using the same test account through create/edit/delete/clear/archive and at least three automatic sync cycles.
