import SwiftUI
import UIKit

struct MistiaNativeTabShell: UIViewControllerRepresentable {
    @Binding var selectedTab: MistiaTab
    var appearanceMode: MistiaAppearanceMode
    var hidesQuickCreate: Bool
    var onAssistantTap: () -> Void
    var onQuickCreateTap: () -> Void

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

        func nativeTabBarController(_ controller: MistiaNativeTabBarController, didSelect tab: MistiaTab) {
            guard parent.selectedTab != tab else { return }
            parent.selectedTab = tab
        }

        func nativeTabBarControllerDidTapAssistant(_ controller: MistiaNativeTabBarController) {
            parent.onAssistantTap()
        }

        func nativeTabBarControllerDidTapQuickCreate(_ controller: MistiaNativeTabBarController) {
            parent.onQuickCreateTap()
        }
    }
}

protocol MistiaNativeTabBarControllerDelegate: AnyObject {
    func nativeTabBarController(_ controller: MistiaNativeTabBarController, didSelect tab: MistiaTab)
    func nativeTabBarControllerDidTapAssistant(_ controller: MistiaNativeTabBarController)
    func nativeTabBarControllerDidTapQuickCreate(_ controller: MistiaNativeTabBarController)
}

final class MistiaNativeTabBarController: UITabBarController, UITabBarControllerDelegate {
    weak var chromeDelegate: MistiaNativeTabBarControllerDelegate?

    private let mistiaAccentColor = UIColor(red: 0.43, green: 0.23, blue: 0.76, alpha: 1)
    private let mistiaDarkModeTabTintColor = UIColor(red: 0.76, green: 0.64, blue: 0.97, alpha: 1)

    private var didConfigureTabs = false
    private var didConfigureQuickCreateButton = false
    private var cachedControllers: [MistiaTab: UIViewController] = [:]
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
            }
        }
        configureTabsIfNeeded()
        configureSystemTabBar()
        configureQuickCreateButtonIfNeeded()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        alignQuickCreateButtonToSearchPill()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        scheduleQuickCreateButtonRealignment()
    }

    func render(selectedTab: MistiaTab, appearanceMode: MistiaAppearanceMode, hidesQuickCreate: Bool) {
        configureTabsIfNeeded()
        configureQuickCreateButtonIfNeeded()
        currentAppearanceMode = appearanceMode
        overrideUserInterfaceStyle = appearanceMode.interfaceStyle
        applyChromeAppearance()
        updateQuickCreateVisibility(isHidden: hidesQuickCreate)

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
            let searchTab = makeAssistantSearchTab()
            tabs = rootTabs + [searchTab]
            selectedTab = rootTabs.first
        } else {
            let controllers = MistiaTab.nativeShellTabs.map(viewController(for:))
            viewControllers = controllers
            selectedIndex = 0
        }
    }

    private func configureSystemTabBar() {
        tabBar.isTranslucent = true
        tabBar.tintColor = mistiaAccentColor
        if #available(iOS 26.0, *) {
            tabBarMinimizeBehavior = .never
        }
    }

    private func configureQuickCreateButtonIfNeeded() {
        guard !didConfigureQuickCreateButton else { return }
        didConfigureQuickCreateButton = true

        addChild(quickCreateController)
        quickCreateController.view.translatesAutoresizingMaskIntoConstraints = false
        quickCreateController.view.backgroundColor = .clear
        view.addSubview(quickCreateController.view)
        quickCreateController.didMove(toParent: self)

        let centerXConstraint = quickCreateController.view.centerXAnchor.constraint(equalTo: view.leadingAnchor)
        centerXConstraint.constant = fallbackQuickCreateCenterX
        quickCreateCenterXConstraint = centerXConstraint

        NSLayoutConstraint.activate([
            quickCreateController.view.widthAnchor.constraint(equalToConstant: 50),
            quickCreateController.view.heightAnchor.constraint(equalToConstant: 50),
            centerXConstraint,
            quickCreateController.view.bottomAnchor.constraint(equalTo: tabBar.topAnchor, constant: -14)
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
        tabBar.tintColor = usesDarkTint ? mistiaDarkModeTabTintColor : mistiaAccentColor
    }

    private func updateQuickCreateVisibility(isHidden: Bool) {
        guard didConfigureQuickCreateButton else { return }
        let targetAlpha: CGFloat = isHidden ? 0 : 1
        guard quickCreateController.view.alpha != targetAlpha || quickCreateController.view.isHidden != isHidden else {
            return
        }

        if !isHidden {
            quickCreateController.view.isHidden = false
        }

        UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseInOut]) {
            self.quickCreateController.view.alpha = targetAlpha
            self.quickCreateController.view.transform = isHidden
                ? CGAffineTransform(scaleX: 0.88, y: 0.88)
                : .identity
        } completion: { _ in
            self.quickCreateController.view.isHidden = isHidden
        }
    }

    private var fallbackQuickCreateCenterX: CGFloat {
        view.bounds.maxX - view.safeAreaInsets.right - 41
    }

    @available(iOS 18.0, *)
    private func makeRootTab(for tab: MistiaTab) -> UITab {
        let rootTab = UITab(
            title: tab.title,
            image: UIImage(systemName: tab.systemImage),
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
        searchTab.image = UIImage(systemName: "apple.intelligence")
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
    func tabBarController(_ tabBarController: UITabBarController, shouldSelectTab tab: UITab) -> Bool {
        guard let assistantTab, tab === assistantTab else { return true }
        chromeDelegate?.nativeTabBarControllerDidTapAssistant(self)
        return false
    }

    @available(iOS 18.0, *)
    func tabBarController(_ tabBarController: UITabBarController, didSelectTab selectedTab: UITab, previousTab: UITab?) {
        guard let tab = MistiaTab(identifier: selectedTab.identifier) else { return }
        chromeDelegate?.nativeTabBarController(self, didSelect: tab)
    }

    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        guard
            let viewControllers,
            let index = viewControllers.firstIndex(of: viewController),
            let tab = MistiaTab.nativeShellTabs[safe: index]
        else { return }

        chromeDelegate?.nativeTabBarController(self, didSelect: tab)
    }
}

private struct MistiaQuickCreateFloatingButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 50, height: 50)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .tint(Color(red: 0.43, green: 0.23, blue: 0.76))
        .shadow(color: Color.black.opacity(0.18), radius: 16, y: 8)
        .accessibilityLabel("Tạo nhanh")
    }
}

private extension MistiaTab {
    static let nativeShellTabs: [MistiaTab] = [.overview, .transactions, .planning, .settings]

    var tabIdentifier: String {
        "mistia.tab.\(rawValue)"
    }

    init?(identifier: String) {
        guard let rawValue = identifier.split(separator: ".").last.map(String.init) else {
            return nil
        }
        self.init(rawValue: rawValue)
    }

    var nativeRootView: AnyView {
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

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension UIView {
    var rightmostVisibleControl: UIControl? {
        allDescendantControls
            .filter { control in
                !control.isHidden &&
                control.alpha > 0.01 &&
                control.bounds.width > 20 &&
                control.bounds.height > 20
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
