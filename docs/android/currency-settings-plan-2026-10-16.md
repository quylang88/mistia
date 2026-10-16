# Currency settings slice94

Baseline c9563af0. Follow autonomous TXT execution; no deployment or cloud writes.

Swift sources: CurrencyLogic.swift89–190; SettingsView.swift386–705. Device settings default enabled JPY, primary JPY, manual mode and canonical JPY→VND165. Normalize codes/order; keep one enabled, constrain primary to enabled, fall back when disabling primary. Show rate controls with both enabled, source other enabled→primary, round display/canonical inverse to8 places. Invalid direct manual text remains editable; invalid inverse leaves prior canonical rate. Automatic mode uses cache; explicit refresh bypasses daily/07:00 throttling; delayed automatic completion must not override manual selection.

Implement model + device SharedPreferences store; runtime RED→GREEN. Add mode wrapper and explicit force refresh with network tests. Add localized UI/navigation and wire primary into transaction editor/configured rates globally. Native tests use isolated on-disk preferences/controlled rates: restart persistence/last-enabled/primary, direct/inverse/manual-auto/late response, reporting consumer. Test target36. Inspect light/dark enlarged-font screenshots. Independent read-only review against Swift, fix findings, full checks, archive executed artifacts, evidence and separate commit.

Every enabled-currency picker/aggregate consumer, imported currencies, broader RC and Samsung proof remain separate required slices, not completed by settings alone.
