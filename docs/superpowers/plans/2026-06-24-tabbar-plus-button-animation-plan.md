# Tab Bar Plus Button Animation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the tab bar plus button opening/closing animation by performing an instant visibility handoff and morphing the menu background during expansion.

**Architecture:** Coordinate state between the native tab bar controller and the SwiftUI overlay. Hide the UIKit native button instantly when the menu opens, replacing it with the SwiftUI overlay button, and swap them back on close completion. Animate the overlay background fill color dynamically from purple to gray/white during expansion.

**Tech Stack:** SwiftUI, UIKit Integration (`UIViewControllerRepresentable`), Swift

---

### Task 1: Update MistiaNativeTabShell Interface and Visibility Logic

**Files:**
* Modify: [MistiaNativeTabShell.swift](file:///Users/quylang/Projects/mistia/Mistia/App/MistiaNativeTabShell.swift)

- [ ] **Step 1: Add isMenuVisible property to MistiaNativeTabShell**
  Update the properties of `MistiaNativeTabShell` around line 18 to include `var isMenuVisible: Bool`:
  ```swift
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
    var isMenuVisible: Bool // NEW PROPERTY
    var onShortcutTap: () -> Void
    ...
  ```

- [ ] **Step 2: Update render signature in MistiaNativeTabBarController**
  Modify the `render` method of `MistiaNativeTabBarController` to accept `isMenuVisible: Bool` and pass it to the visibility update:
  ```swift
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
      isMenuVisible: Bool // NEW PARAMETER
    )
    {
      ...
      updateQuickCreateVisibility(isHidden: hidesQuickCreate || hidesTabBar, isMenuVisible: isMenuVisible)
      ...
    }
  ```

- [ ] **Step 3: Update makeUIViewController and updateUIViewController in MistiaNativeTabShell**
  Modify both methods to pass the new `isMenuVisible` value into `controller.render(...)`:
  ```swift
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
        isMenuVisible: isMenuVisible // PASS NEW PROPERTY
      )
      return controller
    }
  ```

- [ ] **Step 4: Update updateQuickCreateVisibility to hide/show instantly when toggled by menu**
  Modify `updateQuickCreateVisibility` in `MistiaNativeTabBarController` to check `isMenuVisible` and bypass the 0.18s alpha animation:
  ```swift
    private func updateQuickCreateVisibility(isHidden: Bool, isMenuVisible: Bool) {
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

      if isMenuVisible {
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
    }
  ```

- [ ] **Step 5: Verify core compilation**
  Run `swift build` to verify SPM core logic is not broken.
  Expected: Successful compilation of the SPM library target.

- [ ] **Step 6: Commit (if auto_commit enabled)**
  Check `.agent/config.yml` for `auto_commit` setting.
  If `auto_commit: false`, skip commit and print: "Skipping commit (auto_commit: false)."

---

### Task 2: Pass state in RootTabView and update Morphing Background

**Files:**
* Modify: [RootTabView.swift](file:///Users/quylang/Projects/mistia/Mistia/App/RootTabView.swift)

- [ ] **Step 1: Pass isMenuVisible into MistiaNativeTabShell**
  Locate `MistiaNativeTabShell` inside the body of `RootTabView` (around line 110-132) and pass the `isMenuVisible` value:
  ```swift
          MistiaNativeTabShell(
            selectedTab: $selectedTab,
            appearanceMode: appearanceMode,
            appLanguage: appLanguage,
            hidesQuickCreate: MistiaRootChromeLogic.hidesQuickCreate(
              transientHidden: uiState.isQuickCreateHidden,
              menuVisible: isQuickCreateMenuVisible
            ),
            hidesTabBar: uiState.isTabBarHidden,
            showsShortcutTab: mistiaShortcutEnabled && !shouldHideShortcutTabInCurrentContext,
            isShortcutSyncing: isSyncingShortcut && !isPinnedShortcutDisabled,
            isShortcutDisabled: isPinnedShortcutDisabled,
            isShortcutAttentionPulsing: isShortcutMemberAttentionPulsing,
            shortcutDisabledAccessibilityHint: shortcutDisabledAccessibilityHint,
            shortcutPresentation: shortcutResolution.presentation,
            isMenuVisible: isQuickCreateMenuVisible, // PASS STATE
            onShortcutTap: handlePinnedShortcutTap,
            onQuickCreateTap: toggleQuickCreateMenu,
            onQuickCreateFrameChange: { frame in
              if !isQuickCreateMenuVisible {
                quickCreateButtonFrame = frame
              }
            }
          )
  ```

- [ ] **Step 2: Update MistiaQuickCreateMenuBackground to morph colors**
  Modify `MistiaQuickCreateMenuBackground` (around lines 939-978) to dynamically morph its background fill color and border:
  ```swift
  private struct MistiaQuickCreateMenuBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat
    let isExpanded: Bool
    private let appPurple = Color(red: 0.43, green: 0.23, blue: 0.76)

    var body: some View {
      let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

      ZStack {
        // Morphs fill color from purple (button tint) to card color
        shape
          .fill(isExpanded ? expandedSurfaceColor : appPurple)

        LinearGradient(
          colors: [
            Color.white.opacity(colorScheme == .dark ? 0.08 : 0.36),
            Color.clear
          ],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
        .opacity(isExpanded ? 1 : 0)
        .clipShape(shape)

        // Morphs border from clear to outline
        shape
          .strokeBorder(isExpanded ? expandedBorderColor : Color.clear, lineWidth: 0.8)
      }
    }
    ...
  ```

- [ ] **Step 3: Verify build**
  Run `swift build` to ensure no compile errors are introduced.
  Expected: Successful compilation.

- [ ] **Step 4: Commit (if auto_commit enabled)**
  Check `.agent/config.yml` for `auto_commit` setting.
  If `auto_commit: false`, skip commit and print: "Skipping commit (auto_commit: false)."
