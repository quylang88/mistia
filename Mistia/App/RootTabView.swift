import SwiftUI
import SwiftData

enum MistiaTab: String, CaseIterable, Hashable {
  case overview
  case transactions
  case planning
  case settings

  var title: String {
    switch self {
    case .overview:
      mistiaLocalized(vi: "Tổng quan", en: "Overview", ja: "概要")
    case .transactions:
      mistiaLocalized(vi: "Giao dịch", en: "Transactions", ja: "取引")
    case .planning:
      mistiaLocalized(vi: "Kế hoạch", en: "Planning", ja: "計画")
    case .settings:
      mistiaLocalized(vi: "Quản lý", en: "Manage", ja: "管理")
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
  @Environment(\.modelContext) private var modelContext
  @AppStorage(MistiaAppStorageKey.appearanceMode) private var appearanceModeRawValue =
    MistiaAppearanceMode.automatic.rawValue
  @AppStorage(MistiaAppStorageKey.appLanguage) private var appLanguageRawValue = MistiaAppLanguage.english.rawValue
  @AppStorage(MistiaAppStorageKey.hideQuickCreate) private var hideQuickCreate = false
  @State private var selectedTab: MistiaTab = .overview
  @State private var isQuickCreateMenuVisible = false
  @State private var isQuickCreateMenuExpanded = false
  @State private var activeSheet: RootSheet?
  @State private var quickCreateButtonFrame: CGRect = .zero
  @State private var quickCreateAnchorFrame: CGRect = .zero

  private let quickCreateMenuAnimation = Animation.spring(response: 0.34, dampingFraction: 0.84)
  private let quickCreateMenuDuration = 0.28

  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .bottomTrailing) {
        MistiaNativeTabShell(
          selectedTab: $selectedTab,
          appearanceMode: appearanceMode,
          appLanguage: appLanguage,
          hidesQuickCreate: hideQuickCreate || isQuickCreateMenuVisible,
          onAssistantTap: {
            dismissQuickCreateMenu()
            activeSheet = .assistant
          },
          onQuickCreateTap: toggleQuickCreateMenu,
          onQuickCreateFrameChange: { frame in
            if !isQuickCreateMenuVisible {
              quickCreateButtonFrame = frame
            }
          }
        )
        .ignoresSafeArea()

        if isQuickCreateMenuVisible, quickCreateAnchorFrame.width > 0 {
          Color.black
            .opacity(isQuickCreateMenuExpanded ? (colorScheme == .dark ? 0.18 : 0.08) : 0)
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture(perform: dismissQuickCreateMenu)
            .animation(quickCreateMenuAnimation, value: isQuickCreateMenuExpanded)

          MistiaQuickCreateMenu(
            isExpanded: isQuickCreateMenuExpanded,
            expandedWidth: max(
              quickCreateAnchorFrame.maxX - 12, MistiaQuickCreateMenu.collapsedSize)
          ) { destination in
            presentQuickCreateSheet(for: destination)
          }
          .position(quickCreateMenuPosition(in: proxy))
        }
      }
    }
    .sheet(item: $activeSheet) { sheet in
      switch sheet {
      case .assistant:
        MistiaAssistantSheet()
          .presentationDetents([.medium])
          .presentationDragIndicator(.visible)
      case .quickCreate(let destination):
        TransactionEditorSheet(target: quickCreateTarget(for: destination)) { completion in
          if completion == .savedDraft {
            selectedTab = .transactions
          }
        }
          .presentationDetents(destination == .note ? [.medium, .large] : [.large])
          .presentationDragIndicator(.visible)
      }
    }
    .task {
      try? MistiaBootstrap.seedDefaultCategoriesIfNeeded(modelContext: modelContext)
    }
    .onChange(of: hideQuickCreate) { _, newValue in
      if newValue {
        dismissQuickCreateMenu()
      }
    }
    .onChange(of: selectedTab) { _, _ in
      dismissQuickCreateMenu()
    }
  }

  private var appearanceMode: MistiaAppearanceMode {
    MistiaAppearanceMode(rawValue: appearanceModeRawValue) ?? .automatic
  }

  private var appLanguage: MistiaAppLanguage {
    MistiaAppLanguage.resolve(storedRawValue: appLanguageRawValue)
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
      activeSheet = .quickCreate(destination)
    }
  }

  private func presentQuickCreateMenu() {
    guard !hideQuickCreate else { return }
    guard quickCreateButtonFrame.width > 0 else { return }

    quickCreateAnchorFrame = quickCreateButtonFrame
    isQuickCreateMenuVisible = true
    isQuickCreateMenuExpanded = false

    DispatchQueue.main.async {
      withAnimation(quickCreateMenuAnimation) {
        isQuickCreateMenuExpanded = true
      }
    }
  }

  private func quickCreateTarget(for destination: MistiaQuickCreateDestination) -> TransactionEditorTarget {
    switch destination {
    case .expense:
      TransactionEditorTarget(initialKind: .expense)
    case .income:
      TransactionEditorTarget(initialKind: .income)
    case .transfer:
      TransactionEditorTarget(initialKind: .transfer)
    case .note:
      TransactionEditorTarget(initialKind: .expense, quickCapture: true)
    }
  }

  private func quickCreateMenuPosition(in proxy: GeometryProxy) -> CGPoint {
    let width =
      isQuickCreateMenuExpanded
      ? max(quickCreateAnchorFrame.maxX - 12, MistiaQuickCreateMenu.collapsedSize)
      : MistiaQuickCreateMenu.collapsedSize
    let height =
      isQuickCreateMenuExpanded
      ? MistiaQuickCreateMenu.expandedHeight
      : MistiaQuickCreateMenu.collapsedSize

    let x = quickCreateAnchorFrame.maxX - (width / 2)
    let safeAreaOffset = proxy.safeAreaInsets.top
    let y = quickCreateAnchorFrame.maxY - (height / 2) - safeAreaOffset

    return CGPoint(
      x: min(max(x, width / 2), proxy.size.width - (width / 2)),
      y: min(max(y, height / 2), proxy.size.height - (height / 2))
    )
  }
}

private enum RootSheet: Identifiable {
  case assistant
  case quickCreate(MistiaQuickCreateDestination)

  var id: String {
    switch self {
    case .assistant:
      "assistant"
    case .quickCreate(let destination):
      "quick-create-\(destination.rawValue)"
    }
  }
}

private struct MistiaAssistantSheet: View {
  var body: some View {
    ZStack {
      MistiaBackgroundView()

      VStack(spacing: 18) {
        Text("Mistia Assistant")
          .font(.system(size: 24, weight: .bold, design: .rounded))

        MistiaGlassCard(
          cornerRadius: 28,
          tint: Color(red: 0.29, green: 0.50, blue: 0.96).opacity(0.14)
        ) {
          VStack(spacing: 14) {
            ZStack {
              MistiaRoundedGlassBackground(
                cornerRadius: 24,
                tint: Color.white.opacity(0.08)
              )

              MistiaAssistantGlyph(isCompact: false)
            }
            .frame(width: 76, height: 76)

            Text(
              "Tab AI assistant đang được giữ chỗ để hoàn thiện UI trước, chưa nối logic chat hoặc automation."
            )
            .multilineTextAlignment(.center)
            .font(.system(size: 15, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity)
        }
      }
      .padding(.horizontal, 20)
    }
  }
}

private enum MistiaQuickCreateDestination: String, CaseIterable, Identifiable {
  case expense
  case income
  case transfer
  case note

  var id: String { rawValue }

  var title: String {
    switch self {
    case .expense:
      mistiaLocalized(vi: "Chi tiêu", en: "Expense", ja: "支出")
    case .income:
      mistiaLocalized(vi: "Thu nhập", en: "Income", ja: "収入")
    case .transfer:
      mistiaLocalized(vi: "Chuyển tiền", en: "Transfer", ja: "振替")
    case .note:
      mistiaLocalized(vi: "Ghi nhanh", en: "Quick note", ja: "クイック入力")
    }
  }

  var subtitle: String {
    switch self {
    case .expense:
      mistiaLocalized(vi: "Lưu lại khoản chi tiêu từ ví cá nhân.", en: "Save an expense from a personal wallet.", ja: "個人のウォレットから支出を記録します。")
    case .income:
      mistiaLocalized(vi: "Ghi nhận nguồn thu để cập nhật số dư.", en: "Record income to update your balance.", ja: "残高を更新するための収入を記録します。")
    case .transfer:
      mistiaLocalized(vi: "Chuyển nội bộ hoặc theo dõi công nợ.", en: "Move money internally or track debt.", ja: "内部振替や貸し借りを記録します。")
    case .note:
      mistiaLocalized(vi: "Chỉ nhập số tiền và loại để hoàn thiện sau.", en: "Capture amount and type first, then complete later.", ja: "金額と種類だけ先に入れて、あとで詳細を整えます。")
    }
  }

  var placeholderMessage: String {
    switch self {
    case .expense:
      mistiaLocalized(vi: "Flow tạo khoản chi sẽ đi từ menu popout này. Hiện tại mình đã chốt interaction để bạn duyệt UI trước.", en: "The expense flow will connect from this popout menu. The interaction is locked in for UI review first.", ja: "支出作成フローはこのポップアウトメニューから接続されます。まずは UI レビュー用に操作感を固定しています。")
    case .income:
      mistiaLocalized(vi: "Flow thêm thu nhập sẽ nối từ menu này. Hiện tại đang giữ chỗ bằng sheet riêng để state không phải làm lại.", en: "The income flow will connect from this menu. A separate placeholder sheet keeps the state wiring stable for now.", ja: "収入追加フローはこのメニューから接続されます。今は状態管理を崩さないためにプレースホルダーのシートを使っています。")
    case .transfer:
      mistiaLocalized(vi: "Flow chuyển tiền giữa các nguồn sẽ được nối tại đây sau. Menu popout mới đã tách sẵn action riêng cho màn này.", en: "Transfers between sources will be connected here next. The new popout menu already separates the action for this screen.", ja: "資金移動フローはここに後で接続されます。この画面用のアクションは新しいポップアウトメニューですでに分かれています。")
    case .note:
      mistiaLocalized(vi: "Ghi nhanh sẽ dùng cho những entry cần capture thật gọn. Trước mắt đây là placeholder để bạn duyệt layout và nhịp mở menu.", en: "Quick capture is for ultra-light entries. For now this is a placeholder so you can review layout and menu timing.", ja: "クイック入力は最小限の記録向けです。今はレイアウトとメニューの開き方を確認するためのプレースホルダーです。")
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
    case .note:
      "square.and.pencil"
    }
  }

  var accent: Color {
    switch self {
    case .expense:
      Color(red: 0.94, green: 0.47, blue: 0.40)
    case .income:
      Color(red: 0.25, green: 0.79, blue: 0.61)
    case .transfer:
      Color(red: 0.31, green: 0.62, blue: 0.98)
    case .note:
      Color(red: 0.43, green: 0.23, blue: 0.76)
    }
  }
}

private struct MistiaQuickCreateMenu: View {
  static let collapsedSize: CGFloat = 44
  static let expandedHeight: CGFloat = 350

  @Environment(\.colorScheme) private var colorScheme
  let isExpanded: Bool
  let expandedWidth: CGFloat
  let onSelect: (MistiaQuickCreateDestination) -> Void

  private var expandedTint: Color {
    colorScheme == .dark ? .white.opacity(0.04) : .white.opacity(0.58)
  }

  private var collapsedTint: Color {
    Color(red: 0.43, green: 0.23, blue: 0.76).opacity(colorScheme == .dark ? 0.18 : 0.12)
  }

  private var cornerRadius: CGFloat {
    isExpanded ? 34 : 25
  }

  private var menuHeight: CGFloat {
    isExpanded ? Self.expandedHeight : Self.collapsedSize
  }

  var body: some View {
    ZStack(alignment: .bottomTrailing) {
      if isExpanded {
        VStack(spacing: 0) {
          ForEach(Array(MistiaQuickCreateDestination.allCases.enumerated()), id: \.element.id) {
            index, destination in
            Button {
              onSelect(destination)
            } label: {
              MistiaQuickCreateMenuRow(destination: destination)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
            }
            .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 24, tint: destination.accent))

            if index < MistiaQuickCreateDestination.allCases.count - 1 {
              Divider()
                .padding(.leading, 84)
                .padding(.trailing, 10)
            }
          }
        }
        .padding(4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .opacity(isExpanded ? 1 : 0)
        .scaleEffect(isExpanded ? 1 : 0.96, anchor: .bottomTrailing)
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
                .animation(.easeInOut(duration: 0.16), value: isExpanded)
        }
        .animation(.easeInOut(duration: 0.16), value: isExpanded)
    }
    .frame(
      width: isExpanded ? max(expandedWidth, Self.collapsedSize) : Self.collapsedSize,
      height: menuHeight,
      alignment: .bottomTrailing
    )
    .background {
      MistiaRoundedGlassBackground(
        cornerRadius: cornerRadius,
        tint: isExpanded ? expandedTint : collapsedTint,
        interactive: true
      )
    }
    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    .shadow(color: .black.opacity(colorScheme == .dark ? 0.26 : 0.10), radius: 22, y: 14)
    .allowsHitTesting(isExpanded)
    .accessibilityElement(children: .contain)
  }
}

private struct MistiaQuickCreateMenuRow: View {
  @Environment(\.colorScheme) private var colorScheme
  let destination: MistiaQuickCreateDestination

  private var iconTint: Color {
    colorScheme == .dark ? destination.accent.opacity(0.24) : destination.accent.opacity(0.18)
  }

  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      Image(systemName: destination.systemImage)
        .font(.system(size: 22, weight: .medium, design: .rounded))
        .foregroundStyle(.white.opacity(0.98))
        .frame(width: 54, height: 54)
        .background {
          MistiaRoundedGlassBackground(
            cornerRadius: 18,
            tint: iconTint,
            interactive: true
          )
        }

      VStack(alignment: .leading, spacing: 5) {
        Text(destination.title)
          .font(.system(size: 18, weight: .bold, design: .rounded))
          .foregroundStyle(.primary)

        Text(destination.subtitle)
          .font(.system(size: 13.5, weight: .medium, design: .rounded))
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.leading)
          .lineLimit(2)
      }

      Spacer(minLength: 8)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
  }
}

private struct MistiaAssistantGlyph: View {
  let isCompact: Bool

  var body: some View {
    Image(systemName: "magnifyingglass")
      .font(.system(size: isCompact ? 18 : 22, weight: .semibold, design: .rounded))
      .foregroundStyle(.white.opacity(0.96))
      .shadow(color: .black.opacity(0.12), radius: isCompact ? 4 : 8, y: 2)
  }
}
