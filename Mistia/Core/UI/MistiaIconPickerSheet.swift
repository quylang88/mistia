import SwiftUI

enum MistiaIconGroupID: String, CaseIterable, Identifiable {
    case finance
    case shopping
    case food
    case home
    case utilities
    case transport
    case travel
    case health
    case work
    case entertainment
    case personal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .finance:
            L10n.core.ui.mistiaiconpicker.finance
        case .shopping:
            L10n.core.ui.mistiaiconpicker.shopping
        case .food:
            L10n.core.ui.mistiaiconpicker.food
        case .home:
            L10n.core.ui.mistiaiconpicker.home
        case .utilities:
            L10n.core.ui.mistiaiconpicker.billsUtilities
        case .transport:
            L10n.core.ui.mistiaiconpicker.transport
        case .travel:
            L10n.core.ui.mistiaiconpicker.travel
        case .health:
            L10n.core.ui.mistiaiconpicker.health
        case .work:
            L10n.core.ui.mistiaiconpicker.workStudy
        case .entertainment:
            L10n.core.ui.mistiaiconpicker.entertainment
        case .personal:
            L10n.core.ui.mistiaiconpicker.goalsPersonal
        }
    }

    var filterSymbolName: String {
        switch self {
        case .finance:
            "wallet.pass.fill"
        case .shopping:
            "bag.fill"
        case .food:
            "fork.knife"
        case .home:
            "house.fill"
        case .utilities:
            "bolt.fill"
        case .transport:
            "car.fill"
        case .travel:
            "airplane"
        case .health:
            "cross.case.fill"
        case .work:
            "briefcase.fill"
        case .entertainment:
            "gamecontroller.fill"
        case .personal:
            "target"
        }
    }
}

struct MistiaIconGroup: Identifiable, Hashable {
    let id: MistiaIconGroupID
    let filterSymbolName: String
    let title: String
    let symbols: [String]
}

enum MistiaIconCatalog {
    static let groups: [MistiaIconGroup] = MistiaIconGroupID.allCases.map { id in
        MistiaIconGroup(
            id: id,
            filterSymbolName: id.filterSymbolName,
            title: id.title,
            symbols: deduplicated(groupedSymbols[id] ?? [])
        )
    }

    static let allSymbols: [String] = deduplicated(groups.flatMap(\.symbols))

    static func initialGroup(for symbolName: String) -> MistiaIconGroupID {
        groups.first(where: { $0.symbols.contains(symbolName) })?.id ?? .finance
    }

    static func group(for id: MistiaIconGroupID) -> MistiaIconGroup {
        groups.first(where: { $0.id == id }) ?? groups[0]
    }

    private static let groupedSymbols: [MistiaIconGroupID: [String]] = [
        .finance: [
            "wallet.pass.fill", "wallet.pass", "banknote.fill", "banknote", "creditcard.fill",
            "creditcard", "creditcard.and.123", "creditcard.circle.fill", "building.columns.fill", "building.columns",
            "building.2.fill", "chart.bar.fill", "chart.bar.xaxis", "chart.pie.fill", "chart.line.uptrend.xyaxis",
            "chart.xyaxis.line", "dollarsign.circle.fill", "yensign.circle.fill", "bitcoinsign.circle.fill", "percent",
            "chart.bar.doc.horizontal.fill", "arrow.left.arrow.right.circle.fill", "plusminus.circle.fill", "receipt.fill", "doc.text.fill",
            "tray.full.fill", "briefcase.fill", "calendar.badge.clock", "checkmark.seal.fill", "lock.shield.fill"
        ],
        .shopping: [
            "bag.fill", "bag", "cart.fill", "cart", "basket.fill",
            "basket", "gift.fill", "gift", "tag.fill", "tag",
            "shippingbox.fill", "shippingbox", "storefront.fill", "storefront", "suitcase.fill",
            "suitcase", "tshirt.fill", "shoeprints.fill", "hanger", "watch.analog",
            "camera.fill", "headphones", "display", "iphone", "laptopcomputer",
            "airpodspro", "chair.fill", "lamp.table.fill", "paintpalette.fill", "scissors"
        ],
        .food: [
            "fork.knife", "fork.knife.circle.fill", "takeoutbag.and.cup.and.straw.fill", "takeoutbag.and.cup.and.straw", "cup.and.saucer.fill",
            "cup.and.saucer", "wineglass.fill", "birthday.cake.fill", "carrot.fill", "fish.fill",
            "leaf.fill", "flame.fill", "mug.fill", "popcorn.fill", "waterbottle.fill",
            "basket.fill", "cart.fill", "bag.fill", "storefront.fill", "party.popper.fill",
            "sparkles", "heart.fill", "sun.max.fill", "moon.stars.fill", "gift.fill",
            "star.fill", "tray.fill", "shippingbox.fill", "fork.knife.circle", "carrot"
        ],
        .home: [
            "house.fill", "house", "bed.double.fill", "bed.double", "sofa.fill",
            "chair.fill", "washer.fill", "dishwasher.fill", "lamp.floor.fill", "lamp.desk.fill",
            "fan.fill", "water.waves", "shower.fill", "toilet.fill", "lightbulb.fill",
            "wifi", "tv.fill", "door.left.hand.open", "window.casement.closed", "lock.fill",
            "key.fill", "paintbrush.fill", "wrench.and.screwdriver.fill", "archivebox.fill", "shippingbox.fill",
            "stove.fill", "refrigerator.fill", "curtains.closed", "fireplace.fill", "sensor.tag.radiowaves.forward.fill"
        ],
        .utilities: [
            "bolt.fill", "bolt.circle.fill", "lightbulb.fill", "wifi", "antenna.radiowaves.left.and.right",
            "tv.fill", "phone.fill", "printer.fill", "drop.fill", "flame.fill",
            "battery.100percent", "powerplug.fill", "cable.connector", "network", "wifi.router",
            "dot.radiowaves.left.and.right", "cellularbars", "doc.text.fill", "calendar.badge.clock", "bell.fill",
            "exclamationmark.triangle.fill", "checkmark.circle.fill", "timer", "clock.fill", "gauge.with.dots.needle.50percent",
            "fan.fill", "drop.circle.fill", "shower.fill", "creditcard.and.123", "building.columns.fill"
        ],
        .transport: [
            "car.fill", "car", "car.side.fill", "tram.fill", "bus.fill",
            "bicycle", "scooter", "fuelpump.fill", "mappin.and.ellipse", "location.fill",
            "parkingsign.circle.fill", "bolt.car.fill", "steeringwheel", "figure.walk", "figure.run",
            "figure.outdoor.cycle", "train.side.front.car", "ferry.fill", "airplane.departure", "airplane.arrival",
            "road.lanes", "signpost.right.fill", "ev.charger.fill", "shippingbox.fill", "timer",
            "map.fill", "suitcase.fill", "wave.3.right.circle.fill", "location.circle.fill", "tram.circle.fill"
        ],
        .travel: [
            "airplane", "airplane.circle.fill", "airplane.departure", "airplane.arrival", "tram.fill",
            "train.side.front.car", "ferry.fill", "car.fill", "suitcase.fill", "globe.asia.australia.fill",
            "map.fill", "mappin.circle.fill", "camera.fill", "bed.double.fill", "tent.fill",
            "sun.max.fill", "moon.stars.fill", "mountain.2.fill", "binoculars.fill", "sparkles",
            "photo.fill", "building.columns.fill", "building.2.fill", "location.fill", "signpost.right.fill",
            "figure.walk", "sailboat.fill", "leaf.fill", "paperplane.fill", "tram.circle.fill"
        ],
        .health: [
            "cross.case.fill", "heart.fill", "figure.walk", "figure.run", "pills.fill",
            "bandage.fill", "stethoscope", "lungs.fill", "brain.head.profile", "cross.fill",
            "drop.fill", "waveform.path.ecg", "ear.fill", "eye.fill", "hare.fill",
            "tortoise.fill", "bed.double.fill", "sun.max.fill", "leaf.fill", "figure.mind.and.body",
            "waterbottle.fill", "bolt.heart.fill", "hands.sparkles.fill", "cross.vial.fill", "allergens.fill",
            "checkmark.seal.fill", "shield.checkered", "flame.fill", "sparkles", "staroflife.fill"
        ],
        .work: [
            "briefcase.fill", "laptopcomputer", "desktopcomputer", "display", "keyboard.fill",
            "printer.fill", "doc.text.fill", "doc.richtext.fill", "folder.fill", "tray.full.fill",
            "graduationcap.fill", "book.fill", "books.vertical.fill", "pencil.and.outline", "paperclip",
            "calendar", "clock.fill", "building.2.fill", "person.2.fill", "person.crop.circle.badge.checkmark",
            "chart.bar.fill", "chart.line.uptrend.xyaxis", "checklist", "link", "square.and.pencil",
            "doc.on.doc.fill", "backpack.fill", "ruler.fill", "bookmark.fill", "highlighter"
        ],
        .entertainment: [
            "gamecontroller.fill", "film.fill", "music.note", "music.mic", "play.tv.fill",
            "tv.fill", "popcorn.fill", "ticket.fill", "theatermasks.fill", "paintpalette.fill",
            "camera.fill", "photo.fill", "headphones", "radio.fill", "mic.fill",
            "book.fill", "dice.fill", "sportscourt.fill", "figure.dance", "party.popper.fill",
            "gift.fill", "star.fill", "sparkles", "play.circle.fill", "pause.circle.fill",
            "guitars.fill", "pianokeys.inverse", "soccerball.inverse", "baseball.fill", "basketball.fill"
        ],
        .personal: [
            "target", "star.fill", "flag.fill", "sparkles", "heart.fill",
            "person.fill", "person.2.fill", "figure.walk", "figure.run", "flame.fill",
            "trophy.fill", "medal.fill", "mountain.2.fill", "moon.stars.fill", "sun.max.fill",
            "leaf.fill", "checkmark.seal.fill", "bell.badge.fill", "bookmark.fill", "book.fill",
            "camera.fill", "paintbrush.fill", "pencil.and.outline", "brain.head.profile", "hands.sparkles.fill",
            "figure.mind.and.body", "smiley.fill", "cloud.sun.fill", "graduationcap.fill", "party.popper.fill"
        ]
    ]

    private static func deduplicated(_ symbols: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for symbol in symbols where seen.insert(symbol).inserted {
            result.append(symbol)
        }

        return result
    }
}

private struct MistiaIconColorPreset: Identifiable, Hashable {
    enum Kind: Hashable {
        case preset
        case current
    }

    let hex: String
    let kind: Kind

    var id: String { "\(kind)-\(hex)" }

    var color: Color {
        Color(hex: hex)
    }

    var accessibilityLabel: String {
        switch kind {
        case .preset:
            return L10n.core.ui.mistiaiconpicker.colorValue(String(describing: hex))
        case .current:
            return L10n.core.ui.mistiaiconpicker.currentColorValue(String(describing: hex))
        }
    }

    static let presetPalette: [MistiaIconColorPreset] = MistiaIconColorPalette.presetHexes.map {
        MistiaIconColorPreset(hex: $0, kind: .preset)
    }

    static func choices(for initialHex: String) -> [MistiaIconColorPreset] {
        let normalized = MistiaIconColorPalette.normalizedHex(initialHex)
        guard MistiaIconColorPalette.shouldShowCurrentSwatch(forStored: initialHex) else {
            return presetPalette
        }

        return [MistiaIconColorPreset(hex: normalized, kind: .current)] + presetPalette
    }
}

struct MistiaIconPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let onSave: (String, String) -> Void

    @State private var selectedSymbolName: String
    @State private var selectedColorHex: String
    @State private var selectedGroupID: MistiaIconGroupID

    private let colorChoices: [MistiaIconColorPreset]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 5)
    private let colorColumns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 5)
    private let accent = Color(red: 0.43, green: 0.23, blue: 0.76)

    init(
        title: String,
        selectedSymbolName: String,
        selectedColorHex: String,
        onSave: @escaping (String, String) -> Void
    ) {
        self.title = title
        self.onSave = onSave
        let normalizedSelectedColorHex = MistiaIconColorPalette.pickerSelectionHex(forStored: selectedColorHex)
        _selectedSymbolName = State(initialValue: selectedSymbolName)
        _selectedColorHex = State(initialValue: normalizedSelectedColorHex)
        _selectedGroupID = State(initialValue: MistiaIconCatalog.initialGroup(for: selectedSymbolName))
        colorChoices = MistiaIconColorPreset.choices(for: normalizedSelectedColorHex)
    }

    private var selectedGroup: MistiaIconGroup {
        MistiaIconCatalog.group(for: selectedGroupID)
    }

    private var selectedColor: Color {
        Color(hex: selectedColorHex)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(spacing: 12) {
                        MistiaIconPickerPreview(
                            symbolName: selectedSymbolName,
                            color: selectedColor,
                            size: 58
                        )

                        Text(L10n.core.ui.mistiaiconpicker.iconPreview)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
                    .padding(.horizontal, 20)

                    VStack(alignment: .leading, spacing: 10) {
                        LazyVGrid(columns: colorColumns, spacing: 12) {
                            ForEach(colorChoices) { choice in
                                colorButton(for: choice)
                            }
                        }
                    }
                    .padding(.horizontal, 20)

                    VStack(alignment: .leading, spacing: 14) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(MistiaIconCatalog.groups) { group in
                                    filterButton(for: group)
                                }
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                        }
                        .scrollClipDisabled()

                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(selectedGroup.symbols, id: \.self) { symbol in
                                let isSelected = selectedSymbolName == symbol
                                Button {
                                    selectedSymbolName = symbol
                                } label: {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(selectedColor.opacity(isSelected ? 0.22 : 0.08))

                                        Image(systemName: symbol)
                                            .font(.system(size: 18, weight: .bold))
                                            .foregroundStyle(selectedColor)
                                    }
                                    .frame(height: 54)
                                    .scaleEffect(isSelected ? 1.08 : 1)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .strokeBorder(
                                                isSelected
                                                    ? selectedColor.opacity(0.62)
                                                    : Color.secondary.opacity(0.08),
                                                lineWidth: 1
                                            )
                                    }
                                    .shadow(
                                        color: isSelected ? selectedColor.opacity(0.18) : .clear,
                                        radius: isSelected ? 10 : 0,
                                        y: isSelected ? 4 : 0
                                    )
                                    .animation(.snappy(duration: 0.18), value: isSelected)
                                }
                                .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 20))
                                .accessibilityLabel(symbol)
                                .zIndex(isSelected ? 10 : 0)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 4)
                    }
                }
                .padding(.vertical, 20)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onSave(selectedSymbolName, selectedColorHex)
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color(red: 0.88, green: 0.78, blue: 1.0))
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.circle)
                    .tint(accent)
                }
            }
        }
    }

    @ViewBuilder
    private func colorButton(for choice: MistiaIconColorPreset) -> some View {
        let isSelected = choice.hex == selectedColorHex

        Button {
            withAnimation(.snappy(duration: 0.18)) {
                selectedColorHex = choice.hex
            }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(choice.color)
                        .frame(width: 38, height: 38)

                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .background {
                    Circle()
                        .fill(choice.color.opacity(isSelected ? 0.18 : 0.08))
                        .frame(width: 48, height: 48)
                }
                .overlay {
                    Circle()
                        .strokeBorder(
                            isSelected ? choice.color.opacity(0.72) : Color.secondary.opacity(0.12),
                            style: StrokeStyle(
                                lineWidth: isSelected ? 2.5 : 1,
                                dash: choice.kind == .current ? [3, 3] : []
                            )
                        )
                        .frame(width: 48, height: 48)
                }
                .shadow(
                    color: isSelected ? choice.color.opacity(0.24) : .clear,
                    radius: isSelected ? 8 : 0,
                    y: isSelected ? 4 : 0
                )

                Text(choice.kind == .current
                    ? L10n.core.ui.mistiaiconpicker.current
                    : " ")
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 20))
        .accessibilityLabel(choice.accessibilityLabel)
    }

    @ViewBuilder
    private func filterButton(for group: MistiaIconGroup) -> some View {
        let button = Button {
            withAnimation(.snappy) {
                selectedGroupID = group.id
            }
        } label: {
            Image(systemName: group.filterSymbolName)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(selectedGroupID == group.id ? .white : .primary)
                .frame(width: 42, height: 34)
        }
        .buttonBorderShape(.capsule)
        .tint(accent)
        .accessibilityLabel(group.title)

        if selectedGroupID == group.id {
            button.buttonStyle(.glassProminent)
        } else {
            button.buttonStyle(.glass)
        }
    }
}

private struct MistiaIconPickerPreview: View {
    let symbolName: String
    let color: Color
    var size: CGFloat = 42

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                .fill(color.opacity(0.16))

            Image(systemName: symbolName)
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundStyle(color)
        }
        .frame(width: size, height: size)
    }
}
