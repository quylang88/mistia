import SwiftUI
import UIKit

enum MistiaRootChromeMetrics {
  static let floatingButtonDiameter: CGFloat = 62
  static let trailingInset: CGFloat = 20
}

struct MistiaNativeTabShell: UIViewControllerRepresentable {
  @Binding var selectedTab: MistiaTab
  var appearanceMode: MistiaAppearanceMode
  var appLanguage: MistiaAppLanguage
  var hidesQuickCreate: Bool
  var hidesTabBar: Bool
  var showsShortcutTab: Bool
  var isShortcutSyncing: Bool
  var isShortcutDisabled: Bool
  var isShortcutAttentionPulsing: Bool
  var shortcutDisabledAccessibilityHint: String?
  var shortcutPresentation: MistiaShortcutPresentation
  var isMenuVisible: Bool
  var onShortcutTap: () -> Void
  var onQuickCreateTap: () -> Void
  var onQuickCreateFrameChange: (CGRect) -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  func makeUIViewController(context: Context) -> MistiaNativeTabBarController {
    let controller = MistiaNativeTabBarController()
    controller.chromeDelegate = context.coordinator
    controller.render(
      selectedTab: selectedTab,
      appearanceMode: appearanceMode,
      appLanguage: appLanguage,
      shortcutPresentation: shortcutPresentation,
      isShortcutSyncing: isShortcutSyncing,
      isShortcutDisabled: isShortcutDisabled,
      isShortcutAttentionPulsing: isShortcutAttentionPulsing,
      shortcutDisabledAccessibilityHint: shortcutDisabledAccessibilityHint,
      hidesQuickCreate: hidesQuickCreate,
      hidesTabBar: hidesTabBar,
      showsShortcutTab: showsShortcutTab,
      isMenuVisible: isMenuVisible
    )
    return controller
  }

  func updateUIViewController(_ controller: MistiaNativeTabBarController, context: Context) {
    context.coordinator.parent = self
    controller.chromeDelegate = context.coordinator
    controller.render(
      selectedTab: selectedTab,
      appearanceMode: appearanceMode,
      appLanguage: appLanguage,
      shortcutPresentation: shortcutPresentation,
      isShortcutSyncing: isShortcutSyncing,
      isShortcutDisabled: isShortcutDisabled,
      isShortcutAttentionPulsing: isShortcutAttentionPulsing,
      shortcutDisabledAccessibilityHint: shortcutDisabledAccessibilityHint,
      hidesQuickCreate: hidesQuickCreate,
      hidesTabBar: hidesTabBar,
      showsShortcutTab: showsShortcutTab,
      isMenuVisible: isMenuVisible
    )
  }

  final class Coordinator: NSObject, MistiaNativeTabBarControllerDelegate {
    var parent: MistiaNativeTabShell
    private var lastQuickCreateFrame: CGRect?

    init(parent: MistiaNativeTabShell) {
      self.parent = parent
    }

    func nativeTabBarController(
      _ controller: MistiaNativeTabBarController, didSelect tab: MistiaTab
    ) {
      guard parent.selectedTab != tab else { return }
      parent.selectedTab = tab
    }

    func nativeTabBarControllerDidTapShortcut(_ controller: MistiaNativeTabBarController) {
      parent.onShortcutTap()
    }

    func nativeTabBarControllerDidTapQuickCreate(_ controller: MistiaNativeTabBarController) {
      parent.onQuickCreateTap()
    }

    func nativeTabBarController(
      _ controller: MistiaNativeTabBarController, didUpdateQuickCreateFrame frame: CGRect
    ) {
      guard lastQuickCreateFrame != frame else { return }
      lastQuickCreateFrame = frame
      DispatchQueue.main.async { [weak self] in
        self?.parent.onQuickCreateFrameChange(frame)
      }
    }
  }
}

protocol MistiaNativeTabBarControllerDelegate: AnyObject {
  func nativeTabBarController(_ controller: MistiaNativeTabBarController, didSelect tab: MistiaTab)
  func nativeTabBarControllerDidTapShortcut(_ controller: MistiaNativeTabBarController)
  func nativeTabBarControllerDidTapQuickCreate(_ controller: MistiaNativeTabBarController)
  func nativeTabBarController(
    _ controller: MistiaNativeTabBarController, didUpdateQuickCreateFrame frame: CGRect)
}

final class MistiaNativeTabBarController: UITabBarController, UITabBarControllerDelegate {
  weak var chromeDelegate: MistiaNativeTabBarControllerDelegate?

  private let mistiaAccentColor = UIColor(red: 0.43, green: 0.23, blue: 0.76, alpha: 1)
  private let mistiaDarkModeTabTintColor = UIColor(red: 0.90, green: 0.74, blue: 1.00, alpha: 1)
  private let mistiaLightModeUnselectedTabTintColor = UIColor(
    red: 0.47, green: 0.48, blue: 0.54, alpha: 1)
  private let mistiaDarkModeUnselectedTabTintColor = UIColor(
    red: 0.78, green: 0.79, blue: 0.84, alpha: 1)

  private var didConfigureTabs = false
  private var didConfigureQuickCreateButton = false
  private var didConfigureShortcutButton = false
  private var cachedControllers: [MistiaTab: UIViewController] = [:]
  @available(iOS 18.0, *)
  private var cachedRootTabs: [MistiaTab: UITab] = [:]
  private var shortcutAvatarTask: Task<Void, Never>?
  private var shortcutAvatarImageCache: [String: UIImage] = [:]
  private var currentShortcutImageKey = ""
  private var shortcutImage: UIImage?
  private var currentAppearanceMode: MistiaAppearanceMode = .automatic
  private var currentAppLanguage: MistiaAppLanguage = .english
  private var currentShortcutPresentation = MistiaShortcutPresentation(
    title: "",
    accessibilityLabel: "",
    icon: .systemImage("externaldrive.fill.badge.icloud"),
    action: .backupRestore
  )
  private var isCurrentShortcutSyncing = false
  private var isCurrentShortcutDisabled = false
  private var isCurrentShortcutAttentionPulsing = false
  private var currentShortcutDisabledAccessibilityHint: String?
  private var currentSelectedMistiaTab: MistiaTab?
  private var currentShowsShortcutTab = false
  private var wasMenuVisible = false
  private var draggedFocusedTab: MistiaTab?
  private var draggedFocusedIndex: Int?

  private lazy var quickCreateController = UIHostingController(
    rootView: MistiaQuickCreateFloatingButton(appLanguage: currentAppLanguage) { [weak self] in
      guard let self else { return }
      chromeDelegate?.nativeTabBarControllerDidTapQuickCreate(self)
    }
  )

  private lazy var shortcutController = UIHostingController(
    rootView: MistiaShortcutFloatingButton(
      image: nil,
      tint: Color(uiColor: currentShortcutTint),
      isSyncing: false,
      isDisabled: true,
      showsAttentionPulse: false,
      accessibilityLabel: "",
      accessibilityHint: nil
    ) { [weak self] in
      guard let self else { return }
      chromeDelegate?.nativeTabBarControllerDidTapShortcut(self)
    }
  )

  override func viewDidLoad() {
    super.viewDidLoad()
    setupNotifications()
    delegate = self
    view.backgroundColor = .clear
    registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in
      if self.currentAppearanceMode == .automatic {
        self.applyChromeAppearance()
        if #available(iOS 18.0, *) {
          let tab = self.selectedTab.flatMap { MistiaTab(identifier: $0.identifier) }
          self.syncTabSymbols(selectedTab: tab)
        }
      }
    }
    configureSystemTabBar()
    configureQuickCreateButtonIfNeeded()
  }

  private func setupNotifications() {
    NotificationCenter.default.addObserver(forName: NSNotification.Name("MistiaHideTabBar"), object: nil, queue: .main) { [weak self] notification in
      if let isHidden = notification.userInfo?["isHidden"] as? Bool {
        self?.updateTabBarVisibility(isHidden: isHidden)
      }
    }
    NotificationCenter.default.addObserver(
      forName: UIAccessibility.reduceMotionStatusDidChangeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.refreshShortcutButton()
    }
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    layoutTabBarForShortcut()
    layoutFloatingButtons()
    notifyQuickCreateFrameChanged()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    scheduleQuickCreateButtonRealignment()
  }

  func render(
    selectedTab: MistiaTab,
    appearanceMode: MistiaAppearanceMode,
    appLanguage: MistiaAppLanguage,
    shortcutPresentation: MistiaShortcutPresentation,
    isShortcutSyncing: Bool,
    isShortcutDisabled: Bool,
    isShortcutAttentionPulsing: Bool,
    shortcutDisabledAccessibilityHint: String?,
    hidesQuickCreate: Bool,
    hidesTabBar: Bool,
    showsShortcutTab: Bool,
    isMenuVisible: Bool
  )
  {
    let isFirstRender = currentSelectedMistiaTab == nil
    let didChangeAppearance = currentAppearanceMode != appearanceMode
    let didChangeLanguage = currentAppLanguage != appLanguage
    let didChangeShortcutContent =
      currentShortcutPresentation != shortcutPresentation
      || isCurrentShortcutSyncing != isShortcutSyncing
      || isCurrentShortcutDisabled != isShortcutDisabled
      || isCurrentShortcutAttentionPulsing != isShortcutAttentionPulsing
      || currentShortcutDisabledAccessibilityHint != shortcutDisabledAccessibilityHint
    let didChangeShortcutVisibility = currentShowsShortcutTab != showsShortcutTab
    let didChangeSelectedTab = currentSelectedMistiaTab != selectedTab

    currentAppearanceMode = appearanceMode
    currentAppLanguage = appLanguage
    currentShowsShortcutTab = showsShortcutTab
    currentShortcutPresentation = shortcutPresentation
    isCurrentShortcutSyncing = isShortcutSyncing
    isCurrentShortcutDisabled = isShortcutDisabled
    isCurrentShortcutAttentionPulsing = isShortcutAttentionPulsing
    currentShortcutDisabledAccessibilityHint = shortcutDisabledAccessibilityHint
    overrideUserInterfaceStyle = appearanceMode.interfaceStyle

    configureTabsIfNeeded()
    configureQuickCreateButtonIfNeeded()
    configureShortcutButtonIfNeeded()

    if didChangeLanguage {
      refreshLocalizedContent()
    } else if isFirstRender || didChangeAppearance || didChangeShortcutContent {
      refreshShortcutButtonContent()
    }

    updateQuickCreateVisibility(isHidden: hidesQuickCreate || hidesTabBar, isMenuVisible: isMenuVisible)
    updateShortcutButtonVisibility(isHidden: !showsShortcutTab || hidesTabBar)
    updateTabBarVisibility(isHidden: hidesTabBar)
    if isFirstRender || didChangeAppearance {
      applyChromeAppearance()
    }
    if isFirstRender || didChangeSelectedTab || didChangeAppearance {
      syncTabSymbols(selectedTab: selectedTab)
    }
    currentSelectedMistiaTab = selectedTab

    guard #available(iOS 18.0, *) else { return }
    let identifier = selectedTab.tabIdentifier
    if self.selectedTab?.identifier != identifier {
      self.selectedTab = tab(forIdentifier: identifier)
    }
    if isFirstRender || didChangeShortcutContent || didChangeShortcutVisibility {
      scheduleTabBarChromeRefresh(selectedTab: selectedTab)
    }
  }

  private func configureTabsIfNeeded() {
    guard !didConfigureTabs else { return }
    didConfigureTabs = true

    if #available(iOS 18.0, *) {
      mode = .tabBar
      customizationIdentifier = "vn.com.quyln.mistia.main-tabs"

      let rootTabs = MistiaTab.nativeShellTabs.map(makeRootTab(for:))
      cachedRootTabs = Dictionary(uniqueKeysWithValues: zip(MistiaTab.nativeShellTabs, rootTabs))
      setTabs(rootTabs, animated: false)
      selectedTab = rootTabs.first
      syncTabSymbols(selectedTab: .overview)
    } else {
      let controllers = MistiaTab.nativeShellTabs.map(viewController(for:))
      viewControllers = controllers
      selectedIndex = 0
      syncTabSymbols(selectedTab: .overview)
    }
  }

  private func configureSystemTabBar() {
    tabBar.isTranslucent = true
    tabBar.itemPositioning = .centered
    tabBar.itemWidth = 82
    tabBar.itemSpacing = 0
    if #available(iOS 26.0, *) {
      tabBarMinimizeBehavior = .never
    }
    applyChromeAppearance()
    setupTabBarDragGesture()
  }

  private func configureQuickCreateButtonIfNeeded() {
    guard !didConfigureQuickCreateButton else { return }
    didConfigureQuickCreateButton = true
    refreshQuickCreateRootView()

    addChild(quickCreateController)
    quickCreateController.view.translatesAutoresizingMaskIntoConstraints = true
    quickCreateController.view.backgroundColor = UIColor.clear
    view.addSubview(quickCreateController.view)
    quickCreateController.didMove(toParent: self)
    layoutFloatingButtons()
  }

  private func configureShortcutButtonIfNeeded() {
    guard !didConfigureShortcutButton else { return }
    didConfigureShortcutButton = true
    refreshShortcutButton()

    addChild(shortcutController)
    shortcutController.view.translatesAutoresizingMaskIntoConstraints = true
    shortcutController.view.backgroundColor = .clear
    view.addSubview(shortcutController.view)
    shortcutController.didMove(toParent: self)
    layoutFloatingButtons()
  }

  private func refreshLocalizedContent() {
    refreshQuickCreateRootView()
    refreshShortcutButtonContent()

    if #available(iOS 18.0, *) {
      for tab in MistiaTab.nativeShellTabs {
        cachedRootTabs[tab]?.title = tab.title
      }
    }

    for tab in MistiaTab.nativeShellTabs {
      let controller = viewController(for: tab)
      controller.title = tab.title
      if let hostingController = controller as? UIHostingController<AnyView> {
        hostingController.rootView = localizedRootView(for: tab)
      }
    }
  }

  private func refreshQuickCreateRootView() {
    quickCreateController.rootView = MistiaQuickCreateFloatingButton(
      appLanguage: currentAppLanguage
    ) { [weak self] in
      guard let self else { return }
      chromeDelegate?.nativeTabBarControllerDidTapQuickCreate(self)
    }
  }

  private func refreshShortcutButtonContent() {
    shortcutAvatarTask?.cancel()
    shortcutAvatarTask = nil

    if isCurrentShortcutSyncing && !isCurrentShortcutDisabled {
      currentShortcutImageKey = "syncing_spinner"
      refreshShortcutButton()
      return
    }

    switch currentShortcutPresentation.icon {
    case .systemImage(let systemName):
      currentShortcutImageKey = "system:\(systemName)"
      shortcutImage = shortcutSystemImage(systemName)

    case .currentUserAvatar(_, let avatarURL):
      currentShortcutImageKey = avatarURL?.absoluteString ?? "system:person.crop.circle.fill"

      guard let avatarURL else {
        shortcutImage = shortcutSystemImage("person.crop.circle.fill")
        refreshShortcutButton()
        return
      }

      if let cachedImage = shortcutAvatarImageCache[avatarURL.absoluteString] {
        shortcutImage = cachedImage
        refreshShortcutButton()
        return
      }

      shortcutImage = shortcutSystemImage("person.crop.circle.fill")
      loadShortcutAvatarImage(from: avatarURL, fallbackImage: shortcutSystemImage("person.crop.circle.fill"))

    case .memberAvatar(let initials, let avatarURL):
      let fallbackImage = makeShortcutFallbackAvatarImage(initials: initials)
      currentShortcutImageKey = avatarURL?.absoluteString ?? "member:\(initials)"

      guard let avatarURL else {
        shortcutImage = fallbackImage
        refreshShortcutButton()
        return
      }

      if let cachedImage = shortcutAvatarImageCache[avatarURL.absoluteString] {
        shortcutImage = cachedImage
        refreshShortcutButton()
        return
      }

      shortcutImage = fallbackImage
      loadShortcutAvatarImage(from: avatarURL, fallbackImage: fallbackImage)
    }

    refreshShortcutButton()
  }

  private func loadShortcutAvatarImage(from url: URL, fallbackImage: UIImage?) {
    let cacheKey = url.absoluteString

    shortcutAvatarTask = Task { [weak self] in
      guard let self else { return }
      let image = await self.fetchShortcutAvatarImage(from: url)
      guard !Task.isCancelled else { return }

      await MainActor.run {
        guard let resolvedImage = image ?? fallbackImage else { return }
        if image != nil {
          self.shortcutAvatarImageCache[cacheKey] = resolvedImage
        }
        guard self.currentShortcutImageKey == cacheKey else { return }
        self.shortcutImage = resolvedImage
        self.refreshShortcutButton()
      }
    }
  }

  private func fetchShortcutAvatarImage(from url: URL) async -> UIImage? {
    if url.isFileURL {
      return await Task.detached(priority: .utility) {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return Self.makeShortcutAvatarImage(from: data)
      }.value
    }

    do {
      let (data, _) = try await URLSession.shared.data(from: url)
      return await Task.detached(priority: .utility) {
        Self.makeShortcutAvatarImage(from: data)
      }.value
    } catch {
      return nil
    }
  }

  private func shortcutSystemImage(_ systemName: String) -> UIImage? {
    let config = UIImage.SymbolConfiguration(pointSize: 25, weight: .medium)
    let image = UIImage(systemName: systemName, withConfiguration: config)
    return image?.mistiaRasterized(with: currentShortcutTint)
  }

  private var currentShortcutTint: UIColor {
    let usesDarkTint =
      currentAppearanceMode == .dark
      || (currentAppearanceMode == .automatic && traitCollection.userInterfaceStyle == .dark)

    switch currentShortcutPresentation.action {
    case .backupRestore:
      return usesDarkTint
        ? UIColor(red: 0.40, green: 0.85, blue: 0.75, alpha: 1.0) // #66d8bf
        : UIColor(red: 0.00, green: 0.65, blue: 0.55, alpha: 1.0) // #00a68c
    case .archivedItems:
      return usesDarkTint
        ? UIColor(red: 0.65, green: 0.68, blue: 0.69, alpha: 1.0) // #a6adb0
        : UIColor(red: 0.45, green: 0.48, blue: 0.57, alpha: 1.0) // #737b91
    case .familyOverview:
      return usesDarkTint
        ? UIColor(red: 0.90, green: 0.74, blue: 1.00, alpha: 1.0) // mistiaDarkModeTabTintColor
        : UIColor(red: 0.43, green: 0.23, blue: 0.76, alpha: 1.0) // mistiaAccentColor
    case .memberOverview:
      return usesDarkTint
        ? UIColor(red: 1.00, green: 0.46, blue: 0.66, alpha: 1.0) // #ff75a9
        : UIColor(red: 0.86, green: 0.20, blue: 0.46, alpha: 1.0) // #dc3375
    case .investment:
      return usesDarkTint
        ? UIColor(red: 0.90, green: 0.74, blue: 1.00, alpha: 1.0)
        : UIColor(red: 0.43, green: 0.23, blue: 0.76, alpha: 1.0)
    case .receiptScan:
      return usesDarkTint
        ? UIColor(red: 1.00, green: 0.72, blue: 0.28, alpha: 1.0) // #ffb847
        : UIColor(red: 0.93, green: 0.52, blue: 0.16, alpha: 1.0) // #ed8529
    case .syncNow:
      return usesDarkTint
        ? UIColor(red: 0.50, green: 0.78, blue: 1.00, alpha: 1.0) // #80c7ff
        : UIColor(red: 0.20, green: 0.58, blue: 0.90, alpha: 1.0) // #3394e6
    }
  }

  private func refreshShortcutButton() {
    guard didConfigureShortcutButton else { return }

    shortcutController.rootView = MistiaShortcutFloatingButton(
      image: shortcutImage,
      tint: Color(uiColor: currentShortcutTint),
      isSyncing: isCurrentShortcutSyncing,
      isDisabled: isCurrentShortcutDisabled,
      showsAttentionPulse: isCurrentShortcutAttentionPulsing,
      accessibilityLabel: currentShortcutPresentation.accessibilityLabel,
      accessibilityHint: currentShortcutDisabledAccessibilityHint
    ) { [weak self] in
      guard let self else { return }
      chromeDelegate?.nativeTabBarControllerDidTapShortcut(self)
    }
  }

  private func makeShortcutFallbackAvatarImage(initials: String) -> UIImage? {
    let size = CGSize(width: 36, height: 36)
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { context in
      let rect = CGRect(origin: .zero, size: size)
      let path = UIBezierPath(ovalIn: rect)
      path.addClip()

      let colors = [
        UIColor(red: 0.49, green: 0.34, blue: 0.95, alpha: 1),
        UIColor(red: 0.36, green: 0.50, blue: 0.98, alpha: 1)
      ] as CFArray

      guard let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: colors,
        locations: [0, 1]
      ) else {
        return
      }

      context.cgContext.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: 0),
        end: CGPoint(x: rect.maxX, y: rect.maxY),
        options: []
      )

      let paragraphStyle = NSMutableParagraphStyle()
      paragraphStyle.alignment = .center
      let attributes: [NSAttributedString.Key: Any] = [
        .font: UIFont.systemFont(ofSize: 13, weight: .heavy),
        .foregroundColor: UIColor.white,
        .paragraphStyle: paragraphStyle
      ]
      let string = NSString(string: initials)
      let size = string.size(withAttributes: attributes)
      let textRect = CGRect(
        x: (rect.width - size.width) / 2,
        y: (rect.height - size.height) / 2,
        width: size.width,
        height: size.height
      )
      string.draw(in: textRect, withAttributes: attributes)
    }.withRenderingMode(.alwaysOriginal)
  }

  private nonisolated static func makeShortcutAvatarImage(from image: UIImage) -> UIImage? {
    let size = CGSize(width: 36, height: 36)
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { _ in
      UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).addClip()
      image.draw(in: CGRect(origin: .zero, size: size))
    }.withRenderingMode(.alwaysOriginal)
  }

  private nonisolated static func makeShortcutAvatarImage(from data: Data) -> UIImage? {
    guard let image = UIImage(data: data) else { return nil }
    return makeShortcutAvatarImage(from: image)
  }

  private func layoutFloatingButtons() {
    guard didConfigureQuickCreateButton, !view.bounds.isEmpty else { return }
    let tabContentFrame = visibleTabBarContentFrame
    guard !tabContentFrame.isEmpty else { return }

    let buttonSize = MistiaRootChromeMetrics.floatingButtonDiameter
    let tabBarGap: CGFloat = 14
    let centerX = fallbackQuickCreateCenterX

    quickCreateController.view.frame = CGRect(
      x: centerX - buttonSize / 2,
      y: tabContentFrame.minY - tabBarGap - buttonSize,
      width: buttonSize,
      height: buttonSize
    )

    guard didConfigureShortcutButton else { return }
    shortcutController.view.frame = CGRect(
      x: centerX - buttonSize / 2,
      y: tabContentFrame.midY - buttonSize / 2,
      width: buttonSize,
      height: buttonSize
    )
  }

  private func layoutTabBarForShortcut() {
    guard !view.bounds.isEmpty else { return }
    tabBar.layoutIfNeeded()

    let buttonSize = MistiaRootChromeMetrics.floatingButtonDiameter
    let gap: CGFloat = 12
    let shortcutCenterX = fallbackQuickCreateCenterX
    let fullWidth = view.bounds.width
    let tabBarFrame = tabBar.convert(tabBar.bounds, to: view)
    // The system's visible pill is inset inside the tab bar's full frame.
    let contentTrailingInset = max(0, tabBarFrame.maxX - visibleTabBarContentFrame.maxX)
    let targetWidth = currentShowsShortcutTab
      ? shortcutCenterX - buttonSize / 2 - gap + contentTrailingInset - view.bounds.minX
      : fullWidth

    var targetFrame = tabBar.frame
    targetFrame.origin.x = view.bounds.minX
    targetFrame.size.width = targetWidth

    if abs(tabBar.frame.minX - targetFrame.minX) > 0.5
      || abs(tabBar.frame.width - targetFrame.width) > 0.5
    {
      tabBar.frame = targetFrame
    }

    tabBar.layoutIfNeeded()

    let itemWidth = currentShowsShortcutTab
      ? targetWidth / CGFloat(MistiaTab.nativeShellTabs.count)
      : 82
    guard abs(tabBar.itemWidth - itemWidth) > 0.5 else { return }

    tabBar.itemWidth = itemWidth
    let appearance = tabBar.standardAppearance.copy()
    appearance.stackedItemWidth = itemWidth
    tabBar.standardAppearance = appearance
    tabBar.scrollEdgeAppearance = appearance
    tabBar.setNeedsLayout()
  }

  private var visibleTabBarContentFrame: CGRect {
    func containsVisibleControl(_ candidate: UIView) -> Bool {
      guard !candidate.isHidden, candidate.alpha > 0.01, !candidate.bounds.isEmpty else {
        return false
      }
      return candidate is UIControl || candidate.subviews.contains(where: containsVisibleControl)
    }

    let contentFrames = tabBar.subviews
      .filter(containsVisibleControl)
      .map { $0.convert($0.bounds, to: view) }
    if let firstFrame = contentFrames.first {
      return contentFrames.dropFirst().reduce(firstFrame) { $0.union($1) }
    }

    // Before UIKit creates the tab controls, exclude the home-indicator safe area.
    let frame = tabBar.convert(tabBar.bounds, to: view)
    return CGRect(
      x: frame.minX,
      y: frame.minY,
      width: frame.width,
      height: max(0, frame.height - tabBar.safeAreaInsets.bottom)
    )
  }

  private func scheduleQuickCreateButtonRealignment() {
    DispatchQueue.main.async { [weak self] in
      self?.layoutFloatingButtons()
      self?.notifyQuickCreateFrameChanged()
    }
  }

  private func applyChromeAppearance() {
    let usesDarkTint: Bool
    switch currentAppearanceMode {
    case .dark:
      usesDarkTint = true
    case .light:
      usesDarkTint = false
    case .automatic:
      usesDarkTint = traitCollection.userInterfaceStyle == .dark
    }

    let selectedTint = usesDarkTint ? mistiaDarkModeTabTintColor : mistiaAccentColor
    let unselectedTint =
      usesDarkTint ? mistiaDarkModeUnselectedTabTintColor : mistiaLightModeUnselectedTabTintColor

    tabBar.tintColor = selectedTint
    tabBar.unselectedItemTintColor = unselectedTint

    let appearance = tabBar.standardAppearance.copy()
    appearance.stackedItemPositioning = .centered
    appearance.stackedItemWidth = 82
    appearance.stackedItemSpacing = 0

    let stackedAppearance = appearance.stackedLayoutAppearance
    stackedAppearance.normal.iconColor = unselectedTint
    stackedAppearance.selected.iconColor = selectedTint
    stackedAppearance.normal.titlePositionAdjustment = UIOffset(horizontal: 0, vertical: 2)
    stackedAppearance.selected.titlePositionAdjustment = UIOffset(horizontal: 0, vertical: 2)
    stackedAppearance.normal.titleTextAttributes = tabBarTitleAttributes(
      color: unselectedTint,
      font: .systemFont(ofSize: 11.5, weight: .semibold)
    )
    stackedAppearance.selected.titleTextAttributes = tabBarTitleAttributes(
      color: selectedTint,
      font: .systemFont(ofSize: 11.5, weight: .semibold)
    )

    appearance.inlineLayoutAppearance = stackedAppearance.copy()
    appearance.compactInlineLayoutAppearance = stackedAppearance.copy()

    tabBar.standardAppearance = appearance
    tabBar.scrollEdgeAppearance = appearance
  }

  private func tabBarTitleAttributes(color: UIColor, font: UIFont) -> [NSAttributedString.Key: Any]
  {
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.alignment = .center
    paragraphStyle.lineBreakMode = .byTruncatingTail

    return [
      .font: font,
      .foregroundColor: color,
      .paragraphStyle: paragraphStyle,
    ]
  }

  private func updateQuickCreateVisibility(isHidden: Bool, isMenuVisible: Bool) {
    guard didConfigureQuickCreateButton else { return }
    let targetAlpha: CGFloat = isHidden ? 0 : 1
    guard
      quickCreateController.view.alpha != targetAlpha
        || quickCreateController.view.isHidden != isHidden
    else {
      wasMenuVisible = isMenuVisible
      notifyQuickCreateFrameChanged()
      return
    }

    if !isHidden {
      quickCreateController.view.isHidden = false
    }

    if isMenuVisible || wasMenuVisible {
      // Swap instantly when transitioning with the menu to avoid double-imaging/gaps
      self.quickCreateController.view.alpha = targetAlpha
      self.quickCreateController.view.isHidden = isHidden
      self.notifyQuickCreateFrameChanged()
    } else {
      UIView.animate(withDuration: 0.18, delay: 0, options: [.beginFromCurrentState, .curveEaseInOut]) {
        self.quickCreateController.view.alpha = targetAlpha
      } completion: { _ in
        guard abs(self.quickCreateController.view.alpha - targetAlpha) < 0.01 else { return }
        self.quickCreateController.view.isHidden = isHidden
        self.notifyQuickCreateFrameChanged()
      }
    }
    wasMenuVisible = isMenuVisible
  }

  private func updateShortcutButtonVisibility(isHidden: Bool) {
    guard didConfigureShortcutButton else { return }
    let targetAlpha: CGFloat = isHidden ? 0 : 1
    guard
      shortcutController.view.alpha != targetAlpha
        || shortcutController.view.isHidden != isHidden
    else { return }

    if !isHidden {
      shortcutController.view.isHidden = false
    }

    UIView.animate(withDuration: 0.18, delay: 0, options: [.beginFromCurrentState, .curveEaseInOut]) {
      self.shortcutController.view.alpha = targetAlpha
    } completion: { _ in
      guard abs(self.shortcutController.view.alpha - targetAlpha) < 0.01 else { return }
      self.shortcutController.view.isHidden = isHidden
    }
  }

  private func updateTabBarVisibility(isHidden: Bool) {
    let targetAlpha: CGFloat = isHidden ? 0 : 1
    let targetTranslation: CGFloat = isHidden ? (tabBar.frame.height > 0 ? tabBar.frame.height : 100) : 0
    let targetSafeAreaBottom = isHidden ? -tabBar.frame.height : 0

    let alreadyAtTarget =
      tabBar.isHidden == isHidden
      && abs(tabBar.alpha - targetAlpha) < 0.01
      && abs(tabBar.transform.ty - targetTranslation) < 0.5
      && abs(additionalSafeAreaInsets.bottom - targetSafeAreaBottom) < 0.5

    guard !alreadyAtTarget else { return }
    
    if !isHidden {
      tabBar.isHidden = false
    }
    
    UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0) {
      self.tabBar.alpha = targetAlpha
      self.tabBar.transform = CGAffineTransform(translationX: 0, y: targetTranslation)
      
      // Triệt tiêu vùng Safe Area của TabBar để View con tràn xuống đáy
      self.additionalSafeAreaInsets.bottom = targetSafeAreaBottom
      
      self.view.setNeedsLayout()
      self.view.layoutIfNeeded()
    } completion: { _ in
      self.tabBar.isHidden = isHidden
    }
  }

  private func notifyQuickCreateFrameChanged() {
    guard didConfigureQuickCreateButton else { return }
    view.layoutIfNeeded()
    let frame = quickCreateController.view.convert(quickCreateController.view.bounds, to: view)
    chromeDelegate?.nativeTabBarController(self, didUpdateQuickCreateFrame: frame.integral)
  }

  private var fallbackQuickCreateCenterX: CGFloat {
    view.bounds.maxX - view.safeAreaInsets.right - MistiaRootChromeMetrics.trailingInset
      - MistiaRootChromeMetrics.floatingButtonDiameter / 2
  }

  private var currentSelectedTint: UIColor {
    let usesDarkTint =
      currentAppearanceMode == .dark
      || (currentAppearanceMode == .automatic && traitCollection.userInterfaceStyle == .dark)
    return usesDarkTint ? mistiaDarkModeTabTintColor : mistiaAccentColor
  }

  private var currentUnselectedTint: UIColor {
    let usesDarkTint =
      currentAppearanceMode == .dark
      || (currentAppearanceMode == .automatic && traitCollection.userInterfaceStyle == .dark)
    return usesDarkTint
      ? mistiaDarkModeUnselectedTabTintColor : mistiaLightModeUnselectedTabTintColor
  }

  private func syncTabSymbols(selectedTab: MistiaTab?, focusedTab: MistiaTab? = nil) {
    let activeTab = focusedTab ?? selectedTab
    if #available(iOS 18.0, *) {
      let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)
      for tab in MistiaTab.nativeShellTabs {
        let isSelected = tab == activeTab
        let tint = isSelected ? currentSelectedTint : currentUnselectedTint
        cachedRootTabs[tab]?.image = UIImage(
          systemName: tab.systemImage(isSelected: isSelected),
          withConfiguration: config
        )?.mistiaRasterized(with: tint)
      }
    } else {
      for tab in MistiaTab.nativeShellTabs {
        let controller = viewController(for: tab)
        controller.tabBarItem.image = UIImage(systemName: tab.outlineSystemImage)
        controller.tabBarItem.selectedImage = UIImage(systemName: tab.selectedSystemImage)
      }
    }
  }

  private func setupTabBarDragGesture() {
    let gesture = UILongPressGestureRecognizer(
      target: self, action: #selector(handleTabBarDragGesture(_:)))
    gesture.minimumPressDuration = 0
    gesture.delaysTouchesBegan = false
    gesture.delegate = self
    tabBar.addGestureRecognizer(gesture)
  }

  @objc private func handleTabBarDragGesture(_ gesture: UILongPressGestureRecognizer) {
    let location = gesture.location(in: tabBar)

    switch gesture.state {
    case .began:
      updateFocusedTabForGesture(at: location)

    case .changed:
      updateFocusedTabForGesture(at: location)

    case .ended:
      if let focusedTab = draggedFocusedTab {
        if currentSelectedMistiaTab != focusedTab {
          currentSelectedMistiaTab = focusedTab
          if #available(iOS 18.0, *) {
            if let rootTab = cachedRootTabs[focusedTab] {
              self.selectedTab = rootTab
            }
          } else if let index = MistiaTab.nativeShellTabs.firstIndex(of: focusedTab) {
            self.selectedIndex = index
          }
          chromeDelegate?.nativeTabBarController(self, didSelect: focusedTab)
        }
      }
      clearTabHoverHighlight()

    case .cancelled, .failed:
      clearTabHoverHighlight()

    default:
      break
    }
  }

  private var orderedTabControls: [UIControl] {
    tabBar.subviews
      .compactMap { $0 as? UIControl }
      .filter { !$0.isHidden && $0.alpha > 0.01 && $0.bounds.width > 10 }
      .sorted { $0.frame.minX < $1.frame.minX }
  }

  private func targetIndex(for location: CGPoint) -> Int? {
    guard tabBar.bounds.contains(CGPoint(x: location.x, y: tabBar.bounds.midY))
            || (location.y >= -30 && location.y <= tabBar.bounds.height + 30) else {
      return nil
    }

    let controls = orderedTabControls
    let totalCount = MistiaTab.nativeShellTabs.count

    if controls.count == totalCount {
      for (index, control) in controls.enumerated() {
        let frame = control.frame
        if location.x >= frame.minX && location.x <= frame.maxX {
          return index
        }
      }
    }

    guard tabBar.bounds.width > 0 else { return nil }
    let itemWidth = tabBar.bounds.width / CGFloat(totalCount)
    let index = min(max(0, Int(location.x / itemWidth)), totalCount - 1)
    return index
  }

  private func updateFocusedTabForGesture(at location: CGPoint) {
    let index = targetIndex(for: location)
    guard index != draggedFocusedIndex else { return }

    draggedFocusedIndex = index
    let newFocusedTab = (index != nil && index! < 4) ? MistiaTab.nativeShellTabs[index!] : nil
    draggedFocusedTab = newFocusedTab

    applyTabHoverHighlight(focusedIndex: index, focusedTab: newFocusedTab)
  }

  private func applyTabHoverHighlight(focusedIndex: Int?, focusedTab: MistiaTab?) {
    let activeTab = focusedTab ?? (focusedIndex == nil ? currentSelectedMistiaTab : nil)
    syncTabSymbols(selectedTab: currentSelectedMistiaTab, focusedTab: activeTab)

    let controls = orderedTabControls
    let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)

    for (idx, control) in controls.enumerated() {
      let isFocused = (idx == focusedIndex)

      UIView.animate(
        withDuration: 0.18,
        delay: 0,
        usingSpringWithDamping: 0.75,
        initialSpringVelocity: 0,
        options: [.beginFromCurrentState, .allowUserInteraction]
      ) {
        control.transform = isFocused ? CGAffineTransform(scaleX: 1.15, y: 1.15) : .identity
      }

      if idx < 4 {
        let tab = MistiaTab.nativeShellTabs[idx]
        let isTabActive = (tab == activeTab)
        let tint = isTabActive ? currentSelectedTint : currentUnselectedTint
        let image = UIImage(
          systemName: tab.systemImage(isSelected: isTabActive),
          withConfiguration: config
        )?.mistiaRasterized(with: tint)

        if let imageView = findImageView(in: control) {
          imageView.image = image
        }
      }
    }
  }

  private func clearTabHoverHighlight() {
    draggedFocusedIndex = nil
    draggedFocusedTab = nil

    let controls = orderedTabControls
    UIView.animate(
      withDuration: 0.2,
      delay: 0,
      usingSpringWithDamping: 0.85,
      initialSpringVelocity: 0,
      options: [.beginFromCurrentState, .allowUserInteraction]
    ) {
      for control in controls {
        control.transform = .identity
      }
    }

    syncTabSymbols(selectedTab: currentSelectedMistiaTab)
  }

  private func findImageView(in view: UIView) -> UIImageView? {
    if let imageView = view as? UIImageView {
      return imageView
    }
    for subview in view.subviews {
      if let found = findImageView(in: subview) {
        return found
      }
    }
    return nil
  }

  @available(iOS 18.0, *)
  private func makeRootTab(for tab: MistiaTab) -> UITab {
    let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)
    let initialImage = UIImage(systemName: tab.outlineSystemImage, withConfiguration: config)?
      .mistiaRasterized(with: currentUnselectedTint)

    let rootTab = UITab(
      title: tab.title,
      image: initialImage,
      identifier: tab.tabIdentifier
    ) { [weak self] _ in
      guard let self else {
        return UIViewController()
      }
      return self.viewController(for: tab)
    }

    // Keep the four core destinations grouped by the system.
    rootTab.preferredPlacement = UITab.Placement.fixed
    return rootTab
  }

  private func scheduleTabBarChromeRefresh(selectedTab: MistiaTab) {
    view.setNeedsLayout()
    tabBar.setNeedsLayout()

    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.applyChromeAppearance()
      self.syncTabSymbols(selectedTab: selectedTab)
      self.view.setNeedsLayout()
      self.tabBar.setNeedsLayout()
      self.view.layoutIfNeeded()
      self.layoutFloatingButtons()
      self.notifyQuickCreateFrameChanged()
    }
  }

  private func viewController(for tab: MistiaTab) -> UIViewController {
    if let cachedController = cachedControllers[tab] {
      return cachedController
    }

    let host = UIHostingController(rootView: localizedRootView(for: tab))
    host.view.backgroundColor = .clear
    host.title = tab.title
    cachedControllers[tab] = host
    return host
  }

  private func localizedRootView(for tab: MistiaTab) -> AnyView {
    AnyView(
      tab.nativeRootView
        .id("mistia.root.\(tab.rawValue)")
        .environment(\.locale, currentAppLanguage.locale)
        .environment(\.calendar, currentAppLanguage.calendar)
    )
  }

  @available(iOS 18.0, *)
  func tabBarController(
    _ tabBarController: UITabBarController, didSelectTab selectedTab: UITab, previousTab: UITab?
  ) {
    let tab = MistiaTab(identifier: selectedTab.identifier)
    syncTabSymbols(selectedTab: tab)
    if let tab {
      chromeDelegate?.nativeTabBarController(self, didSelect: tab)
    }
  }

  func tabBarController(
    _ tabBarController: UITabBarController, didSelect viewController: UIViewController
  ) {
    guard
      let viewControllers,
      let index = viewControllers.firstIndex(of: viewController),
      let tab = MistiaTab.nativeShellTabs[safe: index]
    else { return }

    syncTabSymbols(selectedTab: tab)
    chromeDelegate?.nativeTabBarController(self, didSelect: tab)
  }
}

private struct MistiaQuickCreateFloatingButton: View {
  let appLanguage: MistiaAppLanguage
  let action: () -> Void

  var body: some View {
    Button {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
        action()
    } label: {
      Image(systemName: "plus")
        .font(.system(size: 24, weight: .semibold, design: .rounded))
        .foregroundStyle(MistiaAccent.checkmarkPurple.color)
        .frame(
          width: MistiaRootChromeMetrics.floatingButtonDiameter,
          height: MistiaRootChromeMetrics.floatingButtonDiameter
        )
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .glassEffect(
      .regular.tint(Color(red: 0.43, green: 0.23, blue: 0.76)).interactive(),
      in: Circle()
    )
    .shadow(color: Color.black.opacity(0.18), radius: 16, y: 8)
    .accessibilityLabel(
      L10n.app.mistianativetab.quickCreate
    )
  }
}

private struct MistiaShortcutFloatingButton: View {
  let image: UIImage?
  let tint: Color
  let isSyncing: Bool
  let isDisabled: Bool
  let showsAttentionPulse: Bool
  let accessibilityLabel: String
  let accessibilityHint: String?
  let action: () -> Void

  var body: some View {
    Group {
      if #available(iOS 26.0, *) {
        button
          .buttonStyle(.plain)
          .glassEffect(.regular.interactive(), in: Circle())
      } else {
        button
          .buttonStyle(.plain)
          .background(.ultraThinMaterial, in: Circle())
      }
    }
    .frame(
      width: MistiaRootChromeMetrics.floatingButtonDiameter,
      height: MistiaRootChromeMetrics.floatingButtonDiameter
    )
    .opacity(isDisabled ? 0.48 : 1)
    .shadow(color: Color.black.opacity(0.14), radius: 12, y: 6)
    .disabled(isDisabled || isSyncing)
    .accessibilityLabel(accessibilityLabel)
    .accessibilityHint(accessibilityHint ?? "")
  }

  private var button: some View {
    Button {
      let generator = UIImpactFeedbackGenerator(style: .light)
      generator.prepare()
      generator.impactOccurred()
      action()
    } label: {
      ZStack {
        if showsAttentionPulse && !isDisabled && !isSyncing {
          MistiaAttentionPulseRing(
            color: tint,
            diameter: MistiaRootChromeMetrics.floatingButtonDiameter - 4,
            targetScale: 1.62,
            isActive: true
          )
        }

        if isSyncing {
          ProgressView()
            .tint(tint)
        } else if let image {
          Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .frame(width: 28, height: 28)
        } else {
          Image(systemName: "externaldrive.badge.icloud")
            .font(.system(size: 24, weight: .medium))
            .foregroundStyle(tint)
        }
      }
      .frame(
        width: MistiaRootChromeMetrics.floatingButtonDiameter,
        height: MistiaRootChromeMetrics.floatingButtonDiameter
      )
      .contentShape(Circle())
    }
  }
}

extension MistiaTab {
  fileprivate static let nativeShellTabs: [MistiaTab] = [
    .overview, .transactions, .planning, .settings,
  ]

  fileprivate var tabIdentifier: String {
    "mistia.tab.\(rawValue)"
  }

  fileprivate init?(identifier: String) {
    guard let rawValue = identifier.split(separator: ".").last.map(String.init) else {
      return nil
    }
    self.init(rawValue: rawValue)
  }

  fileprivate var nativeRootView: AnyView {
    switch self {
    case .overview:
      AnyView(OverviewView())
    case .transactions:
      AnyView(TransactionsView())
    case .planning:
      AnyView(PlanningView())
    case .settings:
      AnyView(ManagementView())
    }
  }
}

extension Array {
  fileprivate subscript(safe index: Int) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}

extension UIImage {
  fileprivate func mistiaRasterized(with tintColor: UIColor) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = self.scale
    let renderer = UIGraphicsImageRenderer(size: self.size, format: format)
    return renderer.image { _ in
      tintColor.set()
      self.withTintColor(tintColor).draw(in: CGRect(origin: .zero, size: self.size))
    }.withRenderingMode(.alwaysOriginal)
  }
}


extension MistiaNativeTabBarController: UIGestureRecognizerDelegate {
  func gestureRecognizer(
    _ gestureRecognizer: UIGestureRecognizer,
    shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
  ) -> Bool {
    true
  }
}
