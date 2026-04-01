--- Mistia/Shared/Persistence/MistiaDataStack.swift
+++ Mistia/Shared/Persistence/MistiaDataStack.swift
@@ -14,9 +14,8 @@
         } catch {
             // Fallback for development: wipe and recreate
             do {
-                try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: false)).mainContext.container.deleteAllData()
+                try? ModelContainer(for: schema, configurations: [configuration]).deleteAllData()
             } catch {}
-            return try! ModelContainer(
-                for: schema, configurations: [configuration]
-            )
+            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
+            return try! ModelContainer(for: schema, configurations: [config])
         }
     }()
 }
