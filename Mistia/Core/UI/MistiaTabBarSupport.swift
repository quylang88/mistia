import SwiftUI

struct MistiaTabBarHiddenPreferenceKey: PreferenceKey {
    static var defaultValue: Bool = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

extension View {
    func mistiaTabBarHidden(_ hidden: Bool) -> some View {
        preference(key: MistiaTabBarHiddenPreferenceKey.self, value: hidden)
    }
}
