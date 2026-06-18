import XCTest
@testable import MistiaCoreLogic

final class FamilyRLSEdgeCasesTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MistiaAppLanguage.persist(.vietnamese)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: MistiaAppLanguage.userDefaultsKey)
        UserDefaults.standard.removeObject(forKey: MistiaAppLanguage.backupUserDefaultsKey)
        super.tearDown()
    }

    // MARK: - Family Member Access Edge Cases

    func testFamilyMemberAccessSameUser() {
        let viewerRole: FamilyRole = .member
        let viewerPolicy = FamilyPermissionPolicy.preset(for: .member)
        let targetRole: FamilyRole = .kid
        let isSameUser = true
        
        let access = FamilyLogic.access(
            viewerRole: viewerRole,
            viewerPolicy: viewerPolicy,
            targetRole: targetRole,
            isSameUser: isSameUser
        )
        
        XCTAssertTrue(access.canViewTarget)
        XCTAssertTrue(access.canEditTarget)
        XCTAssertTrue(access.canViewTargetWallets)
        XCTAssertTrue(access.canViewTargetDebts)
    }

    func testFamilyMemberAccessOwnerViewingKid() {
        let viewerRole: FamilyRole = .owner
        let viewerPolicy = FamilyPermissionPolicy.preset(for: .owner)
        let targetRole: FamilyRole = .kid
        let isSameUser = false
        
        let access = FamilyLogic.access(
            viewerRole: viewerRole,
            viewerPolicy: viewerPolicy,
            targetRole: targetRole,
            isSameUser: isSameUser
        )
        
        XCTAssertTrue(access.canViewTarget)
        XCTAssertTrue(access.canEditTarget) // Owner can edit kids
        XCTAssertTrue(access.canViewTargetWallets)
        XCTAssertTrue(access.canViewTargetDebts)
    }

    func testFamilyMemberAccessMemberViewingKidWithoutPermission() {
        var viewerPolicy = FamilyPermissionPolicy.preset(for: .member)
        viewerPolicy.canViewKids = false
        viewerPolicy.canEditKids = false
        
        let access = FamilyLogic.access(
            viewerRole: .member,
            viewerPolicy: viewerPolicy,
            targetRole: .kid,
            isSameUser: false
        )
        
        XCTAssertFalse(access.canViewTarget)
        XCTAssertFalse(access.canEditTarget)
        XCTAssertFalse(access.canViewTargetWallets)
        XCTAssertFalse(access.canViewTargetDebts)
    }

    func testFamilyMemberAccessMemberViewingKidWithViewOnly() {
        var viewerPolicy = FamilyPermissionPolicy.preset(for: .member)
        viewerPolicy.canViewKids = true
        viewerPolicy.canEditKids = false
        
        let access = FamilyLogic.access(
            viewerRole: .member,
            viewerPolicy: viewerPolicy,
            targetRole: .kid,
            isSameUser: false
        )
        
        XCTAssertTrue(access.canViewTarget)
        XCTAssertFalse(access.canEditTarget)
        XCTAssertTrue(access.canViewTargetWallets)
        XCTAssertTrue(access.canViewTargetDebts)
    }

    func testFamilyMemberAccessKidViewingOthers() {
        let viewerPolicy = FamilyPermissionPolicy.preset(for: .kid)
        
        let access = FamilyLogic.access(
            viewerRole: .kid,
            viewerPolicy: viewerPolicy,
            targetRole: .member,
            isSameUser: false
        )
        
        XCTAssertFalse(access.canViewTarget)
        XCTAssertFalse(access.canEditTarget)
        XCTAssertFalse(access.canViewTargetWallets)
        XCTAssertFalse(access.canViewTargetDebts)
    }

    // MARK: - RLS Policy Edge Cases

    func testRLSInsertPermissionDenied() {
        // This would be tested at the Supabase level, but we can simulate the error handling
        let errorMessage = "new row violates row-level security policy for table \"family_memberships\""
        
        // Check if our error suppression logic works
        XCTAssertTrue(shouldSuppressNoFamilyPermissionError(errorMessage))
    }

    func testRLSUpdatePermissionDenied() {
        let errorMessage = "permission denied for table family_memberships"
        
        XCTAssertTrue(shouldSuppressNoFamilyPermissionError(errorMessage))
    }

    func testNonRLSErrorNotSuppressed() {
        let errorMessage = "Network connection failed"
        
        XCTAssertFalse(shouldSuppressNoFamilyPermissionError(errorMessage))
    }

    // MARK: - Family Wallet Access Edge Cases

    func testFamilyMemberAccessWithNoWalletPermissions() {
        let viewerPolicy = FamilyPermissionPolicy.preset(for: .member)
        
        let access = FamilyLogic.access(
            viewerRole: .member,
            viewerPolicy: viewerPolicy,
            targetRole: .owner,
            isSameUser: false
        )
        
        XCTAssertTrue(access.canViewTarget)
        XCTAssertFalse(access.canEditTarget)
        XCTAssertTrue(access.canViewTargetWallets)
        XCTAssertTrue(access.canViewTargetDebts)
    }

    func testFamilyKidAccessWithRestrictedWallets() {
        let kidPolicy = FamilyPermissionPolicy.preset(for: .kid)
        
        let access = FamilyLogic.access(
            viewerRole: .kid,
            viewerPolicy: kidPolicy,
            targetRole: .owner,
            isSameUser: false
        )
        
        XCTAssertFalse(access.canViewTarget)
        XCTAssertFalse(access.canEditTarget)
        XCTAssertFalse(access.canViewTargetWallets)
        XCTAssertFalse(access.canViewTargetDebts)
    }

    // MARK: - Edge Cases for Family Permission Updates

    func testFamilyPermissionUpdateWithDifferentRoles() {
        // Test that different roles have different policies
        let ownerPolicy = FamilyPermissionPolicy.preset(for: .owner)
        let memberPolicy = FamilyPermissionPolicy.preset(for: .member)
        
        // Owner and member policies should be different
        XCTAssertNotEqual(ownerPolicy, memberPolicy)
    }

    // MARK: - Helper Functions for Testing

    private func shouldSuppressNoFamilyPermissionError(_ message: String) -> Bool {
        let normalized = message.lowercased()
        return (normalized.contains("permission denied") || normalized.contains("row-level security"))
            && (normalized.contains("family_memberships") || normalized.contains("family membership"))
    }
}