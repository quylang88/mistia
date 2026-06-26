import XCTest

final class FamilyEventPermissionPolicyGuardTests: XCTestCase {
    func testLatestCanManageEventRequiresExplicitEventEditGrant() throws {
        let sql = try combinedMigrationSQL()
        let functionBody = try latestCreateOrReplaceBlock(
            named: "public.can_manage_event",
            in: sql
        )

        XCTAssertTrue(
            functionBody.contains("public.has_family_permission_grant(owner_user_id, 'event', null, 'edit')"),
            "Event editing must be guarded by the event edit permission, not by transaction permissions or participant membership."
        )
        XCTAssertFalse(
            functionBody.contains("public.settlement_participants"),
            "Being listed as an event participant must not grant edit/manage access to another member's event."
        )
        XCTAssertFalse(
            functionBody.contains("'transaction'"),
            "Event permissions must stay separate from transaction permissions."
        )
    }

    func testLatestSettlementGroupPoliciesUseEventPermissionsOnly() throws {
        let sql = try combinedMigrationSQL()
        let insertPolicy = try latestCreatePolicyBlock(
            named: "settlement_groups_access_insert",
            in: sql
        )
        let updatePolicy = try latestCreatePolicyBlock(
            named: "settlement_groups_access_update",
            in: sql
        )

        XCTAssertTrue(
            insertPolicy.contains("public.has_family_permission_grant(user_id, 'event', null, 'create')"),
            "Creating a member event must require that member's event create grant."
        )
        XCTAssertFalse(
            insertPolicy.contains("'transaction'"),
            "Creating an event must not be authorized by transaction create grants."
        )
        XCTAssertTrue(
            updatePolicy.contains("public.can_manage_event(user_id, id)"),
            "Editing a member event must route through the explicit event edit gate."
        )
        XCTAssertFalse(
            updatePolicy.contains("'transaction'"),
            "Editing an event must not be authorized by transaction edit grants."
        )
    }

    func testSettlementEditorMutationsCheckEventPermission() throws {
        let source = try settlementSheetsSource()

        let saveSharedExpense = try functionBody(named: "saveSharedExpense", in: source)
        XCTAssertTrue(
            saveSharedExpense.contains("guardSharedExpenseEventPermission(ownerUserID: ownerUserID, scope: requiredPermissionScope)"),
            "Saving an event must re-check event create/edit permission inside the sheet, not only before presentation."
        )

        for functionName in [
            "detachBill",
            "persistLinkedBillUpdate",
            "archiveSharedExpenseEvent",
            "resetCompletedSharedExpenseToPreparing"
        ] {
            let body = try functionBody(named: functionName, in: source)
            XCTAssertTrue(
                body.contains("guardSharedExpenseEventPermission(ownerUserID: ownerUserID, scope: .edit)"),
                "\(functionName) mutates event state and must require event edit permission."
            )
        }
    }

    private func combinedMigrationSQL() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let repoRoot = testFile.deletingLastPathComponent().deletingLastPathComponent()
        let migrationsURL = repoRoot
            .appendingPathComponent("supabase")
            .appendingPathComponent("migrations")
        let migrationURLs = try FileManager.default
            .contentsOfDirectory(
                at: migrationsURL,
                includingPropertiesForKeys: nil
            )
            .filter { $0.pathExtension == "sql" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        return try migrationURLs
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n\n")
    }

    private func latestCreateOrReplaceBlock(
        named functionName: String,
        in sql: String
    ) throws -> String {
        let marker = "create or replace function \(functionName)"
        guard let range = sql.range(of: marker, options: [.caseInsensitive, .backwards]) else {
            XCTFail("Missing \(marker)")
            return ""
        }
        return String(sql[range.lowerBound...]).components(separatedBy: "$$;").first ?? ""
    }

    private func latestCreatePolicyBlock(
        named policyName: String,
        in sql: String
    ) throws -> String {
        let marker = "create policy \"\(policyName)\""
        guard let range = sql.range(of: marker, options: [.caseInsensitive, .backwards]) else {
            XCTFail("Missing \(marker)")
            return ""
        }
        let tail = String(sql[range.lowerBound...])
        if let semicolon = tail.firstIndex(of: ";") {
            return String(tail[...semicolon])
        }
        return tail
    }

    private func settlementSheetsSource() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let repoRoot = testFile.deletingLastPathComponent().deletingLastPathComponent()
        let sourceURL = repoRoot
            .appendingPathComponent("Mistia")
            .appendingPathComponent("Features")
            .appendingPathComponent("Transactions")
            .appendingPathComponent("SettlementSheets.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    private func functionBody(named functionName: String, in source: String) throws -> String {
        let marker = "private func \(functionName)("
        guard let range = source.range(of: marker) else {
            XCTFail("Missing \(marker)")
            return ""
        }
        let tail = String(source[range.lowerBound...])
        guard let nextFunction = tail.range(of: "\n    private func ", options: [], range: tail.index(after: tail.startIndex)..<tail.endIndex) else {
            return tail
        }
        return String(tail[..<nextFunction.lowerBound])
    }
}
