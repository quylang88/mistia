import SwiftUI
import SwiftData
import UIKit

enum MistiaTab: String, CaseIterable, Hashable {
  case overview
  case transactions
  case planning
  case settings

  var title: String {
    switch self {
    case .overview:
      L10n.app.roottab.overview
    case .transactions:
      L10n.app.roottab.transactions
    case .planning:
      L10n.app.roottab.planning
    case .settings:
      L10n.app.roottab.manage
    }
  }

  var outlineSystemImage: String {
    switch self {
    case .overview:
      "house"
    case .transactions:
      "arrow.left.arrow.right.circle"
    case .planning:
      "flag"
    case .settings:
      "square.stack"
    }
  }

  var selectedSystemImage: String {
    switch self {
    case .overview:
      "house.fill"
    case .transactions:
      "arrow.left.arrow.right.circle.fill"
    case .planning:
      "flag.fill"
    case .settings:
      "square.stack.fill"
    }
  }

  var systemImage: String {
    selectedSystemImage
  }

  func systemImage(isSelected: Bool) -> String {
    if isSelected {
      selectedSystemImage
    } else {
      outlineSystemImage
    }
  }

  var accent: Color {
    switch self {
    case .overview:
      .blue
    case .transactions:
      .cyan
    case .planning:
      Color(red: 0.24, green: 0.45, blue: 0.96)
    case .settings:
      Color(red: 0.43, green: 0.23, blue: 0.76)
    }
  }
}

struct RootTabView: View {
  @Environment(\.colorScheme) private var colorScheme
  @Environment(SessionStore.self) private var sessionStore
  @Environment(FamilyContextStore.self) private var familyContextStore
  @Environment(MistiaUIState.self) private var uiState
  @Query(filter: #Predicate<LedgerWallet> { $0.deletedAt == nil && !$0.isArchived })
  private var storedWallets: [LedgerWallet]
  @Query private var ownershipScopes: [OwnedRecordScope]
  @AppStorage(MistiaAppStorageKey.appearanceMode) private var appearanceModeRawValue =
    MistiaAppearanceMode.automatic.rawValue
  @AppStorage(MistiaAppStorageKey.appLanguage) private var appLanguageRawValue = ""
  @AppStorage(MistiaAppStorageKey.hideQuickCreate) private var hideQuickCreate = false
  @AppStorage(MistiaAppStorageKey.mistiaShortcutEnabled) private var mistiaShortcutEnabled = false
  @AppStorage(MistiaAppStorageKey.mistiaShortcutKind) private var shortcutKindRawValue =
    MistiaShortcutKind.backupRestore.rawValue
  @AppStorage(MistiaAppStorageKey.mistiaShortcutMemberUserID) private var shortcutMemberUserIDRawValue = ""
  @State private var selectedTab: MistiaTab = .overview
  @State private var isQuickCreateMenuVisible = false
  @State private var isQuickCreateMenuExpanded = false
  @State private var activeSheet: RootSheet?
  @State private var quickCreateButtonFrame: CGRect = .zero
  @State private var quickCreateAnchorFrame: CGRect = .zero
  @State private var quickCreateDragOffset: CGFloat = 0
  @State private var isDraggingQuickCreate = false
  @State private var isSyncingShortcut = false
  @State private var isRefreshingQuickCreateAccess = false
  @State private var quickCreateAccessAlert: RootQuickCreateAccessAlert?
  @State private var showsReceiptSourceDialog = false

  private let quickCreateMenuAnimation = Animation.spring(response: 0.34, dampingFraction: 0.84)
  private let quickCreateMenuDuration = 0.28

  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .bottomTrailing) {
        MistiaNativeTabShell(
          selectedTab: $selectedTab,
          appearanceMode: appearanceMode,
          appLanguage: appLanguage,
          hidesQuickCreate: hideQuickCreate || uiState.isQuickCreateHidden || isQuickCreateMenuVisible,
          hidesTabBar: uiState.isTabBarHidden,
          showsShortcutTab: mistiaShortcutEnabled && !shouldHideShortcutTabInCurrentContext,
          isShortcutSyncing: isSyncingShortcut && !isPinnedShortcutDisabled,
          isShortcutDisabled: isPinnedShortcutDisabled,
          shortcutDisabledAccessibilityHint: shortcutDisabledAccessibilityHint,
          shortcutPresentation: shortcutResolution.presentation,
          onShortcutTap: handlePinnedShortcutTap,
          onQuickCreateTap: toggleQuickCreateMenu,
          onQuickCreateFrameChange: { frame in
            if !isQuickCreateMenuVisible {
              quickCreateButtonFrame = frame
            }
          }
        )
        .ignoresSafeArea()

        NotificationBadgeObserver()

        if isQuickCreateMenuVisible, quickCreateAnchorFrame.width > 0 {
          Color.black
            .opacity(isQuickCreateMenuExpanded ? (colorScheme == .dark ? 0.18 : 0.08) : 0)
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture(perform: dismissQuickCreateMenu)
            .animation(quickCreateMenuAnimation, value: isQuickCreateMenuExpanded)

          MistiaQuickCreateMenu(
            isExpanded: isQuickCreateMenuExpanded,
            width: proxy.size.width - 40, // Match tab bar margins (20pt each side)
            expandedHeight: quickCreateExpandedHeight,
            destinations: quickCreateDestinations,
            dragOffset: $quickCreateDragOffset,
            isDragging: $isDraggingQuickCreate,
            onDismiss: dismissQuickCreateMenu
          ) { destination in
            presentQuickCreateSheet(for: destination)
          }
          .position(quickCreateMenuPosition(in: proxy))
          .offset(y: quickCreateDragOffset)
          .scaleEffect(isQuickCreateMenuExpanded ? 1 : 0.9, anchor: .bottomTrailing)
          .opacity(isQuickCreateMenuExpanded ? 1 : 0)
          .offset(y: isQuickCreateMenuExpanded ? 0 : 10)
          .animation(quickCreateMenuAnimation, value: isQuickCreateMenuExpanded)
        }
      }
      .sheet(item: $activeSheet) { sheet in
        switch sheet {
        case .quickCreate(let destination, let receiptInitialSource):
          TransactionEditorSheet(target: quickCreateTarget(for: destination, receiptInitialSource: receiptInitialSource)) { completion in
            if completion == .savedDraft {
              self.selectedTab = .transactions
            }
          }
            .presentationDetents(destination == .note ? [.medium, .large] : [.large])
            .presentationDragIndicator(.hidden)
        case .settlement(let target):
          SettlementEditorSheet(target: target)
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
        }
      }
      .task(id: shortcutNormalizationKey) {
        persistShortcutSelectionIfNeeded(shortcutResolution.selection)
      }
      .onChange(of: hideQuickCreate) { _, newValue in
        if newValue {
          dismissQuickCreateMenu()
        }
      }
      .onChange(of: selectedTab) { _, _ in
        dismissQuickCreateMenu()
      }
      .onChange(of: familyContextStore.pendingFamilyOverviewRoute?.id) { _, familyID in
        guard familyID != nil else { return }
        dismissQuickCreateMenu()
        familyContextStore.activateFamilyHome()
        openManagementRoute(.familyOverview)
        familyContextStore.clearFamilyOverviewPresentationRequest()
      }
      .onChange(of: uiState.tabSelectionRequest?.id) { _, requestID in
        guard requestID != nil, let request = uiState.tabSelectionRequest else { return }
        dismissQuickCreateMenu()
        selectedTab = request.tab
        uiState.clearTabSelectionRequest(id: request.id)
      }
      .onChange(of: uiState.quickCreateMenuRequestID) { _, requestID in
        guard requestID != nil else { return }
        presentQuickCreateMenu()
      }
      .alert(item: $quickCreateAccessAlert) { alert in
        Alert(
          title: Text(alert.title),
          message: Text(alert.message),
          dismissButton: .default(Text(L10n.common.ok))
        )
      }
      .confirmationDialog(
        L10n.app.roottab.scanReceipt,
        isPresented: $showsReceiptSourceDialog,
        titleVisibility: .visible
      ) {
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
          Button(L10n.app.roottab.takePhoto) {
            activeSheet = .quickCreate(.receipt, .camera)
          }
        }

        Button(L10n.app.roottab.chooseFromPhotos) {
          activeSheet = .quickCreate(.receipt, .photoLibrary)
        }

        Button(L10n.common.cancel, role: .cancel) {}
      } message: {
        Text(L10n.app.roottab.chooseAReceiptImageSourceForAI)
      }
    }
  }

  private var appearanceMode: MistiaAppearanceMode {
    MistiaAppearanceMode(rawValue: appearanceModeRawValue) ?? .automatic
  }

  private var appLanguage: MistiaAppLanguage {
    MistiaAppLanguage.resolve(storedRawValue: appLanguageRawValue)
  }

  private var shortcutAccent: Color {
    colorScheme == .dark ? MistiaAccent.lightPurple.color : MistiaAccent.purple.color
  }

  private var storedShortcutSelection: MistiaShortcutSelection {
    MistiaShortcutSelection(
      storedKindRawValue: shortcutKindRawValue,
      storedMemberUserIDRawValue: shortcutMemberUserIDRawValue
    )
  }

  private var effectiveShortcutSelection: MistiaShortcutSelection {
    storedShortcutSelection
  }

  private var shortcutInput: MistiaShortcutResolveInput {
    MistiaShortcutResolveInput(
      currentUserInitials: sessionStore.summary?.initials ?? "MI",
      currentUserAvatarURL: sessionStore.summary?.avatarURL,
      familyID: familyContextStore.family?.id,
      canOpenFamilyHome: familyContextStore.canPresentFamilyHome,
      members: familyContextStore.members.map { member in
        MistiaShortcutMemberContext(
          userID: member.userID,
          displayName: member.displayName,
          initials: String(member.displayName.prefix(2)).uppercased(),
          avatarURL: member.avatarURL,
          canView: familyContextStore.capabilities(for: member).canViewTarget,
          isCurrentUser: member.userID == sessionStore.signedInUserID
        )
      }
    )
  }

  private var shortcutResolution: MistiaShortcutResolution {
    MistiaShortcutLogic.resolve(
      selection: effectiveShortcutSelection,
      input: shortcutInput
    )
  }

  private var hidesBillFeaturesForMemberContext: Bool {
    false
  }

  private var shouldHideShortcutTabInCurrentContext: Bool {
    false
  }

  private var isPinnedShortcutDisabled: Bool {
    shortcutResolution.presentation.action.requiresRemoteAction && !sessionStore.canPerformRemoteActions
  }

  private var shortcutDisabledAccessibilityHint: String? {
    guard isPinnedShortcutDisabled else { return nil }
    return sessionStore.remoteUnavailableReason
      ?? L10n.shared.session.session.noNetworkConnectionReconnectToSyncEdit
  }

  private var quickCreateDestinations: [MistiaQuickCreateDestination] {
    var destinations: [MistiaQuickCreateDestination] = [.expense, .income, .transfer, .resale, .sharedExpense]
    destinations.append(.receipt)
    return destinations
  }

  private var quickCreateExpandedHeight: CGFloat {
    MistiaQuickCreateMenu.expandedHeight(for: quickCreateDestinations)
  }

  private var shortcutNormalizationKey: String {
    let memberFingerprint = familyContextStore.members
      .map { member in
        let canView = familyContextStore.capabilities(for: member).canViewTarget ? "1" : "0"
        let isCurrent = member.userID == sessionStore.signedInUserID ? "1" : "0"
        return "\(member.userID.uuidString.lowercased()):\(canView):\(isCurrent)"
      }
      .sorted()
      .joined(separator: ",")

    let effective = effectiveShortcutSelection
    return [
      effective.storedKindRawValue,
      effective.storedMemberUserIDRawValue,
      familyContextStore.family?.id.uuidString.lowercased() ?? "none",
      familyContextStore.canPresentFamilyHome ? "1" : "0",
      sessionStore.signedInUserID?.uuidString.lowercased() ?? "none",
      memberFingerprint
    ].joined(separator: "|")
  }

  private func toggleQuickCreateMenu() {
    if isQuickCreateMenuVisible {
      dismissQuickCreateMenu()
    } else {
      presentQuickCreateMenu()
    }
  }

  private func dismissQuickCreateMenu() {
    guard isQuickCreateMenuVisible else { return }

    withAnimation(quickCreateMenuAnimation) {
      isQuickCreateMenuExpanded = false
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + quickCreateMenuDuration) {
      guard !isQuickCreateMenuExpanded else { return }
      isQuickCreateMenuVisible = false
    }
  }

  private func presentQuickCreateSheet(for destination: MistiaQuickCreateDestination) {
    dismissQuickCreateMenu()
    DispatchQueue.main.asyncAfter(deadline: .now() + quickCreateMenuDuration) {
      if destination == .receipt {
        showsReceiptSourceDialog = true
      } else if let settlementTarget = destination.settlementTarget {
        selectedTab = .transactions
        activeSheet = .settlement(settlementTarget)
      } else {
        activeSheet = .quickCreate(destination, nil)
      }
    }
  }

  private func presentQuickCreateMenu() {
    guard !hideQuickCreate else { return }
    guard quickCreateButtonFrame.width > 0 else { return }
    if familyContextStore.isViewingOtherMemberContext && !hasUsableWalletForQuickCreateSubject {
      guard !isRefreshingQuickCreateAccess else { return }
      isRefreshingQuickCreateAccess = true
      Task { @MainActor in
        let didRefresh = await familyContextStore.refresh(sessionStore: sessionStore)
        await Task.yield()
        isRefreshingQuickCreateAccess = false
        if didRefresh && hasUsableWalletForQuickCreateSubject {
          openQuickCreateMenu()
          return
        }

        quickCreateAccessAlert = RootQuickCreateAccessAlert(
          title: L10n.app.roottab.noWalletUseAccess,
          message: familyContextStore.lastErrorMessage ?? L10n.app.roottab.youDoNotHaveUseAccessTo
        )
      }
      return
    }

    openQuickCreateMenu()
  }

  private func openQuickCreateMenu() {
    guard !hideQuickCreate else { return }
    guard quickCreateButtonFrame.width > 0 else { return }
    if familyContextStore.isViewingOtherMemberContext && !hasUsableWalletForQuickCreateSubject {
      quickCreateAccessAlert = RootQuickCreateAccessAlert(
        title: L10n.app.roottab.noWalletUseAccess,
        message: L10n.app.roottab.youDoNotHaveUseAccessTo
      )
      return
    }

    quickCreateAnchorFrame = quickCreateButtonFrame
    isQuickCreateMenuVisible = true
    isQuickCreateMenuExpanded = false

    DispatchQueue.main.async {
      withAnimation(quickCreateMenuAnimation) {
        isQuickCreateMenuExpanded = true
      }
    }
  }

  private func handlePinnedShortcutTap() {
    guard !isPinnedShortcutDisabled else {
      isSyncingShortcut = false
      return
    }

    dismissQuickCreateMenu()

    switch shortcutResolution.presentation.action {
    case .backupRestore:
      openManagementRoute(.backupRestore)

    case .archivedItems:
      openManagementRoute(.archivedItems)

    case .familyOverview:
      familyContextStore.activateFamilyHome()
      openManagementRoute(.familyOverview)
      Task { @MainActor in
        await familyContextStore.refreshLatest(
          sessionStore: sessionStore,
          source: .familyOverview
        )
      }

    case .memberOverview(let userID):
      guard let member = familyContextStore.members.first(where: { $0.userID == userID }) else {
        openManagementRoute(.backupRestore)
        return
      }

      familyContextStore.activateMemberView(member)
      selectedTab = .overview
      Task { @MainActor in
        await familyContextStore.refreshMemberFinance(
          sessionStore: sessionStore,
          memberUserID: member.userID
        )
      }

    case .receiptScan:
      activeSheet = .quickCreate(.receipt, .cameraPreferred)

    case .syncNow:
      guard !isSyncingShortcut else { return }
      isSyncingShortcut = true
      Task { @MainActor in
        let _ = await sessionStore.syncNow(isManual: true)
        isSyncingShortcut = false
      }
    }
  }

  private func openManagementRoute(_ destination: MistiaManagementNavigationDestination) {
    selectedTab = .settings
    Task { @MainActor in
      await Task.yield()
      uiState.requestManagementNavigation(destination)
    }
  }

  private func persistShortcutSelectionIfNeeded(_ selection: MistiaShortcutSelection) {
    // Chỉ persist khi selection được resolve GIỐNG với stored (valid).
    // Nếu resolve fallback về profile → KHÔNG persist ngược lại.
    let stored = storedShortcutSelection
    guard stored == selection else { return }

    shortcutKindRawValue = selection.storedKindRawValue
    shortcutMemberUserIDRawValue = selection.storedMemberUserIDRawValue
  }

  private func quickCreateTarget(
    for destination: MistiaQuickCreateDestination,
    receiptInitialSource: TransactionReceiptInitialSource?
  ) -> TransactionEditorTarget {
    let subjectUserID = quickCreateSubjectUserID
    switch destination {
    case .expense:
      return TransactionEditorTarget(initialKind: .expense, subjectUserIDOverride: subjectUserID)
    case .income:
      return TransactionEditorTarget(initialKind: .income, subjectUserIDOverride: subjectUserID)
    case .transfer:
      return TransactionEditorTarget(initialKind: .transfer, subjectUserIDOverride: subjectUserID)
    case .receipt:
      return TransactionEditorTarget(
        initialKind: .expense,
        subjectUserIDOverride: subjectUserID,
        receiptInitialSource: receiptInitialSource,
        receiptPersistencePolicy: receiptPersistencePolicy(for: subjectUserID)
      )
    case .note:
      return TransactionEditorTarget(initialKind: .expense, quickCapture: true, subjectUserIDOverride: subjectUserID)
    case .resale, .sharedExpense:
      fatalError("Settlement destinations are presented with SettlementEditorSheet.")
    }
  }

  private var quickCreateSubjectUserID: UUID? {
    if familyContextStore.isViewingOtherMemberContext {
      return familyContextStore.selectedSubjectUserID
    }
    return sessionStore.activeLocalProfileUserID
  }

  private func receiptPersistencePolicy(for subjectUserID: UUID?) -> TransactionReceiptPersistencePolicy {
    TransactionReceiptPersistencePolicy.policy(
      ownerUserID: subjectUserID,
      activeLocalProfileUserID: sessionStore.activeLocalProfileUserID
    )
  }

  private var hasUsableWalletForQuickCreateSubject: Bool {
    guard let subjectUserID = quickCreateSubjectUserID else { return false }
    let ownerMap = MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .wallet)
    return storedWallets.contains { wallet in
      let ownerUserID = ownerMap[wallet.id] ?? sessionStore.activeLocalProfileUserID
      guard ownerUserID == subjectUserID else { return false }
      if ownerUserID == sessionStore.activeLocalProfileUserID {
        return true
      }
      return familyContextStore.canUseWallet(walletID: wallet.id, ownerUserID: ownerUserID)
    }
  }

  private func quickCreateMenuPosition(in proxy: GeometryProxy) -> CGPoint {
    let width = isQuickCreateMenuExpanded
      ? proxy.size.width - 40 // Match tab bar margins
      : MistiaQuickCreateMenu.collapsedSize
    let height = isQuickCreateMenuExpanded
      ? quickCreateExpandedHeight
      : MistiaQuickCreateMenu.collapsedSize

    // Anchored to the center but width matches tab bar area
    let x = isQuickCreateMenuExpanded ? proxy.size.width / 2 : (quickCreateAnchorFrame.maxX - (width / 2))
    
    let safeAreaOffset = proxy.safeAreaInsets.top
    let y = quickCreateAnchorFrame.maxY - (height / 2) - safeAreaOffset - 2 // Moved closer to tab bar

    return CGPoint(x: x, y: y)
  }
}

private enum RootSheet: Identifiable {
  case quickCreate(MistiaQuickCreateDestination, TransactionReceiptInitialSource?)
  case settlement(SettlementEditorTarget)

  var id: String {
    switch self {
    case .quickCreate(let destination, let receiptInitialSource):
      "quick-create-\(destination.rawValue)-\(receiptInitialSource?.rawValue ?? "none")"
    case .settlement(let target):
      "settlement-\(target.rawValue)"
    }
  }
}

private struct RootQuickCreateAccessAlert: Identifiable {
  let id = UUID()
  let title: String
  let message: String
}

private struct NotificationBadgeObserver: View {
  @Environment(SessionStore.self) private var sessionStore
  @Environment(\.modelContext) private var modelContext
  @Query private var rows: [AppNotificationRecord]

  var body: some View {
    Color.clear
      .frame(width: 0, height: 0)
      .onChange(of: rows) { _, _ in
        MistiaNotificationStore.updateAppBadgeCount(
          in: modelContext,
          userID: sessionStore.activeLocalProfileUserID
        )
      }
      .onAppear {
        MistiaNotificationStore.updateAppBadgeCount(
          in: modelContext,
          userID: sessionStore.activeLocalProfileUserID
        )
      }
  }
}

private enum MistiaQuickCreateDestination: String, CaseIterable, Identifiable {
  case expense
  case income
  case transfer
  case resale
  case sharedExpense
  case receipt
  case note

  var id: String { rawValue }

  var title: String {
    switch self {
    case .expense:
      L10n.app.roottab.expense
    case .income:
      L10n.app.roottab.income
    case .transfer:
      L10n.app.roottab.transfer
    case .resale:
      L10n.transactions.settlement.addResale
    case .sharedExpense:
      L10n.transactions.settlement.addSharedExpense
    case .receipt:
      L10n.app.roottab.scanReceipt
    case .note:
      L10n.app.roottab.quickNote
    }
  }

  var subtitle: String {
    switch self {
    case .expense:
      L10n.app.roottab.saveAnExpenseFromAPersonalWallet
    case .income:
      L10n.app.roottab.recordIncomeToUpdateYourBalance
    case .transfer:
      L10n.app.roottab.moveMoneyInternallyOrTrackDebt
    case .resale:
      L10n.transactions.settlement.resaleQuickCreateSubtitle
    case .sharedExpense:
      L10n.transactions.settlement.sharedExpenseQuickCreateSubtitle
    case .receipt:
      L10n.app.roottab.chooseCameraOrPhotoUploadForAI
    case .note:
      L10n.app.roottab.captureAmountAndTypeFirstThenComplete
    }
  }

  var placeholderMessage: String {
    switch self {
    case .expense:
      L10n.app.roottab.theExpenseFlowWillConnectFromThis
    case .income:
      L10n.app.roottab.theIncomeFlowWillConnectFromThis
    case .transfer:
      L10n.app.roottab.transfersBetweenSourcesWillBeConnectedHere
    case .resale:
      L10n.transactions.settlement.resaleQuickCreateSubtitle
    case .sharedExpense:
      L10n.transactions.settlement.sharedExpenseQuickCreateSubtitle
    case .receipt:
      L10n.app.roottab.receiptScanOpensTheTransactionModalAnd
    case .note:
      L10n.app.roottab.quickCaptureIsForUltraLightEntries
    }
  }

  var systemImage: String {
    switch self {
    case .expense:
      "arrow.up.right"
    case .income:
      "arrow.down.left"
    case .transfer:
      "arrow.left.arrow.right"
    case .resale:
      "cart.badge.clock"
    case .sharedExpense:
      "person.3.sequence"
    case .receipt:
      "doc.viewfinder"
    case .note:
      "square.and.pencil"
    }
  }

  var accent: Color {
    Color(red: 0.43, green: 0.23, blue: 0.76)
  }

  var settlementTarget: SettlementEditorTarget? {
    switch self {
    case .resale:
      return .resale
    case .sharedExpense:
      return .sharedExpense
    case .expense, .income, .transfer, .receipt, .note:
      return nil
    }
  }
}

private struct MistiaQuickCreateMenu: View {
  static let collapsedSize: CGFloat = 44
  static let defaultExpandedHeight: CGFloat = 318 // Matched to menuHeight

  @Environment(\.colorScheme) private var colorScheme
  let isExpanded: Bool
  let width: CGFloat
  let expandedHeight: CGFloat
  let destinations: [MistiaQuickCreateDestination]
  @Binding var dragOffset: CGFloat
  @Binding var isDragging: Bool
  let onDismiss: () -> Void
  let onSelect: (MistiaQuickCreateDestination) -> Void

  static func expandedHeight(for destinations: [MistiaQuickCreateDestination]) -> CGFloat {
    max(262, defaultExpandedHeight - CGFloat(4 - destinations.count) * 54)
  }

  private var collapsedTint: Color {
    Color(red: 0.43, green: 0.23, blue: 0.76).opacity(colorScheme == .dark ? 0.18 : 0.12)
  }

  private var cornerRadius: CGFloat {
    isExpanded ? 30 : 22
  }

  private var menuHeight: CGFloat {
    isExpanded ? expandedHeight : Self.collapsedSize
  }

  private var appPurple: Color {
    Color(red: 0.43, green: 0.23, blue: 0.76)
  }

  private var lightPurpleAccent: Color {
    Color(red: 0.88, green: 0.78, blue: 1.0) // Matched to "sao kê" button foreground
  }

  var body: some View {
    ZStack(alignment: .bottomTrailing) {
      if isExpanded {
        VStack(spacing: 0) {
          VStack(spacing: 0) {
            ForEach(Array(destinations.enumerated()), id: \.element.id) { index, destination in
              Button {
                onSelect(destination)
              } label: {
                MistiaQuickCreateMenuRow(destination: destination)
                  .frame(maxWidth: .infinity, alignment: .leading)
              }
              .buttonStyle(PlainButtonStyle())
              
              if index < destinations.count - 1 {
                Divider()
                  .background(Color.white.opacity(0.06))
                  .padding(.leading, 68)
                  .padding(.trailing, 20)
              }
            }
          }
          .padding(.top, 8) 
          
          Spacer(minLength: 2) // Even smaller gap

          // Bottom prominent button: Quick Note (Ghi nhanh)
          Button {
            onSelect(.note)
          } label: {
            HStack(spacing: 8) {
              Image(systemName: MistiaQuickCreateDestination.note.systemImage)
                .font(.system(size: 14, weight: .bold))
              
              Text(MistiaQuickCreateDestination.note.title.uppercased())
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .kerning(0.8)
            }
            .foregroundStyle(lightPurpleAccent)
            .frame(maxWidth: .infinity) // Make it full-width
            .padding(.vertical, 6)
          }
          .buttonStyle(.glassProminent)
          .buttonBorderShape(.capsule)
          .tint(appPurple)
          .padding(.horizontal, 20)
          .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }

      Image(systemName: "plus")
        .font(.system(size: 20, weight: .semibold, design: .rounded))
        .foregroundStyle(Color(red: 0.75, green: 0.55, blue: 1.0))
        .opacity(isExpanded ? 0 : 1)
        .scaleEffect(isExpanded ? 0.72 : 1)
        .frame(width: Self.collapsedSize, height: Self.collapsedSize)
        .background {
          Circle()
            .fill(Color(red: 0.65, green: 0.45, blue: 0.98).opacity(0.25))
            .opacity(isExpanded ? 0 : 1)
            .scaleEffect(isExpanded ? 0.72 : 1)
        }
    }
    .frame(
      width: isExpanded ? width : Self.collapsedSize,
      height: menuHeight,
      alignment: .bottomTrailing
    )
    .background {
      if isExpanded {
        ZStack {
          RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color(white: 0.12)) // Dark background like the image
          
          RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(.white.opacity(0.08), lineWidth: 1)
        }
      } else {
        MistiaRoundedGlassBackground(
          cornerRadius: cornerRadius,
          tint: collapsedTint,
          interactive: true
        )
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    .shadow(color: .black.opacity(colorScheme == .dark ? 0.22 : 0.08), radius: isDragging ? 30 : 22, y: isDragging ? 20 : 12)
    .scaleEffect(isDragging ? 1.02 : 1.0)
    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isDragging)
    .allowsHitTesting(isExpanded)
    .gesture(
      DragGesture(minimumDistance: 0)
        .onChanged { value in
          if !isDragging && value.translation.height != 0 {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            isDragging = true
          }
          dragOffset = value.translation.height
        }
        .onEnded { value in
          let velocity = value.predictedEndLocation.y - value.location.y
          if value.translation.height > 100 || velocity > 500 {
            onDismiss()
          }
          
          withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            dragOffset = 0
            isDragging = false
          }
        }
    )
    .accessibilityElement(children: .contain)
  }
}

private struct MistiaQuickCreateMenuRow: View {
  @Environment(\.colorScheme) private var colorScheme
  let destination: MistiaQuickCreateDestination

  private var iconBackgroundColor: Color {
    destination.accent.opacity(colorScheme == .dark ? 0.18 : 0.12)
  }

  var body: some View {
    HStack(alignment: .center, spacing: 14) {
      ZStack {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(Color(red: 0.43, green: 0.23, blue: 0.76).opacity(0.24)) // Brightened background
        
        Image(systemName: destination.systemImage)
          .font(.system(size: 17, weight: .bold, design: .rounded))
          .foregroundStyle(Color(red: 0.88, green: 0.78, blue: 1.0)) // Matched to light purple accent
      }
      .frame(width: 42, height: 42)

      VStack(alignment: .leading, spacing: 1) {
        Text(destination.title)
          .font(.system(size: 17, weight: .bold, design: .rounded))
          .foregroundStyle(.white)

        Text(destination.subtitle)
          .font(.system(size: 12, weight: .medium, design: .rounded))
          .foregroundStyle(.white.opacity(0.6))
          .lineLimit(1)
      }

      Spacer()
    }
    .padding(.horizontal, 20)
    .frame(height: 60) // Reduced height for rows
    .contentShape(Rectangle())
  }
}
