import SwiftUI
import UIKit

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
      showsShortcutTab: showsShortcutTab
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
      showsShortcutTab: showsShortcutTab
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
  private var cachedControllers: [MistiaTab: UIViewController] = [:]
  @available(iOS 18.0, *)
  private var cachedRootTabs: [MistiaTab: UITab] = [:]
  private weak var shortcutTab: UISearchTab?
  private var shortcutAvatarTask: Task<Void, Never>?
  private var shortcutAvatarImageCache: [String: UIImage] = [:]
  private var currentShortcutImageKey = ""
  private var quickCreateCenterXConstraint: NSLayoutConstraint?
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
  private var spinnerActivityIndicatorView: UIActivityIndicatorView?
  private var shortcutPulseLayer: CAShapeLayer?

  private lazy var quickCreateController = UIHostingController(
    rootView: MistiaQuickCreateFloatingButton(appLanguage: currentAppLanguage) { [weak self] in
      guard let self else { return }
      chromeDelegate?.nativeTabBarControllerDidTapQuickCreate(self)
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
    configureTabsIfNeeded()
    configureSystemTabBar()
    configureQuickCreateButtonIfNeeded()
  }

  private func setupNotifications() {
    NotificationCenter.default.addObserver(forName: NSNotification.Name("MistiaHideTabBar"), object: nil, queue: .main) { [weak self] notification in
      if let isHidden = notification.userInfo?["isHidden"] as? Bool {
        self?.updateTabBarVisibility(isHidden: isHidden)
      }
    }
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    alignQuickCreateButtonToSearchPill()
    updateShortcutPulseFrame()
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
    showsShortcutTab: Bool
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
    let didChangeSelectedTab = currentSelectedMistiaTab != selectedTab

    currentAppearanceMode = appearanceMode
    currentAppLanguage = appLanguage
    currentShortcutPresentation = shortcutPresentation
    isCurrentShortcutSyncing = isShortcutSyncing
    isCurrentShortcutDisabled = isShortcutDisabled
    isCurrentShortcutAttentionPulsing = isShortcutAttentionPulsing
    currentShortcutDisabledAccessibilityHint = shortcutDisabledAccessibilityHint
    overrideUserInterfaceStyle = appearanceMode.interfaceStyle

    configureTabsIfNeeded()
    configureQuickCreateButtonIfNeeded()

    if didChangeLanguage {
      refreshLocalizedContent()
    } else if didChangeShortcutContent {
      refreshShortcutTabContent()
    }

    if isFirstRender || didChangeAppearance {
      applyChromeAppearance()
    }

    updateShortcutTabVisibilityIfNeeded(showsShortcutTab: showsShortcutTab)
    updateShortcutPulseAnimation()
    updateQuickCreateVisibility(isHidden: hidesQuickCreate || hidesTabBar)
    updateTabBarVisibility(isHidden: hidesTabBar)
    if isFirstRender || didChangeSelectedTab || didChangeAppearance {
      syncTabSymbols(selectedTab: selectedTab)
    }
    currentSelectedMistiaTab = selectedTab

    guard #available(iOS 18.0, *) else { return }
    let identifier = selectedTab.tabIdentifier
    guard self.selectedTab?.identifier != identifier else { return }
    self.selectedTab = tab(forIdentifier: identifier)
  }

  private func configureTabsIfNeeded() {
    guard !didConfigureTabs else { return }
    didConfigureTabs = true

    if #available(iOS 18.0, *) {
      mode = .tabBar
      customizationIdentifier = "vn.com.quyln.mistia.main-tabs"

      let rootTabs = MistiaTab.nativeShellTabs.map(makeRootTab(for:))
      cachedRootTabs = Dictionary(uniqueKeysWithValues: zip(MistiaTab.nativeShellTabs, rootTabs))
      tabs = rootTabs
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
  }

  private func configureQuickCreateButtonIfNeeded() {
    guard !didConfigureQuickCreateButton else { return }
    didConfigureQuickCreateButton = true
    refreshQuickCreateRootView()

    addChild(quickCreateController)
    quickCreateController.view.translatesAutoresizingMaskIntoConstraints = false
    quickCreateController.view.backgroundColor = UIColor.clear
    view.addSubview(quickCreateController.view)
    quickCreateController.didMove(toParent: self)

    let centerXConstraint = quickCreateController.view.centerXAnchor.constraint(
      equalTo: view.leadingAnchor)
    centerXConstraint.constant = fallbackQuickCreateCenterX
    quickCreateCenterXConstraint = centerXConstraint

    NSLayoutConstraint.activate([
      quickCreateController.view.widthAnchor.constraint(equalToConstant: 44),
      quickCreateController.view.heightAnchor.constraint(equalToConstant: 44),
      centerXConstraint,
      quickCreateController.view.bottomAnchor.constraint(equalTo: tabBar.topAnchor, constant: -14),
    ])
  }

  private func refreshLocalizedContent() {
    refreshQuickCreateRootView()
    refreshShortcutTabContent()

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

  private func refreshShortcutTabContent() {
    guard #available(iOS 18.0, *), let shortcutTab else { return }

    shortcutTab.title = currentShortcutPresentation.title
    shortcutAvatarTask?.cancel()
    shortcutAvatarTask = nil
    stopSpinnerAnimation()
    shortcutTab.isEnabled = !isCurrentShortcutDisabled
    shortcutTab.accessibilityLabel = currentShortcutPresentation.accessibilityLabel
    shortcutTab.accessibilityHint = currentShortcutDisabledAccessibilityHint

    if isCurrentShortcutSyncing && !isCurrentShortcutDisabled {
      currentShortcutImageKey = "syncing_spinner"
      stopShortcutPulseAnimation()
      startSpinnerAnimation()
      return
    }

    switch currentShortcutPresentation.icon {
    case .systemImage(let systemName):
      currentShortcutImageKey = "system:\(systemName)"
      shortcutTab.image = shortcutSystemImage(systemName)

    case .currentUserAvatar(_, let avatarURL):
      currentShortcutImageKey = avatarURL?.absoluteString ?? "system:person.crop.circle.fill"

      guard let avatarURL else {
        shortcutTab.image = shortcutSystemImage("person.crop.circle.fill")
        updateShortcutPulseAnimation()
        return
      }

      if let cachedImage = shortcutAvatarImageCache[avatarURL.absoluteString] {
        shortcutTab.image = cachedImage
        updateShortcutPulseAnimation()
        return
      }

      shortcutTab.image = shortcutSystemImage("person.crop.circle.fill")
      loadShortcutAvatarImage(from: avatarURL, fallbackImage: shortcutSystemImage("person.crop.circle.fill"))

    case .memberAvatar(let initials, let avatarURL):
      let fallbackImage = makeShortcutFallbackAvatarImage(initials: initials)
      currentShortcutImageKey = avatarURL?.absoluteString ?? "member:\(initials)"

      guard let avatarURL else {
        shortcutTab.image = fallbackImage
        updateShortcutPulseAnimation()
        return
      }

      if let cachedImage = shortcutAvatarImageCache[avatarURL.absoluteString] {
        shortcutTab.image = cachedImage
        updateShortcutPulseAnimation()
        return
      }

      shortcutTab.image = fallbackImage
      loadShortcutAvatarImage(from: avatarURL, fallbackImage: fallbackImage)
    }

    updateShortcutPulseAnimation()
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
        self.shortcutTab?.image = resolvedImage
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

  private func findSearchTabButton() -> UIView? {
    guard #available(iOS 18.0, *) else { return nil }
    let control = tabBar.rightmostVisibleControl
    return control
  }

  private func startSpinnerAnimation() {
    stopSpinnerAnimation()
    stopShortcutPulseAnimation()
    guard let tabButton = findSearchTabButton() else { return }

    let iconView = tabButton.subviews.first(where: { $0 is UIImageView }) as? UIImageView
    iconView?.isHidden = true

    let indicator = UIActivityIndicatorView(style: .medium)
    indicator.color = currentShortcutTint
    indicator.translatesAutoresizingMaskIntoConstraints = false
    tabButton.addSubview(indicator)

    NSLayoutConstraint.activate([
      indicator.centerXAnchor.constraint(equalTo: tabButton.centerXAnchor),
      indicator.centerYAnchor.constraint(equalTo: iconView?.centerYAnchor ?? tabButton.centerYAnchor),
      indicator.widthAnchor.constraint(equalToConstant: 22),
      indicator.heightAnchor.constraint(equalToConstant: 22),
    ])

    spinnerActivityIndicatorView = indicator
    indicator.startAnimating()
  }

  private func stopSpinnerAnimation() {
    spinnerActivityIndicatorView?.stopAnimating()
    spinnerActivityIndicatorView?.removeFromSuperview()
    spinnerActivityIndicatorView = nil

    if let tabButton = findSearchTabButton() {
      let iconView = tabButton.subviews.first(where: { $0 is UIImageView }) as? UIImageView
      iconView?.isHidden = false
    }
  }

  private func updateShortcutPulseAnimation() {
    guard #available(iOS 18.0, *) else { return }
    guard isCurrentShortcutAttentionPulsing,
      !isCurrentShortcutDisabled,
      !isCurrentShortcutSyncing,
      let tabButton = findSearchTabButton()
    else {
      stopShortcutPulseAnimation()
      return
    }

    let pulseLayer: CAShapeLayer
    if let shortcutPulseLayer {
      pulseLayer = shortcutPulseLayer
      if pulseLayer.superlayer !== tabButton.layer {
        pulseLayer.removeFromSuperlayer()
        tabButton.layer.addSublayer(pulseLayer)
      }
    } else {
      pulseLayer = CAShapeLayer()
      pulseLayer.fillColor = UIColor.clear.cgColor
      pulseLayer.lineWidth = 2.2
      shortcutPulseLayer = pulseLayer
      tabButton.layer.addSublayer(pulseLayer)
    }

    updateShortcutPulseFrame()

    guard pulseLayer.animation(forKey: "mistia.shortcut.memberPulse") == nil else { return }

    let opacity = CABasicAnimation(keyPath: "opacity")
    opacity.fromValue = 0.82
    opacity.toValue = 0
    opacity.duration = 1.6

    let scale = CABasicAnimation(keyPath: "transform.scale")
    scale.fromValue = 1
    scale.toValue = 1.62
    scale.duration = 1.6

    let group = CAAnimationGroup()
    group.animations = [opacity, scale]
    group.duration = 2.5
    group.repeatCount = .infinity
    group.timingFunction = CAMediaTimingFunction(name: .easeOut)
    group.isRemovedOnCompletion = false

    pulseLayer.opacity = 0
    pulseLayer.add(group, forKey: "mistia.shortcut.memberPulse")
  }

  private func updateShortcutPulseFrame() {
    guard let pulseLayer = shortcutPulseLayer,
      let tabButton = findSearchTabButton()
    else { return }

    let iconView = tabButton.subviews.first(where: { $0 is UIImageView }) as? UIImageView
    let iconCenter: CGPoint
    if let iconView, let iconSuperview = iconView.superview {
      iconCenter = tabButton.convert(iconView.center, from: iconSuperview)
    } else {
      iconCenter = CGPoint(x: tabButton.bounds.midX, y: tabButton.bounds.midY - 7)
    }

    let side: CGFloat = 42
    let rect = CGRect(
      x: iconCenter.x - side / 2,
      y: iconCenter.y - side / 2,
      width: side,
      height: side
    ).integral

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    pulseLayer.frame = rect
    pulseLayer.path = UIBezierPath(
      ovalIn: CGRect(origin: .zero, size: rect.size).insetBy(dx: 1.1, dy: 1.1)
    ).cgPath
    pulseLayer.strokeColor = currentShortcutTint.cgColor
    pulseLayer.zPosition = 10
    CATransaction.commit()
  }

  private func stopShortcutPulseAnimation() {
    shortcutPulseLayer?.removeAllAnimations()
    shortcutPulseLayer?.removeFromSuperlayer()
    shortcutPulseLayer = nil
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

  private func alignQuickCreateButtonToSearchPill() {
    guard let quickCreateCenterXConstraint else { return }

    if let searchControl = tabBar.rightmostVisibleControl {
      let searchFrame = searchControl.convert(searchControl.bounds, to: view)
      quickCreateCenterXConstraint.constant = searchFrame.midX
    } else {
      quickCreateCenterXConstraint.constant = fallbackQuickCreateCenterX
    }
  }

  private func scheduleQuickCreateButtonRealignment() {
    DispatchQueue.main.async { [weak self] in
      self?.alignQuickCreateButtonToSearchPill()
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

  private func updateQuickCreateVisibility(isHidden: Bool) {
    guard didConfigureQuickCreateButton else { return }
    let targetAlpha: CGFloat = isHidden ? 0 : 1
    guard
      quickCreateController.view.alpha != targetAlpha
        || quickCreateController.view.isHidden != isHidden
    else {
      notifyQuickCreateFrameChanged()
      return
    }

    if !isHidden {
      quickCreateController.view.isHidden = false
    }

    UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseInOut]) {
      self.quickCreateController.view.alpha = targetAlpha
    } completion: { _ in
      self.quickCreateController.view.isHidden = isHidden
      self.notifyQuickCreateFrameChanged()
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
    let buttonSize = CGSize(width: 44, height: 44)
    let center = quickCreateController.view.center
    let frame = CGRect(
      x: center.x - (buttonSize.width / 2),
      y: center.y - (buttonSize.height / 2),
      width: buttonSize.width,
      height: buttonSize.height
    )
    chromeDelegate?.nativeTabBarController(self, didUpdateQuickCreateFrame: frame.integral)
  }

  private var fallbackQuickCreateCenterX: CGFloat {
    view.bounds.maxX - view.safeAreaInsets.right - 41
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

  private func syncTabSymbols(selectedTab: MistiaTab?) {
    if #available(iOS 18.0, *) {
      let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)
      for tab in MistiaTab.nativeShellTabs {
        let isSelected = tab == selectedTab
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

    // Keep the four core destinations grouped by the system before the pinned search tab.
    rootTab.preferredPlacement = UITab.Placement.fixed
    return rootTab
  }

  @available(iOS 18.0, *)
  private func makePinnedShortcutTab() -> UISearchTab {
    let searchTab = UISearchTab { _ in
      UIViewController()
    }
    searchTab.preferredPlacement = UITab.Placement.pinned
    if #available(iOS 26.0, *) {
      searchTab.automaticallyActivatesSearch = false
    }
    shortcutTab = searchTab
    refreshShortcutTabContent()
    return searchTab
  }

  private func updateShortcutTabVisibilityIfNeeded(showsShortcutTab: Bool) {
    guard #available(iOS 18.0, *) else { return }

    if showsShortcutTab {
      guard shortcutTab == nil else { return }
      tabs = tabs + [makePinnedShortcutTab()]
    } else {
      guard let shortcutTab else { return }
      var nextTabs = tabs
      nextTabs.removeAll { $0 === shortcutTab }
      tabs = nextTabs
      self.shortcutTab = nil
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
  func tabBarController(_ tabBarController: UITabBarController, shouldSelectTab tab: UITab) -> Bool
  {
    guard let shortcutTab, tab === shortcutTab else { return true }
    if isCurrentShortcutSyncing || isCurrentShortcutDisabled {
      return false
    }
    chromeDelegate?.nativeTabBarControllerDidTapShortcut(self)
    return false
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
        .font(.system(size: 20, weight: .semibold, design: .rounded))
        .foregroundStyle(MistiaAccent.checkmarkPurple.color)
        .frame(width: 44, height: 44)
    }
    .buttonStyle(.glassProminent)
    .buttonBorderShape(.circle)
    .tint(Color(red: 0.43, green: 0.23, blue: 0.76))
    .shadow(color: Color.black.opacity(0.18), radius: 16, y: 8)
    .accessibilityLabel(
      L10n.app.mistianativetab.quickCreate
    )
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

extension UIView {
  fileprivate var rightmostVisibleControl: UIControl? {
    allDescendantControls
      .filter { control in
        !control.isHidden && control.alpha > 0.01 && control.bounds.width > 20
          && control.bounds.height > 20
      }
      .max { lhs, rhs in
        let lhsFrame = lhs.convert(lhs.bounds, to: self)
        let rhsFrame = rhs.convert(rhs.bounds, to: self)
        return lhsFrame.midX < rhsFrame.midX
      }
  }

  private var allDescendantControls: [UIControl] {
    var controls: [UIControl] = []
    accumulateDescendantControls(in: self, result: &controls)
    return controls
  }

  private func accumulateDescendantControls(in view: UIView, result: inout [UIControl]) {
    for subview in view.subviews {
      if let control = subview as? UIControl {
        result.append(control)
      }
      accumulateDescendantControls(in: subview, result: &result)
    }
  }
}
