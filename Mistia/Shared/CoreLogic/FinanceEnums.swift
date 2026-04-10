import Foundation

nonisolated enum MistiaFinanceIconGroup: String, CaseIterable, Identifiable, Codable {
    case wallet
    case food
    case home
    case family
    case mobility
    case personal
    case health
    case leisure
    case work
    case finance
    case income
    case planning
    case generic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wallet:
            mistiaLocalized(vi: "Ví", en: "Wallets", ja: "ウォレット")
        case .food:
            mistiaLocalized(vi: "Ăn uống", en: "Food", ja: "食事")
        case .home:
            mistiaLocalized(vi: "Nhà ở", en: "Home", ja: "住まい")
        case .family:
            mistiaLocalized(vi: "Gia đình", en: "Family", ja: "家族")
        case .mobility:
            mistiaLocalized(vi: "Đi lại", en: "Mobility", ja: "移動")
        case .personal:
            mistiaLocalized(vi: "Cá nhân", en: "Personal", ja: "個人")
        case .health:
            mistiaLocalized(vi: "Sức khỏe", en: "Health", ja: "健康")
        case .leisure:
            mistiaLocalized(vi: "Giải trí", en: "Leisure", ja: "娯楽")
        case .work:
            mistiaLocalized(vi: "Công việc", en: "Work", ja: "仕事")
        case .finance:
            mistiaLocalized(vi: "Tài chính", en: "Finance", ja: "金融")
        case .income:
            mistiaLocalized(vi: "Thu nhập", en: "Income", ja: "収入")
        case .planning:
            mistiaLocalized(vi: "Kế hoạch", en: "Planning", ja: "計画")
        case .generic:
            mistiaLocalized(vi: "Khác", en: "Other", ja: "その他")
        }
    }
}

nonisolated enum LedgerWalletKind: String, CaseIterable, Identifiable, Codable {
    case cash
    case payPay
    case bank
    case creditCard
    case eWallet
    case prepaid
    case investment
    case crypto
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cash:
            mistiaLocalized(vi: "Tiền mặt", en: "Cash", ja: "現金")
        case .payPay:
            "PayPay"
        case .bank:
            mistiaLocalized(vi: "Ngân hàng", en: "Bank", ja: "銀行")
        case .creditCard:
            mistiaLocalized(vi: "Credit card", en: "Credit card", ja: "クレジットカード")
        case .eWallet:
            mistiaLocalized(vi: "Ví điện tử / Barcode", en: "E-Wallet / Barcode", ja: "電子マネー / バーコード決済")
        case .prepaid:
            mistiaLocalized(vi: "Thẻ trả trước / IC", en: "Prepaid / IC Card", ja: "プリペイド / ICカード")
        case .investment:
            mistiaLocalized(vi: "Đầu tư / Chứng khoán", en: "Investment / Stocks", ja: "投資 / 証券")
        case .crypto:
            mistiaLocalized(vi: "Tiền ảo / Crypto", en: "Crypto / Digital Assets", ja: "仮想通貨 / クリプト")
        case .other:
            mistiaLocalized(vi: "Loại ví khác", en: "Other wallet", ja: "その他のウォレット")
        }
    }

    var defaultIconSymbolName: String {
        switch self {
        case .cash:
            "mistia.wallet.cash"
        case .payPay:
            "mistia.wallet.paypay"
        case .bank:
            "mistia.wallet.bank"
        case .creditCard:
            "mistia.wallet.credit_card"
        case .eWallet:
            "mistia.wallet.e_wallet"
        case .prepaid:
            "mistia.wallet.prepaid"
        case .investment:
            "mistia.wallet.investment"
        case .crypto:
            "mistia.wallet.crypto"
        case .other:
            "mistia.wallet.other"
        }
    }

    var defaultColorHex: String {
        switch self {
        case .cash:
            "#2DAA9E"
        case .payPay:
            "#F26A5A"
        case .bank:
            "#5B7BFF"
        case .creditCard:
            "#7C85A3"
        case .eWallet:
            "#F26A5A"
        case .prepaid:
            "#FFB347"
        case .investment:
            "#9A67FF"
        case .crypto:
            "#F59B3F"
        case .other:
            "#8A8A8E"
        }
    }

    var legacyDefaultIconSymbolNames: [String] {
        switch self {
        case .cash:
            ["banknote.fill"]
        case .payPay:
            ["wallet.pass.fill"]
        case .bank:
            ["building.columns.fill"]
        case .creditCard:
            ["creditcard.fill"]
        case .eWallet:
            ["qrcode", "barcode.viewfinder"]
        case .prepaid:
            ["creditcard.fill", "creditcard.and.123"]
        case .investment:
            ["chart.line.uptrend.xyaxis", "chart.pie.fill"]
        case .crypto:
            ["bitcoinsign.circle.fill", "bitcoinsign.square.fill"]
        case .other:
            ["wallet.pass.fill", "tray.full.fill"]
        }
    }

    var legacyDefaultColorHexes: [String] {
        switch self {
        case .creditCard:
            ["#8A8A8E", "#7C85A3"]
        default:
            []
        }
    }

    var fallbackSystemName: String {
        switch self {
        case .cash:
            "banknote.fill"
        case .payPay:
            "qrcode"
        case .bank:
            "building.columns.fill"
        case .creditCard:
            "creditcard.fill"
        case .eWallet:
            "qrcode"
        case .prepaid:
            "creditcard.fill"
        case .investment:
            "chart.line.uptrend.xyaxis"
        case .crypto:
            "bitcoinsign.circle.fill"
        case .other:
            "wallet.pass.fill"
        }
    }

    func matchesDefaultIconAppearance(symbolName: String, colorHex: String) -> Bool {
        if symbolName == defaultIconSymbolName {
            return true
        }

        guard legacyDefaultIconSymbolNames.contains(symbolName) else { return false }
        let normalizedColorHex = MistiaIconColorPalette.normalizedHex(colorHex)
        return normalizedColorHex == defaultColorHex || legacyDefaultColorHexes.contains(normalizedColorHex)
    }

    func migratedLegacyDefaultColorHex(for colorHex: String, symbolName: String) -> String? {
        guard legacyDefaultIconSymbolNames.contains(symbolName) else { return nil }
        let normalizedColorHex = MistiaIconColorPalette.normalizedHex(colorHex)
        guard normalizedColorHex == defaultColorHex || legacyDefaultColorHexes.contains(normalizedColorHex) else {
            return nil
        }
        return MistiaIconColorPalette.presetHex(forDefault: defaultColorHex)
    }

    var balanceFieldTitle: String {
        switch self {
        case .creditCard:
            mistiaLocalized(vi: "Dư nợ hiện tại", en: "Current debt", ja: "現在の利用残高")
        default:
            mistiaLocalized(vi: "Số dư ban đầu", en: "Opening balance", ja: "初期残高")
        }
    }
}

nonisolated enum TransactionCategoryKind: String, CaseIterable, Identifiable, Codable {
    case expense
    case income

    var id: String { rawValue }

    var title: String {
        switch self {
        case .expense:
            mistiaLocalized(vi: "Chi tiêu", en: "Expense", ja: "支出")
        case .income:
            mistiaLocalized(vi: "Thu nhập", en: "Income", ja: "収入")
        }
    }

    var defaultIconSymbolName: String {
        switch self {
        case .expense:
            "mistia.flow.expense"
        case .income:
            "mistia.flow.income"
        }
    }

    var defaultColorHex: String {
        switch self {
        case .expense:
            "#FF7A59"
        case .income:
            "#2DAA9E"
        }
    }

    var legacyDefaultIconSymbolNames: [String] {
        switch self {
        case .expense:
            ["fork.knife"]
        case .income:
            ["briefcase.fill"]
        }
    }

    var legacyDefaultColorHexes: [String] {
        switch self {
        case .expense:
            ["#FF9F1C", "#F59B3F"]
        case .income:
            []
        }
    }

    func matchesDefaultIconAppearance(symbolName: String, colorHex: String) -> Bool {
        if symbolName == defaultIconSymbolName {
            return true
        }

        guard legacyDefaultIconSymbolNames.contains(symbolName) else { return false }
        let normalizedColorHex = MistiaIconColorPalette.normalizedHex(colorHex)
        return normalizedColorHex == defaultColorHex || legacyDefaultColorHexes.contains(normalizedColorHex)
    }

    func migratedLegacyDefaultColorHex(for colorHex: String, symbolName: String) -> String? {
        guard legacyDefaultIconSymbolNames.contains(symbolName) else { return nil }
        let normalizedColorHex = MistiaIconColorPalette.normalizedHex(colorHex)
        guard normalizedColorHex == defaultColorHex || legacyDefaultColorHexes.contains(normalizedColorHex) else {
            return nil
        }
        return MistiaIconColorPalette.presetHex(forDefault: defaultColorHex)
    }
}

nonisolated enum TransactionCategoryHierarchyRole: String, CaseIterable, Identifiable, Codable {
    case parent
    case child

    var id: String { rawValue }

    var title: String {
        switch self {
        case .parent:
            mistiaLocalized(vi: "Danh mục cha", en: "Parent category", ja: "親カテゴリ")
        case .child:
            mistiaLocalized(vi: "Danh mục con", en: "Child category", ja: "子カテゴリ")
        }
    }
}

nonisolated enum MistiaSystemCategoryParentKey: String, CaseIterable, Codable, Identifiable {
    case livingExpense = "parent_expense_living"
    case mobilityTravel = "parent_expense_mobility_travel"
    case personalLifestyle = "parent_expense_personal_lifestyle"
    case expenseFood = "parent_expense_food"
    case expenseCostOfGoods = "parent_expense_cost_of_goods"
    case expenseHomeBills = "parent_expense_home_bills"
    case expenseFamilyChildren = "parent_expense_family_children"
    case expenseTransportVehicle = "parent_expense_transport_vehicle"
    case expensePersonalShopping = "parent_expense_personal_shopping"
    case expenseHealth = "parent_expense_health"
    case expenseFamilyRelations = "parent_expense_family_relations"
    case expenseEntertainmentSocial = "parent_expense_entertainment_social"
    case expenseWorkStudy = "parent_expense_work_study"
    case expenseFinancialObligations = "parent_expense_financial_obligations"
    case expensePetCare = "parent_expense_pet_care"
    case expenseOther = "parent_expense_uncategorized"
    case incomeSalaryWork = "parent_income_work"
    case incomeBusiness = "parent_income_sales_other"
    case incomeInvestmentFinance = "parent_income_investment_return"
    case incomeRefundAdjustment = "parent_income_refund_adjustment"
    case incomeSupportGift = "parent_income_support_gift"
    case incomeLiquidation = "parent_income_liquidation"
    case incomeOther = "parent_income_uncategorized"

    private struct Meta {
        let kind: TransactionCategoryKind
        let title: String
        let iconToken: String
        let fallbackSystemName: String
        let iconColorHex: String
        let group: MistiaFinanceIconGroup
        let activeDefault: Bool
        let aliases: [String]
    }

    private static let metadata: [Self: Meta] = [
        .livingExpense: .init(kind: .expense, title: "Sinh hoạt", iconToken: "mistia.category.parent.legacy.living", fallbackSystemName: "house.fill", iconColorHex: "#FF9F1C", group: .home, activeDefault: false, aliases: []),
        .mobilityTravel: .init(kind: .expense, title: "Di chuyển & chuyến đi", iconToken: "mistia.category.parent.legacy.mobility_travel", fallbackSystemName: "airplane", iconColorHex: "#5B7BFF", group: .mobility, activeDefault: false, aliases: []),
        .personalLifestyle: .init(kind: .expense, title: "Cá nhân & phong cách sống", iconToken: "mistia.category.parent.legacy.personal_lifestyle", fallbackSystemName: "sparkles", iconColorHex: "#F26A5A", group: .personal, activeDefault: false, aliases: []),
        .expenseFood: .init(kind: .expense, title: "Sinh hoạt", iconToken: "mistia.category.parent.expense.food", fallbackSystemName: "cart.fill", iconColorHex: "#FF8A4C", group: .food, activeDefault: true, aliases: []),
        .expenseCostOfGoods: .init(kind: .expense, title: "Tiền hàng", iconToken: "mistia.category.parent.expense.cost_of_goods", fallbackSystemName: "shippingbox.fill", iconColorHex: "#4C8DFF", group: .work, activeDefault: true, aliases: []),
        .expenseHomeBills: .init(kind: .expense, title: "Nhà ở & hóa đơn", iconToken: "mistia.category.parent.expense.home_bills", fallbackSystemName: "house.fill", iconColorHex: "#5B7BFF", group: .home, activeDefault: true, aliases: []),
        .expenseFamilyChildren: .init(kind: .expense, title: "Con cái", iconToken: "mistia.category.parent.expense.family_children", fallbackSystemName: "person.2.fill", iconColorHex: "#FF6D8A", group: .family, activeDefault: true, aliases: ["Gia đình & con cái"]),
        .expenseTransportVehicle: .init(kind: .expense, title: "Đi lại & xe cộ", iconToken: "mistia.category.parent.expense.transport_vehicle", fallbackSystemName: "car.fill", iconColorHex: "#2DAA9E", group: .mobility, activeDefault: true, aliases: []),
        .expensePersonalShopping: .init(kind: .expense, title: "Mua sắm", iconToken: "mistia.category.parent.expense.personal_shopping", fallbackSystemName: "bag.fill", iconColorHex: "#A76BFF", group: .personal, activeDefault: true, aliases: ["Mua sắm cá nhân"]),
        .expenseHealth: .init(kind: .expense, title: "Sức khỏe", iconToken: "mistia.category.parent.expense.health", fallbackSystemName: "cross.case.fill", iconColorHex: "#F45C7E", group: .health, activeDefault: true, aliases: []),
        .expenseFamilyRelations: .init(kind: .expense, title: "Gia đình & quan hệ", iconToken: "mistia.category.parent.expense.family_relations", fallbackSystemName: "gift.fill", iconColorHex: "#FF8A4C", group: .family, activeDefault: true, aliases: []),
        .expenseEntertainmentSocial: .init(kind: .expense, title: "Giải trí", iconToken: "mistia.category.parent.expense.entertainment_social", fallbackSystemName: "party.popper.fill", iconColorHex: "#F59B3F", group: .leisure, activeDefault: true, aliases: ["Giải trí & xã hội"]),
        .expenseWorkStudy: .init(kind: .expense, title: "Học tập & công việc", iconToken: "mistia.category.parent.expense.work_study", fallbackSystemName: "briefcase.fill", iconColorHex: "#4C8DFF", group: .work, activeDefault: true, aliases: ["Công việc & học tập"]),
        .expenseFinancialObligations: .init(kind: .expense, title: "Tài chính & nghĩa vụ", iconToken: "mistia.category.parent.expense.financial_obligations", fallbackSystemName: "creditcard.and.123", iconColorHex: "#7C85A3", group: .finance, activeDefault: true, aliases: ["Nghĩa vụ tài chính"]),
        .expensePetCare: .init(kind: .expense, title: "Thú cưng", iconToken: "mistia.category.parent.expense.pet_care", fallbackSystemName: "pawprint.fill", iconColorHex: "#57B7FF", group: .family, activeDefault: true, aliases: []),
        .expenseOther: .init(kind: .expense, title: "Chi khác", iconToken: "mistia.category.parent.expense.other", fallbackSystemName: "tray.full.fill", iconColorHex: "#8A8A8E", group: .generic, activeDefault: true, aliases: ["Chưa phân loại chi"]),
        .incomeSalaryWork: .init(kind: .income, title: "Lương & công việc", iconToken: "mistia.category.parent.income.salary_work", fallbackSystemName: "briefcase.fill", iconColorHex: "#2DAA9E", group: .income, activeDefault: true, aliases: ["Thu nhập công việc"]),
        .incomeBusiness: .init(kind: .income, title: "Kinh doanh", iconToken: "mistia.category.parent.income.business", fallbackSystemName: "storefront.fill", iconColorHex: "#F26A5A", group: .income, activeDefault: true, aliases: ["Bán hàng & khác"]),
        .incomeInvestmentFinance: .init(kind: .income, title: "Đầu tư & tài chính", iconToken: "mistia.category.parent.income.investment_finance", fallbackSystemName: "chart.line.uptrend.xyaxis", iconColorHex: "#5B7BFF", group: .finance, activeDefault: true, aliases: ["Đầu tư & hoàn lại"]),
        .incomeRefundAdjustment: .init(kind: .income, title: "Hoàn lại & bồi hoàn", iconToken: "mistia.category.parent.income.refund_adjustment", fallbackSystemName: "arrow.counterclockwise.circle.fill", iconColorHex: "#57B7FF", group: .income, activeDefault: true, aliases: ["Hoàn lại & điều chỉnh"]),
        .incomeSupportGift: .init(kind: .income, title: "Hỗ trợ & trợ cấp", iconToken: "mistia.category.parent.income.support_gift", fallbackSystemName: "heart.fill", iconColorHex: "#FF6D8A", group: .income, activeDefault: true, aliases: ["Hỗ trợ & quà tặng"]),
        .incomeLiquidation: .init(kind: .income, title: "Thanh lý", iconToken: "mistia.category.parent.income.liquidation", fallbackSystemName: "arrow.square.fill", iconColorHex: "#F59B3F", group: .income, activeDefault: true, aliases: []),
        .incomeOther: .init(kind: .income, title: "Thu khác", iconToken: "mistia.category.parent.income.other", fallbackSystemName: "plusminus.circle.fill", iconColorHex: "#8A8A8E", group: .generic, activeDefault: true, aliases: ["Chưa phân loại thu"])
    ]

    static let activeDefaults: [Self] = [
        .expenseFood,
        .expenseCostOfGoods,
        .expenseHomeBills,
        .expenseFamilyChildren,
        .expenseTransportVehicle,
        .expensePersonalShopping,
        .expenseHealth,
        .expenseFamilyRelations,
        .expenseEntertainmentSocial,
        .expenseWorkStudy,
        .expenseFinancialObligations,
        .expensePetCare,
        .expenseOther,
        .incomeSalaryWork,
        .incomeBusiness,
        .incomeInvestmentFinance,
        .incomeRefundAdjustment,
        .incomeSupportGift,
        .incomeLiquidation,
        .incomeOther
    ]

    private var meta: Meta {
        Self.metadata[self] ?? .init(kind: .expense, title: rawValue, iconToken: rawValue, fallbackSystemName: "questionmark.circle.fill", iconColorHex: "#8A8A8E", group: .generic, activeDefault: false, aliases: [])
    }

    var id: String { rawValue }
    var kind: TransactionCategoryKind { meta.kind }
    var title: String { localizedTitle(for: .current) }
    var legacyVietnameseName: String { meta.title }
    var fallbackSystemName: String { meta.fallbackSystemName }
    var iconSymbolName: String { meta.iconToken }
    var iconColorHex: String { meta.iconColorHex }
    var pickerGroup: MistiaFinanceIconGroup { meta.group }
    var isActiveDefault: Bool { meta.activeDefault }
    var showsOnlyWhenHasChildren: Bool {
        switch self {
        case .expenseOther, .incomeOther:
            true
        default:
            false
        }
    }

    func knownDefaultNames() -> [String] {
        Array(Set([meta.title] + meta.aliases))
    }

    func localizedTitle(for language: MistiaAppLanguage) -> String {
        mistiaLocalized(vi: meta.title, en: meta.title, ja: meta.title, language: language)
    }
}

nonisolated enum MistiaSystemCategoryKey: String, CaseIterable, Codable, Identifiable {
    case food
    case entertainment
    case shopping
    case transportation
    case housing
    case billing
    case health
    case education
    case investment
    case grocery
    case dailySupplies = "daily_supplies"
    case dineOut = "dine_out"
    case businessMeals = "business_meals"
    case cafeTea = "cafe_tea"
    case foodDelivery = "food_delivery"
    case snacks
    case smallAppliances = "small_appliances"
    case importGoods = "import_goods"
    case goodsSourcing = "goods_sourcing"
    case shippingFee = "shipping_fee"
    case packaging
    case platformFee = "platform_fee"
    case marketingAds = "marketing_ads"
    case otherSalesCost = "other_sales_cost"
    case rent
    case electricity
    case water
    case internet
    case phone
    case gas
    case mortgageInstallment = "mortgage_installment"
    case condoFee = "condo_fee"
    case homeRepair = "home_repair"
    case furnitureAppliance = "furniture_appliance"
    case diapersMilk = "diapers_milk"
    case babyFood = "baby_food"
    case childSupplies = "child_supplies"
    case childToys = "child_toys"
    case childTuition = "child_tuition"
    case schoolBooksSupplies = "school_books_supplies"
    case childExtracurricular = "child_extracurricular"
    case childcare
    case childMedical = "child_medical"
    case childMedicine = "child_medicine"
    case babyGear = "baby_gear"
    case familyOther = "family_other"
    case fuel
    case parking
    case grabTaxi = "grab_taxi"
    case publicTransport = "public_transport"
    case vehicleMaintenance = "vehicle_maintenance"
    case vehicleRepair = "vehicle_repair"
    case carWash = "car_wash"
    case tolls
    case vehicleInsurance = "vehicle_insurance"
    case vehicleRegistration = "vehicle_registration"
    case clothes
    case footwear
    case cosmeticsSkincare = "cosmetics_skincare"
    case personalCare = "personal_care"
    case accessories
    case personalSupplies = "personal_supplies"
    case medicalCheckup = "medical_checkup"
    case medicine
    case labTests = "lab_tests"
    case dental
    case hospital
    case healthInsurance = "health_insurance"
    case fitnessGym = "fitness_gym"
    case supplements
    case moviesLeisure = "movies_leisure"
    case travel
    case gamesApps = "games_apps"
    case booksMusic = "books_music"
    case partiesGatherings = "parties_gatherings"
    case giftsCeremonies = "gifts_ceremonies"
    case relationshipGifts = "relationship_gifts"
    case parentsSupportExpense = "parents_support_expense"
    case familySupportExpense = "family_support_expense"
    case charity
    case subscriptions
    case hobbies
    case coffeeFriends = "coffee_friends"
    case workTools = "work_tools"
    case workSoftwareSubscriptions = "work_software_subscriptions"
    case clientEntertainment = "client_entertainment"
    case businessTravel = "business_travel"
    case courses
    case professionalBooks = "professional_books"
    case examsCertificates = "exams_certificates"
    case insurance
    case taxesFees = "taxes_fees"
    case bankingFees = "banking_fees"
    case loanInterest = "loan_interest"
    case loanRepayment = "loan_repayment"
    case finesFees = "fines_fees"
    case otherObligations = "other_obligations"
    case petFood = "pet_food"
    case petMedical = "pet_medical"
    case petSupplies = "pet_supplies"
    case petGrooming = "pet_grooming"
    case petOther = "pet_other"
    case otherExpense = "other_expense"
    case salary
    case sideSalary = "side_salary"
    case bonus
    case allowance
    case commission
    case freelance
    case overtime
    case sales
    case serviceRevenue = "service_revenue"
    case businessProfit = "business_profit"
    case onlineCollaboratorIncome = "online_collaborator_income"
    case otherBusinessIncome = "other_business_income"
    case bankInterest = "bank_interest"
    case dividends
    case investmentGain = "investment_gain"
    case loanInterestReceived = "loan_interest_received"
    case otherFinancialIncome = "other_financial_income"
    case refund
    case cashback
    case reimbursement
    case peopleRepayment = "people_repayment"
    case expenseRecovery = "expense_recovery"
    case insurancePayout = "insurance_payout"
    case gift
    case supportReceived = "support_received"
    case subsidy
    case childAllowance = "child_allowance"
    case maternityAllowance = "maternity_allowance"
    case familySupport = "family_support"
    case sellUsedItems = "sell_used_items"
    case liquidateHousehold = "liquidate_household"
    case otherLiquidationIncome = "other_liquidation_income"
    case otherIncome = "other_income"

    private struct Meta {
        let title: String
        let englishTitle: String?
        let japaneseTitle: String?
        let parentKey: MistiaSystemCategoryParentKey?
        let iconToken: String
        let fallbackSystemName: String
        let iconColorHex: String
        let group: MistiaFinanceIconGroup
        let activeDefault: Bool
        let aliases: [String]

        init(
            title: String,
            englishTitle: String? = nil,
            japaneseTitle: String? = nil,
            parentKey: MistiaSystemCategoryParentKey?,
            iconToken: String,
            fallbackSystemName: String,
            iconColorHex: String,
            group: MistiaFinanceIconGroup,
            activeDefault: Bool,
            aliases: [String]
        ) {
            self.title = title
            self.englishTitle = englishTitle
            self.japaneseTitle = japaneseTitle
            self.parentKey = parentKey
            self.iconToken = iconToken
            self.fallbackSystemName = fallbackSystemName
            self.iconColorHex = iconColorHex
            self.group = group
            self.activeDefault = activeDefault
            self.aliases = aliases
        }
    }

    private static let metadata: [Self: Meta] = [
        .food: .init(title: "Ăn uống", englishTitle: "Food & drinks", japaneseTitle: "食費", parentKey: .livingExpense, iconToken: "mistia.category.legacy.food", fallbackSystemName: "fork.knife", iconColorHex: "#FF9F1C", group: .food, activeDefault: false, aliases: []),
        .entertainment: .init(title: "Đi chơi", parentKey: .personalLifestyle, iconToken: "mistia.category.legacy.entertainment", fallbackSystemName: "party.popper.fill", iconColorHex: "#F26A5A", group: .leisure, activeDefault: false, aliases: []),
        .shopping: .init(title: "Mua sắm", parentKey: .personalLifestyle, iconToken: "mistia.category.legacy.shopping", fallbackSystemName: "bag.fill", iconColorHex: "#F26A5A", group: .personal, activeDefault: false, aliases: []),
        .transportation: .init(title: "Di chuyển", parentKey: .mobilityTravel, iconToken: "mistia.category.legacy.transportation", fallbackSystemName: "train.side.front.car", iconColorHex: "#2DAA9E", group: .mobility, activeDefault: false, aliases: []),
        .housing: .init(title: "Nhà ở", parentKey: .livingExpense, iconToken: "mistia.category.legacy.housing", fallbackSystemName: "house.fill", iconColorHex: "#8A8A8E", group: .home, activeDefault: false, aliases: []),
        .billing: .init(title: "Hóa đơn", parentKey: .livingExpense, iconToken: "mistia.category.legacy.billing", fallbackSystemName: "doc.text.fill", iconColorHex: "#FF9F1C", group: .home, activeDefault: false, aliases: []),
        .health: .init(title: "Sức khỏe", parentKey: .personalLifestyle, iconToken: "mistia.category.legacy.health", fallbackSystemName: "cross.case.fill", iconColorHex: "#F26A5A", group: .health, activeDefault: false, aliases: []),
        .education: .init(title: "Giáo dục", parentKey: .personalLifestyle, iconToken: "mistia.category.legacy.education", fallbackSystemName: "book.closed.fill", iconColorHex: "#9A67FF", group: .work, activeDefault: false, aliases: []),
        .investment: .init(title: "Đầu tư", parentKey: .incomeInvestmentFinance, iconToken: "mistia.category.legacy.investment", fallbackSystemName: "chart.line.uptrend.xyaxis", iconColorHex: "#57B7FF", group: .finance, activeDefault: false, aliases: []),
        .grocery: .init(title: "Đi chợ", parentKey: .expenseFood, iconToken: "mistia.category.expense.food.grocery", fallbackSystemName: "basket.fill", iconColorHex: "#FF8A4C", group: .food, activeDefault: true, aliases: ["Đi chợ / thực phẩm"]),
        .dailySupplies: .init(title: "Đồ tiêu dùng", parentKey: .expenseFood, iconToken: "mistia.category.expense.food.daily_supplies", fallbackSystemName: "bag.fill", iconColorHex: "#A76BFF", group: .food, activeDefault: true, aliases: []),
        .dineOut: .init(title: "Ăn ngoài", parentKey: .expenseFood, iconToken: "mistia.category.expense.food.dine_out", fallbackSystemName: "fork.knife.circle.fill", iconColorHex: "#FF8A4C", group: .food, activeDefault: true, aliases: []),
        .businessMeals: .init(title: "Ăn uống công việc", parentKey: .expenseFood, iconToken: "mistia.category.expense.food.business_meals", fallbackSystemName: "briefcase.fill", iconColorHex: "#2DAA9E", group: .food, activeDefault: true, aliases: []),
        .cafeTea: .init(title: "Cafe / trà sữa", parentKey: .expenseFood, iconToken: "mistia.category.expense.food.cafe_tea", fallbackSystemName: "cup.and.saucer.fill", iconColorHex: "#C46A6A", group: .food, activeDefault: true, aliases: []),
        .foodDelivery: .init(title: "Đặt đồ ăn", parentKey: .expenseFood, iconToken: "mistia.category.expense.food.delivery", fallbackSystemName: "takeoutbag.and.cup.and.straw.fill", iconColorHex: "#FF7A59", group: .food, activeDefault: true, aliases: []),
        .snacks: .init(title: "Ăn vặt / bánh kẹo", parentKey: .expenseFood, iconToken: "mistia.category.expense.food.snacks", fallbackSystemName: "birthday.cake.fill", iconColorHex: "#FFB347", group: .food, activeDefault: true, aliases: []),
        .smallAppliances: .init(title: "Đồ gia dụng nhỏ", parentKey: .expenseFood, iconToken: "mistia.category.expense.food.small_appliances", fallbackSystemName: "desktopcomputer", iconColorHex: "#7C85A3", group: .food, activeDefault: true, aliases: []),
        .importGoods: .init(title: "Nhập hàng", parentKey: .expenseCostOfGoods, iconToken: "mistia.category.expense.cost_of_goods.import_goods", fallbackSystemName: "box.truck.fill", iconColorHex: "#5B7BFF", group: .work, activeDefault: true, aliases: []),
        .goodsSourcing: .init(title: "Chi phí lấy hàng", parentKey: .expenseCostOfGoods, iconToken: "mistia.category.expense.cost_of_goods.goods_sourcing", fallbackSystemName: "cart.fill", iconColorHex: "#F59B3F", group: .work, activeDefault: true, aliases: []),
        .shippingFee: .init(title: "Phí vận chuyển hàng", parentKey: .expenseCostOfGoods, iconToken: "mistia.category.expense.cost_of_goods.shipping_fee", fallbackSystemName: "car.fill", iconColorHex: "#2DAA9E", group: .work, activeDefault: true, aliases: []),
        .packaging: .init(title: "Đóng gói / bao bì", parentKey: .expenseCostOfGoods, iconToken: "mistia.category.expense.cost_of_goods.packaging", fallbackSystemName: "shippingbox.fill", iconColorHex: "#FFB347", group: .work, activeDefault: true, aliases: []),
        .platformFee: .init(title: "Chi phí sàn", parentKey: .expenseCostOfGoods, iconToken: "mistia.category.expense.cost_of_goods.platform_fee", fallbackSystemName: "building.2.fill", iconColorHex: "#4C8DFF", group: .work, activeDefault: true, aliases: []),
        .marketingAds: .init(title: "Marketing / quảng cáo", parentKey: .expenseCostOfGoods, iconToken: "mistia.category.expense.cost_of_goods.marketing_ads", fallbackSystemName: "megaphone.fill", iconColorHex: "#FF6D8A", group: .work, activeDefault: true, aliases: []),
        .otherSalesCost: .init(title: "Chi phí bán hàng khác", parentKey: .expenseCostOfGoods, iconToken: "mistia.category.expense.cost_of_goods.other_sales_cost", fallbackSystemName: "creditcard.fill", iconColorHex: "#8A8A8E", group: .work, activeDefault: true, aliases: []),
        .rent: .init(title: "Tiền nhà", parentKey: .expenseHomeBills, iconToken: "mistia.category.expense.home_bills.rent", fallbackSystemName: "house.fill", iconColorHex: "#5B7BFF", group: .home, activeDefault: true, aliases: ["Tiền nhà / thuê nhà"]),
        .electricity: .init(title: "Điện", parentKey: .expenseHomeBills, iconToken: "mistia.category.expense.home_bills.electricity", fallbackSystemName: "bolt.fill", iconColorHex: "#FFB347", group: .home, activeDefault: true, aliases: []),
        .water: .init(title: "Nước", parentKey: .expenseHomeBills, iconToken: "mistia.category.expense.home_bills.water", fallbackSystemName: "drop.fill", iconColorHex: "#57B7FF", group: .home, activeDefault: true, aliases: []),
        .internet: .init(title: "Internet", parentKey: .expenseHomeBills, iconToken: "mistia.category.expense.home_bills.internet", fallbackSystemName: "wifi", iconColorHex: "#5B7BFF", group: .home, activeDefault: true, aliases: []),
        .phone: .init(title: "Điện thoại", parentKey: .expenseHomeBills, iconToken: "mistia.category.expense.home_bills.phone", fallbackSystemName: "phone.fill", iconColorHex: "#2DAA9E", group: .home, activeDefault: true, aliases: []),
        .gas: .init(title: "Gas", parentKey: .expenseHomeBills, iconToken: "mistia.category.expense.home_bills.gas", fallbackSystemName: "flame.fill", iconColorHex: "#F59B3F", group: .home, activeDefault: true, aliases: []),
        .mortgageInstallment: .init(title: "Trả góp nhà", parentKey: .expenseHomeBills, iconToken: "mistia.category.expense.home_bills.mortgage_installment", fallbackSystemName: "building.columns.fill", iconColorHex: "#7C85A3", group: .home, activeDefault: true, aliases: []),
        .condoFee: .init(title: "Phí chung cư / quản lý", parentKey: .expenseHomeBills, iconToken: "mistia.category.expense.home_bills.condo_fee", fallbackSystemName: "building.2.fill", iconColorHex: "#7C85A3", group: .home, activeDefault: true, aliases: ["Phí chung cư / dịch vụ"]),
        .homeRepair: .init(title: "Sửa chữa / bảo trì nhà", parentKey: .expenseHomeBills, iconToken: "mistia.category.expense.home_bills.home_repair", fallbackSystemName: "wrench.and.screwdriver.fill", iconColorHex: "#7C85A3", group: .home, activeDefault: true, aliases: []),
        .furnitureAppliance: .init(title: "Nội thất / đồ gia dụng", parentKey: .expenseHomeBills, iconToken: "mistia.category.expense.home_bills.furniture_appliance", fallbackSystemName: "chair.fill", iconColorHex: "#A76BFF", group: .home, activeDefault: true, aliases: []),
        .diapersMilk: .init(title: "Bỉm / tã", parentKey: .expenseFamilyChildren, iconToken: "mistia.category.expense.family_children.diapers_milk", fallbackSystemName: "drop.fill", iconColorHex: "#FF9AB5", group: .family, activeDefault: true, aliases: ["Bỉm / sữa"]),
        .babyFood: .init(title: "Sữa / đồ ăn dặm", parentKey: .expenseFamilyChildren, iconToken: "mistia.category.expense.family_children.baby_food", fallbackSystemName: "takeoutbag.and.cup.and.straw.fill", iconColorHex: "#FFB347", group: .family, activeDefault: true, aliases: []),
        .childSupplies: .init(title: "Quần áo / đồ dùng cho bé", parentKey: .expenseFamilyChildren, iconToken: "mistia.category.expense.family_children.child_supplies", fallbackSystemName: "shippingbox.fill", iconColorHex: "#FF6D8A", group: .family, activeDefault: true, aliases: ["Đồ dùng cho con"]),
        .childToys: .init(title: "Đồ chơi", parentKey: .expenseFamilyChildren, iconToken: "mistia.category.expense.family_children.child_toys", fallbackSystemName: "gamecontroller.fill", iconColorHex: "#A76BFF", group: .family, activeDefault: true, aliases: []),
        .childTuition: .init(title: "Học phí / giữ trẻ / mầm non", parentKey: .expenseFamilyChildren, iconToken: "mistia.category.expense.family_children.child_tuition", fallbackSystemName: "graduationcap.fill", iconColorHex: "#4C8DFF", group: .family, activeDefault: true, aliases: ["Học phí cho con"]),
        .schoolBooksSupplies: .init(title: "Sách / học cụ cho bé", parentKey: .expenseFamilyChildren, iconToken: "mistia.category.expense.family_children.school_books_supplies", fallbackSystemName: "book.closed.fill", iconColorHex: "#A76BFF", group: .family, activeDefault: true, aliases: ["Sách / dụng cụ học tập"]),
        .childExtracurricular: .init(title: "Hoạt động ngoại khóa", parentKey: .expenseFamilyChildren, iconToken: "mistia.category.expense.family_children.child_extracurricular", fallbackSystemName: "figure.run", iconColorHex: "#2DAA9E", group: .family, activeDefault: true, aliases: []),
        .childcare: .init(title: "Trông trẻ / babysitter", parentKey: .expenseFamilyChildren, iconToken: "mistia.category.expense.family_children.childcare", fallbackSystemName: "person.2.fill", iconColorHex: "#FF8A4C", group: .family, activeDefault: true, aliases: ["Giữ trẻ / trông trẻ"]),
        .childMedical: .init(title: "Khám bệnh cho bé", parentKey: .expenseFamilyChildren, iconToken: "mistia.category.expense.family_children.child_medical", fallbackSystemName: "stethoscope", iconColorHex: "#F45C7E", group: .family, activeDefault: true, aliases: ["Khám bệnh cho con"]),
        .childMedicine: .init(title: "Thuốc / vitamin cho bé", parentKey: .expenseFamilyChildren, iconToken: "mistia.category.expense.family_children.child_medicine", fallbackSystemName: "pills.fill", iconColorHex: "#57B7FF", group: .family, activeDefault: true, aliases: []),
        .babyGear: .init(title: "Xe đẩy / nôi / ghế ăn / đồ sơ sinh", parentKey: .expenseFamilyChildren, iconToken: "mistia.category.expense.family_children.baby_gear", fallbackSystemName: "bed.double.fill", iconColorHex: "#5B7BFF", group: .family, activeDefault: true, aliases: []),
        .familyOther: .init(title: "Chi khác cho con", parentKey: .expenseFamilyChildren, iconToken: "mistia.category.expense.family_children.family_other", fallbackSystemName: "heart.text.square.fill", iconColorHex: "#FF6D8A", group: .family, activeDefault: true, aliases: ["Chi gia đình khác"]),
        .fuel: .init(title: "Xăng xe", parentKey: .expenseTransportVehicle, iconToken: "mistia.category.expense.transport_vehicle.fuel", fallbackSystemName: "fuelpump.fill", iconColorHex: "#2DAA9E", group: .mobility, activeDefault: true, aliases: []),
        .parking: .init(title: "Gửi xe", parentKey: .expenseTransportVehicle, iconToken: "mistia.category.expense.transport_vehicle.parking", fallbackSystemName: "parkingsign.circle.fill", iconColorHex: "#4C8DFF", group: .mobility, activeDefault: true, aliases: []),
        .grabTaxi: .init(title: "Grab / taxi", parentKey: .expenseTransportVehicle, iconToken: "mistia.category.expense.transport_vehicle.grab_taxi", fallbackSystemName: "car.fill", iconColorHex: "#2DAA9E", group: .mobility, activeDefault: true, aliases: []),
        .publicTransport: .init(title: "Xe buýt / tàu / vé xe", parentKey: .expenseTransportVehicle, iconToken: "mistia.category.expense.transport_vehicle.public_transport", fallbackSystemName: "tram.fill", iconColorHex: "#5B7BFF", group: .mobility, activeDefault: true, aliases: []),
        .vehicleMaintenance: .init(title: "Bảo dưỡng xe", parentKey: .expenseTransportVehicle, iconToken: "mistia.category.expense.transport_vehicle.maintenance", fallbackSystemName: "wrench.and.screwdriver.fill", iconColorHex: "#7C85A3", group: .mobility, activeDefault: true, aliases: []),
        .vehicleRepair: .init(title: "Sửa xe", parentKey: .expenseTransportVehicle, iconToken: "mistia.category.expense.transport_vehicle.repair", fallbackSystemName: "gearshape.2.fill", iconColorHex: "#7C85A3", group: .mobility, activeDefault: true, aliases: []),
        .carWash: .init(title: "Rửa xe", parentKey: .expenseTransportVehicle, iconToken: "mistia.category.expense.transport_vehicle.car_wash", fallbackSystemName: "drop.circle.fill", iconColorHex: "#57B7FF", group: .mobility, activeDefault: true, aliases: []),
        .tolls: .init(title: "Phí cầu đường", parentKey: .expenseTransportVehicle, iconToken: "mistia.category.expense.transport_vehicle.tolls", fallbackSystemName: "road.lanes", iconColorHex: "#F59B3F", group: .mobility, activeDefault: true, aliases: []),
        .vehicleInsurance: .init(title: "Bảo hiểm xe", parentKey: .expenseTransportVehicle, iconToken: "mistia.category.expense.transport_vehicle.insurance", fallbackSystemName: "car.rear.waves.up.fill", iconColorHex: "#7C85A3", group: .mobility, activeDefault: true, aliases: []),
        .vehicleRegistration: .init(title: "Đăng kiểm / giấy tờ xe", parentKey: .expenseTransportVehicle, iconToken: "mistia.category.expense.transport_vehicle.registration", fallbackSystemName: "doc.text.fill", iconColorHex: "#5B7BFF", group: .mobility, activeDefault: true, aliases: []),
        .clothes: .init(title: "Quần áo", parentKey: .expensePersonalShopping, iconToken: "mistia.category.expense.personal_shopping.clothes", fallbackSystemName: "tshirt.fill", iconColorHex: "#A76BFF", group: .personal, activeDefault: true, aliases: []),
        .footwear: .init(title: "Giày dép", parentKey: .expensePersonalShopping, iconToken: "mistia.category.expense.personal_shopping.footwear", fallbackSystemName: "shoeprints.fill", iconColorHex: "#FF8A4C", group: .personal, activeDefault: true, aliases: []),
        .cosmeticsSkincare: .init(title: "Mỹ phẩm / skincare", parentKey: .expensePersonalShopping, iconToken: "mistia.category.expense.personal_shopping.cosmetics_skincare", fallbackSystemName: "sparkles", iconColorHex: "#FF6D8A", group: .personal, activeDefault: true, aliases: []),
        .personalCare: .init(title: "Chăm sóc cá nhân", parentKey: .expensePersonalShopping, iconToken: "mistia.category.expense.personal_shopping.personal_care", fallbackSystemName: "hands.sparkles.fill", iconColorHex: "#2DAA9E", group: .personal, activeDefault: true, aliases: []),
        .accessories: .init(title: "Phụ kiện", parentKey: .expensePersonalShopping, iconToken: "mistia.category.expense.personal_shopping.accessories", fallbackSystemName: "watch.analog", iconColorHex: "#F59B3F", group: .personal, activeDefault: true, aliases: []),
        .personalSupplies: .init(title: "Đồ dùng cá nhân", parentKey: .expensePersonalShopping, iconToken: "mistia.category.expense.personal_shopping.personal_supplies", fallbackSystemName: "shippingbox.fill", iconColorHex: "#7C85A3", group: .personal, activeDefault: true, aliases: []),
        .medicalCheckup: .init(title: "Khám bệnh", parentKey: .expenseHealth, iconToken: "mistia.category.expense.health.checkup", fallbackSystemName: "stethoscope", iconColorHex: "#F45C7E", group: .health, activeDefault: true, aliases: []),
        .medicine: .init(title: "Thuốc", parentKey: .expenseHealth, iconToken: "mistia.category.expense.health.medicine", fallbackSystemName: "pills.fill", iconColorHex: "#57B7FF", group: .health, activeDefault: true, aliases: []),
        .labTests: .init(title: "Xét nghiệm", parentKey: .expenseHealth, iconToken: "mistia.category.expense.health.lab_tests", fallbackSystemName: "cross.vial.fill", iconColorHex: "#2DAA9E", group: .health, activeDefault: true, aliases: []),
        .dental: .init(title: "Nha khoa", parentKey: .expenseHealth, iconToken: "mistia.category.expense.health.dental", fallbackSystemName: "cross.case.fill", iconColorHex: "#F59B3F", group: .health, activeDefault: true, aliases: []),
        .hospital: .init(title: "Bệnh viện / viện phí", parentKey: .expenseHealth, iconToken: "mistia.category.expense.health.hospital", fallbackSystemName: "cross.case.fill", iconColorHex: "#F45C7E", group: .health, activeDefault: true, aliases: ["Bệnh viện"]),
        .healthInsurance: .init(title: "Bảo hiểm sức khỏe", parentKey: .expenseHealth, iconToken: "mistia.category.expense.health.insurance", fallbackSystemName: "lock.shield.fill", iconColorHex: "#7C85A3", group: .health, activeDefault: true, aliases: []),
        .fitnessGym: .init(title: "Thể thao / gym", parentKey: .expenseHealth, iconToken: "mistia.category.expense.health.fitness_gym", fallbackSystemName: "figure.run", iconColorHex: "#2DAA9E", group: .health, activeDefault: true, aliases: []),
        .supplements: .init(title: "Thực phẩm bổ sung", parentKey: .expenseHealth, iconToken: "mistia.category.expense.health.supplements", fallbackSystemName: "leaf.fill", iconColorHex: "#2DAA9E", group: .health, activeDefault: true, aliases: ["Thực phẩm hỗ trợ"]),
        .moviesLeisure: .init(title: "Xem phim / đi chơi", parentKey: .expenseEntertainmentSocial, iconToken: "mistia.category.expense.entertainment_social.movies_leisure", fallbackSystemName: "film.fill", iconColorHex: "#F59B3F", group: .leisure, activeDefault: true, aliases: []),
        .travel: .init(title: "Du lịch", parentKey: .expenseEntertainmentSocial, iconToken: "mistia.category.expense.entertainment_social.travel", fallbackSystemName: "airplane", iconColorHex: "#5B7BFF", group: .leisure, activeDefault: true, aliases: []),
        .gamesApps: .init(title: "Game / app", parentKey: .expenseEntertainmentSocial, iconToken: "mistia.category.expense.entertainment_social.games_apps", fallbackSystemName: "gamecontroller.fill", iconColorHex: "#A76BFF", group: .leisure, activeDefault: true, aliases: []),
        .booksMusic: .init(title: "Sách / truyện / nhạc", parentKey: .expenseEntertainmentSocial, iconToken: "mistia.category.expense.entertainment_social.books_music", fallbackSystemName: "music.note.list", iconColorHex: "#57B7FF", group: .leisure, activeDefault: true, aliases: []),
        .partiesGatherings: .init(title: "Tiệc gia đình / liên hoan", parentKey: .expenseFamilyRelations, iconToken: "mistia.category.expense.entertainment_social.parties_gatherings", fallbackSystemName: "party.popper.fill", iconColorHex: "#FF7A59", group: .family, activeDefault: true, aliases: ["Tiệc tùng / liên hoan"]),
        .giftsCeremonies: .init(title: "Hiếu hỉ", parentKey: .expenseFamilyRelations, iconToken: "mistia.category.expense.entertainment_social.gifts_ceremonies", fallbackSystemName: "gift.fill", iconColorHex: "#FF6D8A", group: .family, activeDefault: true, aliases: ["Hiếu hỉ / quà tặng"]),
        .relationshipGifts: .init(title: "Quà tặng", parentKey: .expenseFamilyRelations, iconToken: "mistia.category.expense.family_relations.gifts", fallbackSystemName: "giftcard.fill", iconColorHex: "#FF8A4C", group: .family, activeDefault: true, aliases: []),
        .parentsSupportExpense: .init(title: "Biếu ông bà / cha mẹ", parentKey: .expenseFamilyRelations, iconToken: "mistia.category.expense.family_relations.parents_support", fallbackSystemName: "person.2.fill", iconColorHex: "#FFB347", group: .family, activeDefault: true, aliases: []),
        .familySupportExpense: .init(title: "Hỗ trợ người thân", parentKey: .expenseFamilyRelations, iconToken: "mistia.category.expense.family_relations.family_support", fallbackSystemName: "heart.text.square.fill", iconColorHex: "#F26A5A", group: .family, activeDefault: true, aliases: []),
        .charity: .init(title: "Từ thiện", parentKey: .expenseFamilyRelations, iconToken: "mistia.category.expense.entertainment_social.charity", fallbackSystemName: "heart.fill", iconColorHex: "#2DAA9E", group: .family, activeDefault: true, aliases: []),
        .subscriptions: .init(title: "Subscription giải trí", parentKey: .expenseEntertainmentSocial, iconToken: "mistia.category.expense.entertainment_social.subscriptions", fallbackSystemName: "play.tv.fill", iconColorHex: "#5B7BFF", group: .leisure, activeDefault: true, aliases: ["Subscription (Netflix, Spotify, iCloud...)", "Subscription"]),
        .hobbies: .init(title: "Sở thích cá nhân", parentKey: .expenseEntertainmentSocial, iconToken: "mistia.category.expense.entertainment_social.hobbies", fallbackSystemName: "paintbrush.pointed.fill", iconColorHex: "#A76BFF", group: .leisure, activeDefault: true, aliases: []),
        .coffeeFriends: .init(title: "Cà phê gặp bạn bè", parentKey: .expenseEntertainmentSocial, iconToken: "mistia.category.expense.entertainment_social.coffee_friends", fallbackSystemName: "cup.and.saucer.fill", iconColorHex: "#C46A6A", group: .leisure, activeDefault: true, aliases: []),
        .workTools: .init(title: "Dụng cụ học tập / làm việc", parentKey: .expenseWorkStudy, iconToken: "mistia.category.expense.work_study.tools", fallbackSystemName: "wrench.and.screwdriver.fill", iconColorHex: "#4C8DFF", group: .work, activeDefault: true, aliases: ["Dụng cụ làm việc"]),
        .workSoftwareSubscriptions: .init(title: "Phần mềm / subscription", parentKey: .expenseWorkStudy, iconToken: "mistia.category.expense.work_study.software", fallbackSystemName: "laptopcomputer", iconColorHex: "#5B7BFF", group: .work, activeDefault: true, aliases: ["Phần mềm / subscription công việc"]),
        .clientEntertainment: .init(title: "Tiếp khách / gặp đối tác", parentKey: .expenseWorkStudy, iconToken: "mistia.category.expense.work_study.client_entertainment", fallbackSystemName: "person.2.fill", iconColorHex: "#FF8A4C", group: .work, activeDefault: true, aliases: []),
        .businessTravel: .init(title: "Di chuyển công việc", parentKey: .expenseWorkStudy, iconToken: "mistia.category.expense.work_study.business_travel", fallbackSystemName: "car.fill", iconColorHex: "#2DAA9E", group: .work, activeDefault: true, aliases: []),
        .courses: .init(title: "Khóa học", parentKey: .expenseWorkStudy, iconToken: "mistia.category.expense.work_study.courses", fallbackSystemName: "graduationcap.fill", iconColorHex: "#A76BFF", group: .work, activeDefault: true, aliases: []),
        .professionalBooks: .init(title: "Sách / tài liệu", parentKey: .expenseWorkStudy, iconToken: "mistia.category.expense.work_study.professional_books", fallbackSystemName: "books.vertical.fill", iconColorHex: "#4C8DFF", group: .work, activeDefault: true, aliases: ["Sách chuyên môn"]),
        .examsCertificates: .init(title: "Thi cử / chứng chỉ", parentKey: .expenseWorkStudy, iconToken: "mistia.category.expense.work_study.exams_certificates", fallbackSystemName: "rosette", iconColorHex: "#F59B3F", group: .work, activeDefault: true, aliases: []),
        .insurance: .init(title: "Bảo hiểm nhân thọ", parentKey: .expenseFinancialObligations, iconToken: "mistia.category.expense.financial_obligations.insurance", fallbackSystemName: "lock.shield.fill", iconColorHex: "#7C85A3", group: .finance, activeDefault: true, aliases: ["Bảo hiểm"]),
        .taxesFees: .init(title: "Thuế / phí", parentKey: .expenseFinancialObligations, iconToken: "mistia.category.expense.financial_obligations.taxes_fees", fallbackSystemName: "receipt.fill", iconColorHex: "#F59B3F", group: .finance, activeDefault: true, aliases: []),
        .bankingFees: .init(title: "Phí ngân hàng", parentKey: .expenseFinancialObligations, iconToken: "mistia.category.expense.financial_obligations.banking_fees", fallbackSystemName: "building.columns.fill", iconColorHex: "#5B7BFF", group: .finance, activeDefault: true, aliases: []),
        .loanInterest: .init(title: "Lãi vay", parentKey: .expenseFinancialObligations, iconToken: "mistia.category.expense.financial_obligations.loan_interest", fallbackSystemName: "percent", iconColorHex: "#F45C7E", group: .finance, activeDefault: true, aliases: []),
        .loanRepayment: .init(title: "Trả góp", parentKey: .expenseFinancialObligations, iconToken: "mistia.category.expense.financial_obligations.loan_repayment", fallbackSystemName: "creditcard.and.123", iconColorHex: "#7C85A3", group: .finance, activeDefault: true, aliases: ["Trả góp / vay"]),
        .finesFees: .init(title: "Phạt / lệ phí", parentKey: .expenseFinancialObligations, iconToken: "mistia.category.expense.financial_obligations.fines_fees", fallbackSystemName: "exclamationmark.circle.fill", iconColorHex: "#F45C7E", group: .finance, activeDefault: true, aliases: []),
        .otherObligations: .init(title: "Nghĩa vụ tài chính khác", parentKey: .expenseFinancialObligations, iconToken: "mistia.category.expense.financial_obligations.other_obligations", fallbackSystemName: "tray.full.fill", iconColorHex: "#8A8A8E", group: .finance, activeDefault: true, aliases: ["Nghĩa vụ khác"]),
        .petFood: .init(title: "Thức ăn thú cưng", parentKey: .expensePetCare, iconToken: "mistia.category.expense.pet_care.pet_food", fallbackSystemName: "pawprint.fill", iconColorHex: "#57B7FF", group: .family, activeDefault: true, aliases: []),
        .petMedical: .init(title: "Khám / thuốc thú cưng", parentKey: .expensePetCare, iconToken: "mistia.category.expense.pet_care.pet_medical", fallbackSystemName: "cross.case.fill", iconColorHex: "#F45C7E", group: .family, activeDefault: true, aliases: []),
        .petSupplies: .init(title: "Đồ dùng thú cưng", parentKey: .expensePetCare, iconToken: "mistia.category.expense.pet_care.pet_supplies", fallbackSystemName: "shippingbox.fill", iconColorHex: "#5B7BFF", group: .family, activeDefault: true, aliases: []),
        .petGrooming: .init(title: "Grooming / chăm sóc", parentKey: .expensePetCare, iconToken: "mistia.category.expense.pet_care.pet_grooming", fallbackSystemName: "sparkles", iconColorHex: "#A76BFF", group: .family, activeDefault: true, aliases: []),
        .petOther: .init(title: "Chi khác cho thú cưng", parentKey: .expensePetCare, iconToken: "mistia.category.expense.pet_care.pet_other", fallbackSystemName: "tray.full.fill", iconColorHex: "#8A8A8E", group: .family, activeDefault: true, aliases: []),
        .otherExpense: .init(title: "Chi khác", parentKey: .expenseOther, iconToken: "mistia.category.expense.other.expense", fallbackSystemName: "tray.full.fill", iconColorHex: "#8A8A8E", group: .generic, activeDefault: false, aliases: []),
        .salary: .init(title: "Lương chính", parentKey: .incomeSalaryWork, iconToken: "mistia.category.income.salary_work.salary", fallbackSystemName: "banknote.fill", iconColorHex: "#2DAA9E", group: .income, activeDefault: true, aliases: ["Lương"]),
        .sideSalary: .init(title: "Lương phụ", parentKey: .incomeSalaryWork, iconToken: "mistia.category.income.salary_work.side_salary", fallbackSystemName: "banknote.fill", iconColorHex: "#57B7FF", group: .income, activeDefault: true, aliases: []),
        .bonus: .init(title: "Thưởng", parentKey: .incomeSalaryWork, iconToken: "mistia.category.income.salary_work.bonus", fallbackSystemName: "gift.fill", iconColorHex: "#FFB347", group: .income, activeDefault: true, aliases: []),
        .allowance: .init(title: "Phụ cấp", parentKey: .incomeSalaryWork, iconToken: "mistia.category.income.salary_work.allowance", fallbackSystemName: "wallet.pass.fill", iconColorHex: "#A76BFF", group: .income, activeDefault: true, aliases: []),
        .commission: .init(title: "Hoa hồng", parentKey: .incomeSalaryWork, iconToken: "mistia.category.income.salary_work.commission", fallbackSystemName: "percent", iconColorHex: "#FF7A59", group: .income, activeDefault: true, aliases: []),
        .freelance: .init(title: "Làm thêm / freelance", parentKey: .incomeSalaryWork, iconToken: "mistia.category.income.salary_work.freelance", fallbackSystemName: "laptopcomputer", iconColorHex: "#4C8DFF", group: .income, activeDefault: true, aliases: ["Freelance"]),
        .overtime: .init(title: "OT / tăng ca", parentKey: .incomeSalaryWork, iconToken: "mistia.category.income.salary_work.overtime", fallbackSystemName: "clock.fill", iconColorHex: "#F59B3F", group: .income, activeDefault: true, aliases: []),
        .sales: .init(title: "Doanh thu bán hàng", parentKey: .incomeBusiness, iconToken: "mistia.category.income.business.sales", fallbackSystemName: "storefront.fill", iconColorHex: "#F26A5A", group: .income, activeDefault: true, aliases: []),
        .serviceRevenue: .init(title: "Thu dịch vụ", parentKey: .incomeBusiness, iconToken: "mistia.category.income.business.service_revenue", fallbackSystemName: "sparkles", iconColorHex: "#57B7FF", group: .income, activeDefault: true, aliases: []),
        .businessProfit: .init(title: "Lợi nhuận kinh doanh", parentKey: .incomeBusiness, iconToken: "mistia.category.income.business.business_profit", fallbackSystemName: "chart.bar.fill", iconColorHex: "#2DAA9E", group: .income, activeDefault: true, aliases: []),
        .onlineCollaboratorIncome: .init(title: "Thu từ online", parentKey: .incomeBusiness, iconToken: "mistia.category.income.business.online_collaborator_income", fallbackSystemName: "person.2.fill", iconColorHex: "#5B7BFF", group: .income, activeDefault: true, aliases: []),
        .otherBusinessIncome: .init(title: "Thu kinh doanh khác", parentKey: .incomeBusiness, iconToken: "mistia.category.income.business.other_business_income", fallbackSystemName: "tray.full.fill", iconColorHex: "#8A8A8E", group: .income, activeDefault: true, aliases: []),
        .bankInterest: .init(title: "Lãi ngân hàng", parentKey: .incomeInvestmentFinance, iconToken: "mistia.category.income.investment_finance.bank_interest", fallbackSystemName: "building.columns.fill", iconColorHex: "#5B7BFF", group: .finance, activeDefault: true, aliases: []),
        .dividends: .init(title: "Cổ tức", parentKey: .incomeInvestmentFinance, iconToken: "mistia.category.income.investment_finance.dividends", fallbackSystemName: "chart.pie.fill", iconColorHex: "#A76BFF", group: .finance, activeDefault: true, aliases: []),
        .investmentGain: .init(title: "Lãi đầu tư", parentKey: .incomeInvestmentFinance, iconToken: "mistia.category.income.investment_finance.investment_gain", fallbackSystemName: "chart.line.uptrend.xyaxis", iconColorHex: "#2DAA9E", group: .finance, activeDefault: true, aliases: []),
        .loanInterestReceived: .init(title: "Lãi cho vay", parentKey: .incomeInvestmentFinance, iconToken: "mistia.category.income.investment_finance.loan_interest_received", fallbackSystemName: "hand.thumbsup.fill", iconColorHex: "#57B7FF", group: .finance, activeDefault: true, aliases: ["Cho vay được trả lãi"]),
        .otherFinancialIncome: .init(title: "Thu nhập tài chính khác", parentKey: .incomeInvestmentFinance, iconToken: "mistia.category.income.investment_finance.other_financial_income", fallbackSystemName: "tray.full.fill", iconColorHex: "#8A8A8E", group: .finance, activeDefault: true, aliases: []),
        .refund: .init(title: "Hoàn tiền mua hàng", parentKey: .incomeRefundAdjustment, iconToken: "mistia.category.income.refund_adjustment.refund", fallbackSystemName: "arrow.counterclockwise.circle.fill", iconColorHex: "#57B7FF", group: .income, activeDefault: true, aliases: ["Hoàn tiền"]),
        .cashback: .init(title: "Cashback", parentKey: .incomeRefundAdjustment, iconToken: "mistia.category.income.refund_adjustment.cashback", fallbackSystemName: "creditcard.and.123", iconColorHex: "#FFB347", group: .income, activeDefault: true, aliases: []),
        .reimbursement: .init(title: "Hoàn ứng", parentKey: .incomeRefundAdjustment, iconToken: "mistia.category.income.refund_adjustment.reimbursement", fallbackSystemName: "arrow.uturn.backward.circle.fill", iconColorHex: "#4C8DFF", group: .income, activeDefault: true, aliases: []),
        .peopleRepayment: .init(title: "Người khác trả lại tiền", parentKey: .incomeRefundAdjustment, iconToken: "mistia.category.income.refund_adjustment.people_repayment", fallbackSystemName: "person.crop.circle.badge.checkmark", iconColorHex: "#2DAA9E", group: .income, activeDefault: true, aliases: []),
        .expenseRecovery: .init(title: "Thu hồi khoản đã chi hộ", parentKey: .incomeRefundAdjustment, iconToken: "mistia.category.income.refund_adjustment.expense_recovery", fallbackSystemName: "person.2.wave.2.fill", iconColorHex: "#2DAA9E", group: .income, activeDefault: true, aliases: []),
        .insurancePayout: .init(title: "Bảo hiểm chi trả / hoàn tiền", parentKey: .incomeRefundAdjustment, iconToken: "mistia.category.income.refund_adjustment.insurance_payout", fallbackSystemName: "shield.fill", iconColorHex: "#5B7BFF", group: .income, activeDefault: true, aliases: []),
        .gift: .init(title: "Được tặng", parentKey: .incomeSupportGift, iconToken: "mistia.category.income.support_gift.gift", fallbackSystemName: "gift.fill", iconColorHex: "#FF6D8A", group: .income, activeDefault: true, aliases: ["Quà tặng"]),
        .supportReceived: .init(title: "Học bổng / hỗ trợ học tập", parentKey: .incomeSupportGift, iconToken: "mistia.category.income.support_gift.support_received", fallbackSystemName: "book.open.fill", iconColorHex: "#5B7BFF", group: .income, activeDefault: true, aliases: ["Được hỗ trợ"]),
        .subsidy: .init(title: "Trợ cấp xã hội", parentKey: .incomeSupportGift, iconToken: "mistia.category.income.support_gift.subsidy", fallbackSystemName: "hands.sparkles.fill", iconColorHex: "#2DAA9E", group: .income, activeDefault: true, aliases: ["Trợ cấp"]),
        .childAllowance: .init(title: "Trợ cấp con nhỏ", parentKey: .incomeSupportGift, iconToken: "mistia.category.income.support_gift.child_allowance", fallbackSystemName: "person.2.fill", iconColorHex: "#FF8A4C", group: .income, activeDefault: true, aliases: []),
        .maternityAllowance: .init(title: "Trợ cấp thai sản", parentKey: .incomeSupportGift, iconToken: "mistia.category.income.support_gift.maternity_allowance", fallbackSystemName: "person.2.fill", iconColorHex: "#FF6D8A", group: .income, activeDefault: true, aliases: []),
        .familySupport: .init(title: "Gia đình hỗ trợ", parentKey: .incomeSupportGift, iconToken: "mistia.category.income.support_gift.family_support", fallbackSystemName: "person.2.fill", iconColorHex: "#A76BFF", group: .income, activeDefault: true, aliases: ["Thu khác từ gia đình"]),
        .sellUsedItems: .init(title: "Bán đồ cũ", parentKey: .incomeLiquidation, iconToken: "mistia.category.income.liquidation.sell_used_items", fallbackSystemName: "tag.fill", iconColorHex: "#F59B3F", group: .income, activeDefault: true, aliases: []),
        .liquidateHousehold: .init(title: "Thanh lý đồ gia dụng", parentKey: .incomeLiquidation, iconToken: "mistia.category.income.liquidation.liquidate_household", fallbackSystemName: "chair.fill", iconColorHex: "#57B7FF", group: .income, activeDefault: true, aliases: []),
        .otherLiquidationIncome: .init(title: "Thu khác từ thanh lý", parentKey: .incomeLiquidation, iconToken: "mistia.category.income.liquidation.other_liquidation_income", fallbackSystemName: "tray.full.fill", iconColorHex: "#8A8A8E", group: .income, activeDefault: true, aliases: []),
        .otherIncome: .init(title: "Thu khác", parentKey: .incomeOther, iconToken: "mistia.category.income.other.income", fallbackSystemName: "plusminus.circle.fill", iconColorHex: "#8A8A8E", group: .generic, activeDefault: false, aliases: [])
    ]

    static let activeDefaults: [Self] = [
        .grocery, .dailySupplies, .dineOut, .businessMeals, .cafeTea, .foodDelivery, .snacks, .smallAppliances,
        .importGoods, .goodsSourcing, .shippingFee, .packaging, .platformFee, .marketingAds, .otherSalesCost,
        .rent, .mortgageInstallment, .electricity, .water, .internet, .phone, .gas, .condoFee, .homeRepair, .furnitureAppliance,
        .diapersMilk, .babyFood, .childSupplies, .childToys, .schoolBooksSupplies, .childTuition, .childExtracurricular, .childMedical, .childMedicine, .babyGear, .childcare, .familyOther,
        .fuel, .parking, .grabTaxi, .publicTransport, .vehicleMaintenance, .vehicleRepair, .carWash, .tolls, .vehicleInsurance, .vehicleRegistration,
        .clothes, .footwear, .cosmeticsSkincare, .personalCare, .accessories, .personalSupplies,
        .medicalCheckup, .medicine, .labTests, .dental, .hospital, .healthInsurance, .fitnessGym, .supplements,
        .giftsCeremonies, .relationshipGifts, .parentsSupportExpense, .familySupportExpense, .partiesGatherings, .charity,
        .moviesLeisure, .travel, .gamesApps, .booksMusic, .subscriptions, .hobbies, .coffeeFriends,
        .workTools, .workSoftwareSubscriptions, .clientEntertainment, .businessTravel, .courses, .professionalBooks, .examsCertificates,
        .insurance, .taxesFees, .bankingFees, .loanInterest, .loanRepayment, .finesFees, .otherObligations,
        .petFood, .petMedical, .petSupplies, .petGrooming, .petOther,
        .salary, .sideSalary, .bonus, .allowance, .commission, .freelance, .overtime,
        .sales, .serviceRevenue, .businessProfit, .onlineCollaboratorIncome, .otherBusinessIncome,
        .bankInterest, .dividends, .investmentGain, .loanInterestReceived, .otherFinancialIncome,
        .refund, .cashback, .reimbursement, .peopleRepayment, .expenseRecovery, .insurancePayout,
        .gift, .familySupport, .childAllowance, .maternityAllowance, .subsidy, .supportReceived,
        .sellUsedItems, .liquidateHousehold, .otherLiquidationIncome
    ]

    static let recurringBillQuickPickDefaults: [Self] = [
        .rent,
        .mortgageInstallment,
        .electricity,
        .water,
        .internet,
        .phone,
        .gas,
        .condoFee,
        .childTuition,
        .childcare,
        .healthInsurance,
        .insurance,
        .vehicleInsurance,
        .subscriptions,
        .workSoftwareSubscriptions,
        .fitnessGym,
        .bankingFees,
        .loanRepayment,
        .taxesFees
    ]

    private var meta: Meta {
        Self.metadata[self] ?? .init(title: rawValue, parentKey: nil, iconToken: rawValue, fallbackSystemName: "questionmark.circle.fill", iconColorHex: "#8A8A8E", group: .generic, activeDefault: false, aliases: [])
    }

    var id: String { rawValue }
    var title: String { localizedTitle(for: .current) }
    var legacyVietnameseName: String { meta.title }
    var parentKey: MistiaSystemCategoryParentKey? { meta.parentKey }
    var fallbackSystemName: String { meta.fallbackSystemName }
    var iconSymbolName: String { meta.iconToken }
    var iconColorHex: String { meta.iconColorHex }
    var pickerGroup: MistiaFinanceIconGroup { meta.group }
    var isActiveDefault: Bool { meta.activeDefault }
    var kind: TransactionCategoryKind { meta.parentKey?.kind ?? .expense }

    func knownDefaultNames() -> [String] {
        Array(Set([meta.title, meta.englishTitle, meta.japaneseTitle].compactMap { $0 } + meta.aliases))
    }

    func localizedTitle(for language: MistiaAppLanguage) -> String {
        switch language {
        case .vietnamese:
            return meta.title
        case .english:
            return meta.englishTitle ?? meta.title
        case .japanese:
            return meta.japaneseTitle ?? meta.title
        }
    }
}

nonisolated enum PlanningDueSourceKind: String, CaseIterable, Codable, Identifiable {
    case creditCard
    case recurringBill
    case installment

    var id: String { rawValue }
}

nonisolated enum PlanningDueOccurrenceStatus: String, CaseIterable, Codable, Identifiable {
    case pending
    case paid

    var id: String { rawValue }
}

nonisolated enum CreditCardNetwork: String, CaseIterable, Identifiable, Codable {
    case visa
    case mastercard
    case jcb
    case americanExpress
    case unionPay
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .visa:
            "Visa"
        case .mastercard:
            "Mastercard"
        case .jcb:
            "JCB"
        case .americanExpress:
            "American Express"
        case .unionPay:
            "UnionPay"
        case .other:
            mistiaLocalized(vi: "Khác", en: "Other", ja: "Other")
        }
    }
}

nonisolated enum TransactionPrimaryKind: String, CaseIterable, Identifiable, Codable {
    case expense
    case income
    case transfer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .expense:
            mistiaLocalized(vi: "Chi tiêu", en: "Expense", ja: "支出")
        case .income:
            mistiaLocalized(vi: "Thu nhập", en: "Income", ja: "収入")
        case .transfer:
            mistiaLocalized(vi: "Chuyển tiền", en: "Transfer", ja: "振替")
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
        }
    }

    var financeIconToken: String {
        switch self {
        case .expense:
            "mistia.flow.expense"
        case .income:
            "mistia.flow.income"
        case .transfer:
            "mistia.flow.transfer"
        }
    }
}

nonisolated enum TransactionTransferSubtype: String, CaseIterable, Identifiable, Codable {
    case internalTransfer
    case debt

    var id: String { rawValue }

    var title: String {
        switch self {
        case .internalTransfer:
            mistiaLocalized(vi: "Nội bộ", en: "Internal", ja: "内部")
        case .debt:
            mistiaLocalized(vi: "Công nợ", en: "Debt", ja: "貸し借り")
        }
    }

    var systemImage: String {
        switch self {
        case .internalTransfer:
            "arrow.left.arrow.right.circle"
        case .debt:
            "person.2.wave.2.fill"
        }
    }

    var financeIconToken: String {
        switch self {
        case .internalTransfer:
            "mistia.flow.transfer.internal"
        case .debt:
            "mistia.flow.transfer.debt"
        }
    }
}

nonisolated enum TransactionDebtIntent: String, CaseIterable, Identifiable, Codable {
    case lend
    case collect
    case borrow
    case repay

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lend:
            mistiaLocalized(vi: "Cho vay", en: "Lend", ja: "貸す")
        case .collect:
            mistiaLocalized(vi: "Thu nợ", en: "Collect debt", ja: "回収")
        case .borrow:
            mistiaLocalized(vi: "Đi vay", en: "Borrow", ja: "借りる")
        case .repay:
            mistiaLocalized(vi: "Trả nợ", en: "Repay", ja: "返済")
        }
    }

    var systemImage: String {
        switch self {
        case .lend:
            "arrow.up.right.circle.fill"
        case .collect:
            "arrow.down.left.circle.fill"
        case .borrow:
            "tray.and.arrow.down.fill"
        case .repay:
            "tray.and.arrow.up.fill"
        }
    }

    var financeIconToken: String {
        switch self {
        case .lend:
            "mistia.debt.lend"
        case .collect:
            "mistia.debt.collect"
        case .borrow:
            "mistia.debt.borrow"
        case .repay:
            "mistia.debt.repay"
        }
    }
}

nonisolated enum TransactionEntryStatus: String, CaseIterable, Identifiable, Codable {
    case posted
    case draft

    var id: String { rawValue }

    var title: String {
        switch self {
        case .posted:
            mistiaLocalized(vi: "Đã ghi nhận", en: "Recorded", ja: "記録済み")
        case .draft:
            mistiaLocalized(vi: "Bản nháp", en: "Draft", ja: "下書き")
        }
    }
}

nonisolated enum TransactionTimeScope: String, CaseIterable, Identifiable, Codable {
    case allTime
    case thisMonth
    case yesterday
    case today

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allTime:
            mistiaLocalized(vi: "Tất cả", en: "All", ja: "すべて")
        case .thisMonth:
            mistiaLocalized(vi: "Tháng này", en: "This month", ja: "今月")
        case .yesterday:
            mistiaLocalized(vi: "Hôm qua", en: "Yesterday", ja: "昨日")
        case .today:
            mistiaLocalized(vi: "Hôm nay", en: "Today", ja: "今日")
        }
    }
}

nonisolated enum TransactionStatusScope: String, CaseIterable, Identifiable, Codable {
    case all
    case postedOnly
    case draftOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            mistiaLocalized(vi: "Tất cả", en: "All", ja: "すべて")
        case .postedOnly:
            mistiaLocalized(vi: "Đã ghi nhận", en: "Recorded", ja: "記録済み")
        case .draftOnly:
            mistiaLocalized(vi: "Bản nháp", en: "Draft", ja: "下書き")
        }
    }
}
