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
            L10n.shared.corelogic.financeenums.wallets
        case .food:
            L10n.shared.corelogic.financeenums.food
        case .home:
            L10n.shared.corelogic.financeenums.home
        case .family:
            L10n.shared.corelogic.financeenums.family
        case .mobility:
            L10n.shared.corelogic.financeenums.mobility
        case .personal:
            L10n.shared.corelogic.financeenums.personal
        case .health:
            L10n.shared.corelogic.financeenums.health
        case .leisure:
            L10n.shared.corelogic.financeenums.leisure
        case .work:
            L10n.shared.corelogic.financeenums.work
        case .finance:
            L10n.shared.corelogic.financeenums.finance
        case .income:
            L10n.shared.corelogic.financeenums.income
        case .planning:
            L10n.shared.corelogic.financeenums.planning
        case .generic:
            L10n.shared.corelogic.financeenums.other2
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
            L10n.shared.corelogic.financeenums.cash
        case .payPay:
            "PayPay"
        case .bank:
            L10n.shared.corelogic.financeenums.bank
        case .creditCard:
            L10n.shared.corelogic.financeenums.creditCard
        case .eWallet:
            L10n.shared.corelogic.financeenums.eWalletBarcode
        case .prepaid:
            L10n.shared.corelogic.financeenums.prepaidICCard
        case .investment:
            L10n.shared.corelogic.financeenums.investmentStocks
        case .crypto:
            L10n.shared.corelogic.financeenums.cryptoDigitalAssets
        case .other:
            L10n.shared.corelogic.financeenums.otherWallet
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
        let normalizedColorHex = MistiaIconColorPalette.normalizedHex(colorHex)
        let normalizedDefault = MistiaIconColorPalette.normalizedHex(defaultColorHex)
        let presetDefault = MistiaIconColorPalette.presetHex(forDefault: defaultColorHex)
        return symbolName == defaultIconSymbolName
            && (normalizedColorHex == normalizedDefault || normalizedColorHex == presetDefault)
    }

    func migratedLegacyDefaultColorHex(for colorHex: String, symbolName: String) -> String? {
        let normalizedColorHex = MistiaIconColorPalette.normalizedHex(colorHex)
        let normalizedDefault = MistiaIconColorPalette.normalizedHex(defaultColorHex)
        let presetDefault = MistiaIconColorPalette.presetHex(forDefault: defaultColorHex)
        guard symbolName == defaultIconSymbolName,
              normalizedColorHex == normalizedDefault || normalizedColorHex == presetDefault else {
            return nil
        }
        return presetDefault
    }

    var balanceFieldTitle: String {
        switch self {
        case .creditCard:
            L10n.shared.corelogic.financeenums.currentDebt
        default:
            L10n.shared.corelogic.financeenums.openingBalance
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
            L10n.shared.corelogic.financeenums.expense
        case .income:
            L10n.shared.corelogic.financeenums.income
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

    func matchesDefaultIconAppearance(symbolName: String, colorHex: String) -> Bool {
        let normalizedColorHex = MistiaIconColorPalette.normalizedHex(colorHex)
        let normalizedDefault = MistiaIconColorPalette.normalizedHex(defaultColorHex)
        let presetDefault = MistiaIconColorPalette.presetHex(forDefault: defaultColorHex)
        return symbolName == defaultIconSymbolName
            && (normalizedColorHex == normalizedDefault || normalizedColorHex == presetDefault)
    }

    func migratedLegacyDefaultColorHex(for colorHex: String, symbolName: String) -> String? {
        let normalizedColorHex = MistiaIconColorPalette.normalizedHex(colorHex)
        let normalizedDefault = MistiaIconColorPalette.normalizedHex(defaultColorHex)
        let presetDefault = MistiaIconColorPalette.presetHex(forDefault: defaultColorHex)
        guard symbolName == defaultIconSymbolName,
              normalizedColorHex == normalizedDefault || normalizedColorHex == presetDefault else {
            return nil
        }
        return presetDefault
    }
}

nonisolated enum TransactionCategoryHierarchyRole: String, CaseIterable, Identifiable, Codable {
    case parent
    case child

    var id: String { rawValue }

    var title: String {
        switch self {
        case .parent:
            L10n.shared.corelogic.financeenums.parentCategory
        case .child:
            L10n.shared.corelogic.financeenums.childCategory
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

    private var parsed: ParsedSystemCategory? {
        MistiaSystemCategoryRegistry.shared.metadata(forId: rawValue)
    }

    static var activeDefaults: [Self] {
        MistiaSystemCategoryRegistry.shared.allParents
            .filter { $0.active }
            .compactMap { Self(rawValue: $0.id) }
    }

    var id: String { rawValue }
    var kind: TransactionCategoryKind { parsed?.kind(in: MistiaSystemCategoryRegistry.shared) ?? .expense }
    var title: String { localizedTitle(for: .current) }
    var legacyVietnameseName: String { parsed?.translations["vi"] ?? rawValue }
    var englishTitle: String { parsed?.translations["en"] ?? legacyVietnameseName }
    var japaneseTitle: String { parsed?.translations["ja"] ?? legacyVietnameseName }
    var fallbackSystemName: String { parsed?.fallbackIcon ?? "questionmark.circle.fill" }
    var iconSymbolName: String { parsed?.icon ?? rawValue }
    var iconColorHex: String { parsed?.color ?? "#8A8A8E" }
    var pickerGroup: MistiaFinanceIconGroup { parsed?.group ?? .generic }
    var isActiveDefault: Bool { parsed?.active ?? false }
    var showsOnlyWhenHasChildren: Bool {
        rawValue == "parent_expense_uncategorized" || rawValue == "parent_income_uncategorized"
    }

    func knownDefaultNames() -> [String] {
        parsed?.knownDefaultNames() ?? [rawValue]
    }

    func localizedTitle(for language: MistiaAppLanguage) -> String {
        parsed?.localizedTitle(for: language) ?? rawValue
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
    case balanceAdjustmentExpense = "balance_adjustment_expense"
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
    case balanceAdjustmentIncome = "balance_adjustment_income"
    static let recurringBillQuickPickDefaults: [Self] = [
        .rent,
        .mortgageInstallment,
        .electricity,
        .water,
        .internet,
        .phone,
        .gas,
        .condoFee,
        .publicTransport,
        .parking,
        .tolls,
        .fuel,
        .vehicleMaintenance,
        .vehicleRepair,
        .childTuition,
        .childcare,
        .healthInsurance,
        .insurance,
        .vehicleInsurance,
        .vehicleRegistration,
        .subscriptions,
        .workSoftwareSubscriptions,
        .fitnessGym,
        .bankingFees,
        .loanRepayment,
        .taxesFees
    ]

    private var parsed: ParsedSystemCategory? {
        MistiaSystemCategoryRegistry.shared.metadata(forId: rawValue)
    }

    static var activeDefaults: [Self] {
        MistiaSystemCategoryRegistry.shared.allParents
            .flatMap { $0.children ?? [] }
            .filter { $0.active }
            .compactMap { Self(rawValue: $0.id) }
    }

    var id: String { rawValue }
    var title: String { localizedTitle(for: .current) }
    var legacyVietnameseName: String { parsed?.translations["vi"] ?? rawValue }
    var englishTitle: String { parsed?.translations["en"] ?? legacyVietnameseName }
    var japaneseTitle: String { parsed?.translations["ja"] ?? legacyVietnameseName }
    var parentKey: MistiaSystemCategoryParentKey? {
        guard let parentId = MistiaSystemCategoryRegistry.shared.parentId(for: rawValue) else { return nil }
        return MistiaSystemCategoryParentKey(rawValue: parentId)
    }
    var fallbackSystemName: String { parsed?.fallbackIcon ?? "questionmark.circle.fill" }
    var iconSymbolName: String { parsed?.icon ?? rawValue }
    var iconColorHex: String { parsed?.color ?? "#8A8A8E" }
    var pickerGroup: MistiaFinanceIconGroup { parsed?.group ?? .generic }
    var isActiveDefault: Bool { parsed?.active ?? false }
    var kind: TransactionCategoryKind { parentKey?.kind ?? .expense }

    func knownDefaultNames() -> [String] {
        parsed?.knownDefaultNames() ?? [rawValue]
    }

    func localizedTitle(for language: MistiaAppLanguage) -> String {
        parsed?.localizedTitle(for: language) ?? rawValue
    }
}

nonisolated enum PlanningDueSourceKind: String, CaseIterable, Codable, Identifiable {
    case creditCard
    case recurringBill
    case installment

    var id: String { rawValue }
}

nonisolated enum PlanningBillScheduleKind: String, CaseIterable, Codable, Identifiable {
    case recurring
    case oneTime

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
            L10n.shared.corelogic.financeenums.other
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
            L10n.shared.corelogic.financeenums.expense
        case .income:
            L10n.shared.corelogic.financeenums.income
        case .transfer:
            L10n.shared.corelogic.financeenums.transfer
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
    case familyTransfer
    case debt

    var id: String { rawValue }

    var title: String {
        switch self {
        case .internalTransfer:
            L10n.shared.corelogic.financeenums.`internal`
        case .familyTransfer:
            L10n.shared.corelogic.financeenums.family
        case .debt:
            L10n.shared.corelogic.financeenums.debt
        }
    }

    var systemImage: String {
        switch self {
        case .internalTransfer:
            "arrow.left.arrow.right.circle"
        case .familyTransfer:
            "person.2.fill"
        case .debt:
            "person.2.wave.2.fill"
        }
    }

    var financeIconToken: String {
        switch self {
        case .internalTransfer:
            "mistia.flow.transfer.internal"
        case .familyTransfer:
            "mistia.flow.transfer.family"
        case .debt:
            "mistia.flow.transfer.debt"
        }
    }

    static func editorOptions(
        isFamilyEligible: Bool,
        includesFamilyTransfer: Bool
    ) -> [TransactionTransferSubtype] {
        var options: [TransactionTransferSubtype] = [.internalTransfer]
        if isFamilyEligible || includesFamilyTransfer {
            options.append(.familyTransfer)
        }
        options.append(.debt)
        return options
    }

    static func isEditorOptionEnabled(
        _ subtype: TransactionTransferSubtype,
        canPerformRemoteActions: Bool,
        isFamilyTransferDetail: Bool
    ) -> Bool {
        guard subtype == .familyTransfer else { return true }
        return isFamilyTransferDetail || canPerformRemoteActions
    }
}

nonisolated enum TransactionDebtIntent: String, CaseIterable, Identifiable, Codable {
    case lend
    case collect
    case borrow
    case repay

    var id: String { rawValue }

    var title: String {
        title(language: .current)
    }

    func title(language: MistiaAppLanguage) -> String {
        switch self {
        case .lend:
            L10n.shared.corelogic.financeenums.lend(language: language)
        case .collect:
            L10n.shared.corelogic.financeenums.collectDebt(language: language)
        case .borrow:
            L10n.shared.corelogic.financeenums.borrow(language: language)
        case .repay:
            L10n.shared.corelogic.financeenums.repay(language: language)
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

nonisolated enum SettlementKind: String, CaseIterable, Identifiable, Codable {
    case resale
    case sharedExpense

    var id: String { rawValue }
}

nonisolated enum SettlementStatus: String, CaseIterable, Identifiable, Codable {
    case preparing
    case open
    case partiallySettled
    case settled

    var id: String { rawValue }
}

nonisolated enum SettlementTransactionRole: String, CaseIterable, Identifiable, Codable {
    case resalePurchase
    case resaleReceipt
    case sharedExpensePaid
    case sharedExpenseReceipt
    case sharedExpensePayment

    var id: String { rawValue }
}

nonisolated enum SettlementDirection: String, CaseIterable, Identifiable, Codable {
    case receivable
    case payable

    var id: String { rawValue }
}

nonisolated enum TransactionEntryStatus: String, CaseIterable, Identifiable, Codable {
    case posted
    case draft

    var id: String { rawValue }

    var title: String {
        switch self {
        case .posted:
            L10n.shared.corelogic.financeenums.recorded
        case .draft:
            L10n.shared.corelogic.financeenums.draft
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
            L10n.shared.corelogic.financeenums.all
        case .thisMonth:
            L10n.shared.corelogic.financeenums.thisMonth
        case .yesterday:
            L10n.shared.corelogic.financeenums.yesterday
        case .today:
            L10n.shared.corelogic.financeenums.today
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
            L10n.shared.corelogic.financeenums.all
        case .postedOnly:
            L10n.shared.corelogic.financeenums.recorded
        case .draftOnly:
            L10n.shared.corelogic.financeenums.draft
        }
    }
}
