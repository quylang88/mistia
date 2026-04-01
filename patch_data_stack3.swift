--- Mistia/Shared/Persistence/MistiaDataStack.swift
+++ Mistia/Shared/Persistence/MistiaDataStack.swift
@@ -15,7 +15,9 @@
         } catch {
             // Fallback for development: wipe and recreate
             do {
-                try? ModelContainer(for: schema, configurations: [configuration]).deleteAllData()
+                if let url = configuration.url {
+                    try? FileManager.default.removeItem(at: url)
+                }
             } catch {}
             let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
             return try! ModelContainer(for: schema, configurations: [config])
