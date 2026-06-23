# Spec: Tab Bar Plus Button Animation Optimization

This specification outlines the changes required to fix the animation of the plus button on the tab bar when opening and closing the quick create menu, making it smooth and seamless.

## User Review Required

> [!IMPORTANT]
> The solution optimizes transition timing and visibility handoff between UIKit and SwiftUI views, avoiding a full SwiftUI tab bar rewrite.

## Proposed Changes

### UIKit Tab Bar Shell

#### [MODIFY] [MistiaNativeTabShell.swift](file:///Users/quylang/Projects/mistia/Mistia/App/MistiaNativeTabShell.swift)
* Add a boolean parameter `isMenuVisible` to the `render` method of `MistiaNativeTabShell` and `MistiaNativeTabBarController`.
* Update `updateQuickCreateVisibility` in `MistiaNativeTabBarController` to:
  * When `isHidden` is true because the menu is opening (`isMenuVisible == true`), set alpha = 0 and `isHidden = true` **instantly** without animation.
  * When `isHidden` is false because the menu has finished closing, set alpha = 1 and `isHidden = false` **instantly** without animation.
  * For other visibility changes (e.g., keyboard showing/hiding), maintain the smooth 0.18s fade animation.

### SwiftUI Root View

#### [MODIFY] [RootTabView.swift](file:///Users/quylang/Projects/mistia/Mistia/App/RootTabView.swift)
* Pass `isQuickCreateMenuVisible` into `MistiaNativeTabShell` as the new `isMenuVisible` property:
  ```swift
  MistiaNativeTabShell(
    ...
    isMenuVisible: isQuickCreateMenuVisible,
    ...
  )
  ```
* Modify `MistiaQuickCreateMenuBackground` to interpolate the background color and border:
  * Animate the fill color from the button's purple tint (`Color(red: 0.43, green: 0.23, blue: 0.76)`) to the card surface color (`expandedSurfaceColor`) using `isExpanded`.
  * Animate the border stroke from `Color.clear` to `expandedBorderColor`.
* In `RootTabView`, ensure that the transition handoff timing is perfectly clean by coordinating the states.

## Verification Plan

### Manual Verification
* Run the application on an iOS Simulator/Device.
* Tap the plus button to open the quick create menu: verify that the button morphs smoothly into the menu background without doubling/ghosting.
* Swipe down or tap outside to close the menu: verify that the menu collapses back to the button size and swaps back to the tab bar button instantly without any blink, fade, or visual gap.
