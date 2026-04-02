import SwiftUI
import UIKit

struct MistiaNativeTabShell: UIViewControllerRepresentable {
  @Binding var selectedTab: MistiaTab
  var appearanceMode: MistiaAppearanceMode
  var hidesQuickCreate: Bool
  var onAssistantTap: () -> Void
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
      hidesQuickCreate: hidesQuickCreate
    )
    return controller
  }

  func updateUIViewController(_ controller: MistiaNativeTabBarController, context: Context) {
    context.coordinator.parent = self
    controller.chromeDelegate = context.coordinator
    controller.render(
      selectedTab: selectedTab,
      appearanceMode: appearanceMode,
      hidesQuickCreate: hidesQuickCreate
    )
  }

  final class Coordinator: NSObject, MistiaNativeTabBarControllerDelegate {
    var parent: MistiaNativeTabShell

    init(parent: MistiaNativeTabShell) {
      self.parent = parent
    }

    func nativeTabBarController(
      _ controller: MistiaNativeTabBarController, didSelect tab: MistiaTab
    ) {
      guard parent.selectedTab != tab else { return }
      parent.selectedTab = tab
    }

    func nativeTabBarControllerDidTapAssistant(_ controller: MistiaNativeTabBarController) {
      parent.onAssistantTap()
    }

    func nativeTabBarControllerDidTapQuickCreate(_ controller: MistiaNativeTabBarController) {
      parent.onQuickCreateTap()
    }

    func nativeTabBarController(
      _ controller: MistiaNativeTabBarController, didUpdateQuickCreateFrame frame: CGRect
    ) {
      parent.onQuickCreateFrameChange(frame)
    }
  }
}

protocol MistiaNativeTabBarControllerDelegate: AnyObject {
  func nativeTabBarController(_ controller: MistiaNativeTabBarController, didSelect tab: MistiaTab)
  func nativeTabBarControllerDidTapAssistant(_ controller: MistiaNativeTabBarController)
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
  private weak var assistantTab: UISearchTab?
  private var quickCreateCenterXConstraint: NSLayoutConstraint?
  private var currentAppearanceMode: MistiaAppearanceMode = .automatic

  private lazy var quickCreateController = UIHostingController(
    rootView: MistiaQuickCreateFloatingButton { [weak self] in
      guard let self else { return }
      chromeDelegate?.nativeTabBarControllerDidTapQuickCreate(self)
    }
  )

  override func viewDidLoad() {
    super.viewDidLoad()
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

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    alignQuickCreateButtonToSearchPill()
    notifyQuickCreateFrameChanged()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    scheduleQuickCreateButtonRealignment()
  }

  func render(selectedTab: MistiaTab, appearanceMode: MistiaAppearanceMode, hidesQuickCreate: Bool)
  {
    configureTabsIfNeeded()
    configureQuickCreateButtonIfNeeded()
    currentAppearanceMode = appearanceMode
    overrideUserInterfaceStyle = appearanceMode.interfaceStyle
    applyChromeAppearance()
    updateQuickCreateVisibility(isHidden: hidesQuickCreate)
    syncTabSymbols(selectedTab: selectedTab)

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
      let searchTab = makeAssistantSearchTab()
      tabs = rootTabs + [searchTab]
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

    addChild(quickCreateController)
    quickCreateController.view.translatesAutoresizingMaskIntoConstraints = false
    quickCreateController.view.backgroundColor = .clear
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
  private func makeAssistantSearchTab() -> UISearchTab {
    let searchTab = UISearchTab { _ in
      UIViewController()
    }
    let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)
    searchTab.image = UIImage(systemName: "apple.intelligence", withConfiguration: config)
    searchTab.preferredPlacement = UITab.Placement.pinned
    if #available(iOS 26.0, *) {
      searchTab.automaticallyActivatesSearch = false
    }
    assistantTab = searchTab
    return searchTab
  }

  private func viewController(for tab: MistiaTab) -> UIViewController {
    if let cachedController = cachedControllers[tab] {
      return cachedController
    }

    let host = UIHostingController(rootView: tab.nativeRootView)
    host.view.backgroundColor = .clear
    host.title = tab.title
    cachedControllers[tab] = host
    return host
  }

  @available(iOS 18.0, *)
  func tabBarController(_ tabBarController: UITabBarController, shouldSelectTab tab: UITab) -> Bool
  {
    guard let assistantTab, tab === assistantTab else { return true }
    chromeDelegate?.nativeTabBarControllerDidTapAssistant(self)
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
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: "plus")
        .font(.system(size: 20, weight: .semibold, design: .rounded))
        .foregroundStyle(Color(red: 0.88, green: 0.78, blue: 1.0))
        .frame(width: 44, height: 44)
    }
    .buttonStyle(.glassProminent)
    .buttonBorderShape(.circle)
    .tint(Color(red: 0.43, green: 0.23, blue: 0.76))
    .shadow(color: Color.black.opacity(0.18), radius: 16, y: 8)
    .accessibilityLabel("Tạo nhanh")
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
    subviews.flatMap { subview -> [UIControl] in
      let nestedControls = subview.allDescendantControls
      if let control = subview as? UIControl {
        return [control] + nestedControls
      }
      return nestedControls
    }
  }
}
