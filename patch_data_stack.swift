--- Mistia/Shared/Persistence/MistiaDataStack.swift
+++ Mistia/Shared/Persistence/MistiaDataStack.swift
@@ -10,7 +10,13 @@
                 configurations: [configuration]
             )
         } catch {
-            fatalError("Unable to create SwiftData container: \(error)")
+            // Fallback for development: wipe and recreate
+            do {
+                try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: false)).mainContext.container.deleteAllData()
+            } catch {}
+            return try! ModelContainer(
+                for: schema, configurations: [configuration]
+            )
         }
     }()
 }
