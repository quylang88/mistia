import SwiftUI

struct MistiaFinancePickerOption: Identifiable, Hashable {
    let token: String
    let title: String
    let group: MistiaFinanceIconGroup
    let defaultColorHex: String

    var id: String { token }
}

struct MistiaFinanceIconDescriptor: Hashable {
    let token: String
    let assetName: String?
    let fallbackSystemName: String
    let primaryHex: String
    let secondaryHex: String
    let accentHex: String
    let backgroundHexes: [String]
    let group: MistiaFinanceIconGroup
    let badgeSystemName: String?
}

enum MistiaFinanceIconRegistry {
    static func descriptor(for token: String) -> MistiaFinanceIconDescriptor? {
        if let category = MistiaSystemCategoryKey.allCases.first(where: { $0.iconSymbolName == token }) {
            return descriptor(
                token: token,
                fallbackSystemName: category.fallbackSystemName,
                baseHex: category.iconColorHex,
                group: category.pickerGroup,
                badgeSystemName: badge(for: category.pickerGroup)
            )
        }

        if let parent = MistiaSystemCategoryParentKey.allCases.first(where: { $0.iconSymbolName == token }) {
            return descriptor(
                token: token,
                fallbackSystemName: parent.fallbackSystemName,
                baseHex: parent.iconColorHex,
                group: parent.pickerGroup,
                badgeSystemName: badge(for: parent.pickerGroup)
            )
        }

        if let custom = explicitDescriptors[token] {
            return custom
        }

        return nil
    }

    static func defaultColorHex(for token: String) -> String {
        descriptor(for: token)?.primaryHex ?? "#8A8A8E"
    }

    static func categoryKey(for token: String) -> MistiaSystemCategoryKey? {
        MistiaSystemCategoryKey.activeDefaults.first(where: { $0.iconSymbolName == token })
    }

    static func activeCategoryOptions(for kind: TransactionCategoryKind) -> [MistiaFinancePickerOption] {
        let parentOptions = MistiaSystemCategoryParentKey.activeDefaults
            .filter { $0.kind == kind }
            .map {
                MistiaFinancePickerOption(
                    token: $0.iconSymbolName,
                    title: $0.title,
                    group: $0.pickerGroup,
                    defaultColorHex: $0.iconColorHex
                )
            }

        let childOptions = MistiaSystemCategoryKey.activeDefaults
            .filter { $0.kind == kind }
            .map {
                MistiaFinancePickerOption(
                    token: $0.iconSymbolName,
                    title: $0.title,
                    group: $0.pickerGroup,
                    defaultColorHex: $0.iconColorHex
                )
            }

        return parentOptions + childOptions
    }

    static let walletOptions: [MistiaFinancePickerOption] = [
        option(token: LedgerWalletKind.cash.defaultIconSymbolName, title: LedgerWalletKind.cash.title, group: .wallet),
        option(token: LedgerWalletKind.payPay.defaultIconSymbolName, title: LedgerWalletKind.payPay.title, group: .wallet),
        option(token: LedgerWalletKind.bank.defaultIconSymbolName, title: LedgerWalletKind.bank.title, group: .wallet),
        option(token: LedgerWalletKind.creditCard.defaultIconSymbolName, title: LedgerWalletKind.creditCard.title, group: .wallet),
        option(token: LedgerWalletKind.eWallet.defaultIconSymbolName, title: LedgerWalletKind.eWallet.title, group: .wallet),
        option(token: LedgerWalletKind.prepaid.defaultIconSymbolName, title: LedgerWalletKind.prepaid.title, group: .wallet),
        option(token: LedgerWalletKind.investment.defaultIconSymbolName, title: LedgerWalletKind.investment.title, group: .wallet),
        option(token: LedgerWalletKind.crypto.defaultIconSymbolName, title: LedgerWalletKind.crypto.title, group: .wallet),
        option(token: LedgerWalletKind.other.defaultIconSymbolName, title: LedgerWalletKind.other.title, group: .wallet),
        option(token: "mistia.wallet.savings", title: L10n.core.ui.mistiafinanceicons.savingsWallet, group: .wallet),
        option(token: "mistia.wallet.travel", title: L10n.core.ui.mistiafinanceicons.travelWallet, group: .wallet),
        option(token: "mistia.wallet.family", title: L10n.core.ui.mistiafinanceicons.familyWallet, group: .wallet),
        option(token: "mistia.wallet.emergency", title: L10n.core.ui.mistiafinanceicons.emergencyWallet, group: .wallet)
    ]

    static let goalOptions: [MistiaFinancePickerOption] = [
        option(token: "mistia.goal.savings", title: L10n.core.ui.mistiafinanceicons.savings, group: .planning),
        option(token: "mistia.goal.travel", title: L10n.core.ui.mistiafinanceicons.travel, group: .planning),
        option(token: "mistia.goal.home", title: L10n.core.ui.mistiafinanceicons.home, group: .planning),
        option(token: "mistia.goal.education", title: L10n.core.ui.mistiafinanceicons.study, group: .planning),
        option(token: "mistia.goal.vehicle", title: L10n.core.ui.mistiafinanceicons.vehicle, group: .planning),
        option(token: "mistia.goal.family", title: L10n.core.ui.mistiafinanceicons.family, group: .planning)
    ]

    static let installmentOptions: [MistiaFinancePickerOption] = [
        option(token: "mistia.plan.installment", title: L10n.core.ui.mistiafinanceicons.installment, group: .planning),
        option(token: "mistia.plan.loan", title: L10n.core.ui.mistiafinanceicons.loan, group: .planning),
        option(token: "mistia.plan.card_bill", title: L10n.core.ui.mistiafinanceicons.cardDebt, group: .planning),
        option(token: "mistia.plan.payment", title: L10n.core.ui.mistiafinanceicons.scheduledPayment, group: .planning)
    ]

    static let creditCardOptions: [MistiaFinancePickerOption] = [
        option(token: LedgerWalletKind.creditCard.defaultIconSymbolName, title: L10n.core.ui.mistiafinanceicons.classicCard, group: .wallet),
        option(token: "mistia.wallet.credit_card_premium", title: L10n.core.ui.mistiafinanceicons.premiumCard, group: .wallet),
        option(token: "mistia.wallet.credit_card_rewards", title: L10n.core.ui.mistiafinanceicons.rewardsCard, group: .wallet)
    ]

    private static let explicitDescriptors: [String: MistiaFinanceIconDescriptor] = [
        "mistia.flow.expense": descriptor(token: "mistia.flow.expense", fallbackSystemName: "arrow.up.right", baseHex: "#FF7A59", group: .finance, badgeSystemName: "minus"),
        "mistia.flow.income": descriptor(token: "mistia.flow.income", fallbackSystemName: "arrow.down.left", baseHex: "#2DAA9E", group: .income, badgeSystemName: "plus"),
        "mistia.flow.transfer": descriptor(token: "mistia.flow.transfer", fallbackSystemName: "arrow.left.arrow.right", baseHex: "#5B7BFF", group: .finance, badgeSystemName: "arrow.left.arrow.right"),
        "mistia.flow.transfer.internal": descriptor(token: "mistia.flow.transfer.internal", fallbackSystemName: "arrow.left.arrow.right.circle.fill", baseHex: "#5B7BFF", group: .finance, badgeSystemName: "building.columns.fill"),
        "mistia.flow.transfer.family": descriptor(token: "mistia.flow.transfer.family", fallbackSystemName: "person.2.fill", baseHex: "#A76BFF", group: .finance, badgeSystemName: "arrow.left.arrow.right"),
        "mistia.flow.transfer.debt": descriptor(token: "mistia.flow.transfer.debt", fallbackSystemName: "person.2.wave.2.fill", baseHex: "#FF8A4C", group: .finance, badgeSystemName: "person.fill"),
        "mistia.debt.lend": descriptor(token: "mistia.debt.lend", fallbackSystemName: "arrow.up.right.circle.fill", baseHex: "#FF7A59", group: .finance, badgeSystemName: "hand.raised.fill"),
        "mistia.debt.collect": descriptor(token: "mistia.debt.collect", fallbackSystemName: "arrow.down.left.circle.fill", baseHex: "#2DAA9E", group: .finance, badgeSystemName: "tray.full.fill"),
        "mistia.debt.borrow": descriptor(token: "mistia.debt.borrow", fallbackSystemName: "tray.and.arrow.down.fill", baseHex: "#5B7BFF", group: .finance, badgeSystemName: "person.crop.circle.badge.plus"),
        "mistia.debt.repay": descriptor(token: "mistia.debt.repay", fallbackSystemName: "tray.and.arrow.up.fill", baseHex: "#F59B3F", group: .finance, badgeSystemName: "checkmark.circle.fill"),
        "mistia.goal.savings": descriptor(token: "mistia.goal.savings", fallbackSystemName: "target", baseHex: "#2DAA9E", group: .planning, badgeSystemName: "banknote.fill"),
        "mistia.goal.travel": descriptor(token: "mistia.goal.travel", fallbackSystemName: "airplane", baseHex: "#5B7BFF", group: .planning, badgeSystemName: "sparkles"),
        "mistia.goal.home": descriptor(token: "mistia.goal.home", fallbackSystemName: "house.fill", baseHex: "#FF8A4C", group: .planning, badgeSystemName: "star.fill"),
        "mistia.goal.education": descriptor(token: "mistia.goal.education", fallbackSystemName: "graduationcap.fill", baseHex: "#A76BFF", group: .planning, badgeSystemName: "book.fill"),
        "mistia.goal.vehicle": descriptor(token: "mistia.goal.vehicle", fallbackSystemName: "car.fill", baseHex: "#2DAA9E", group: .planning, badgeSystemName: "flag.fill"),
        "mistia.goal.family": descriptor(token: "mistia.goal.family", fallbackSystemName: "person.2.fill", baseHex: "#FF6D8A", group: .planning, badgeSystemName: "heart.fill"),
        "mistia.plan.bill": descriptor(token: "mistia.plan.bill", fallbackSystemName: "doc.text.fill", baseHex: "#F59B3F", group: .planning, badgeSystemName: "calendar"),
        "mistia.plan.installment": descriptor(token: "mistia.plan.installment", fallbackSystemName: "creditcard.and.123", baseHex: "#7C85A3", group: .planning, badgeSystemName: "calendar"),
        "mistia.plan.loan": descriptor(token: "mistia.plan.loan", fallbackSystemName: "building.columns.fill", baseHex: "#5B7BFF", group: .planning, badgeSystemName: "percent"),
        "mistia.plan.card_bill": descriptor(token: "mistia.plan.card_bill", fallbackSystemName: "creditcard.fill", baseHex: "#A76BFF", group: .planning, badgeSystemName: "doc.text.fill"),
        "mistia.plan.payment": descriptor(token: "mistia.plan.payment", fallbackSystemName: "calendar.badge.clock", baseHex: "#2DAA9E", group: .planning, badgeSystemName: "checkmark"),
        "mistia.wallet.cash": descriptor(token: "mistia.wallet.cash", fallbackSystemName: "banknote.fill", baseHex: "#2DAA9E", group: .wallet, badgeSystemName: "wallet.pass.fill"),
        "mistia.wallet.paypay": descriptor(token: "mistia.wallet.paypay", fallbackSystemName: "qrcode", baseHex: "#FF7A59", group: .wallet, badgeSystemName: "iphone"),
        "mistia.wallet.bank": descriptor(token: "mistia.wallet.bank", fallbackSystemName: "building.columns.fill", baseHex: "#5B7BFF", group: .wallet, badgeSystemName: "creditcard.fill"),
        "mistia.wallet.credit_card": descriptor(token: "mistia.wallet.credit_card", fallbackSystemName: "creditcard.fill", baseHex: "#7C85A3", group: .wallet, badgeSystemName: "wave.3.right"),
        "mistia.wallet.savings": descriptor(token: "mistia.wallet.savings", fallbackSystemName: "banknote.fill", baseHex: "#2DAA9E", group: .wallet, badgeSystemName: "star.fill"),
        "mistia.wallet.travel": descriptor(token: "mistia.wallet.travel", fallbackSystemName: "suitcase.fill", baseHex: "#5B7BFF", group: .wallet, badgeSystemName: "airplane"),
        "mistia.wallet.family": descriptor(token: "mistia.wallet.family", fallbackSystemName: "person.2.fill", baseHex: "#FF6D8A", group: .wallet, badgeSystemName: "heart.fill"),
        "mistia.wallet.emergency": descriptor(token: "mistia.wallet.emergency", fallbackSystemName: "cross.case.fill", baseHex: "#F45C7E", group: .wallet, badgeSystemName: "shield.fill"),
        "mistia.wallet.credit_card_premium": descriptor(token: "mistia.wallet.credit_card_premium", fallbackSystemName: "creditcard.fill", baseHex: "#A76BFF", group: .wallet, badgeSystemName: "crown.fill"),
        "mistia.wallet.credit_card_rewards": descriptor(token: "mistia.wallet.credit_card_rewards", fallbackSystemName: "creditcard.fill", baseHex: "#FFB347", group: .wallet, badgeSystemName: "gift.fill"),
        "mistia.wallet.e_wallet": descriptor(token: "mistia.wallet.e_wallet", fallbackSystemName: "qrcode", baseHex: "#F26A5A", group: .wallet, badgeSystemName: "barcode.viewfinder"),
        "mistia.wallet.prepaid": descriptor(token: "mistia.wallet.prepaid", fallbackSystemName: "creditcard.fill", baseHex: "#FFB347", group: .wallet, badgeSystemName: "creditcard.and.123"),
        "mistia.wallet.investment": descriptor(token: "mistia.wallet.investment", fallbackSystemName: "chart.line.uptrend.xyaxis", baseHex: "#9A67FF", group: .wallet, badgeSystemName: "chart.pie.fill"),
        "mistia.wallet.crypto": descriptor(token: "mistia.wallet.crypto", fallbackSystemName: "bitcoinsign.circle.fill", baseHex: "#F59B3F", group: .wallet, badgeSystemName: "shield.fill"),
        "mistia.wallet.other": descriptor(token: "mistia.wallet.other", fallbackSystemName: "wallet.pass.fill", baseHex: "#8A8A8E", group: .wallet, badgeSystemName: "questionmark")
    ]

    private static let fluentAssetNamesByToken: [String: String] = {
        var mapping: [String: String] = [:]

        func assign(_ assetName: String, _ tokens: [String]) {
            for token in tokens {
                mapping[token] = assetName
            }
        }

        assign("ic_fluent_food_24_color", [
            "mistia.category.parent.expense.food",
            "mistia.category.expense.food.grocery",
            "mistia.category.expense.food.dine_out",
            "mistia.category.expense.food.cafe_tea",
            "mistia.category.expense.food.snacks"
        ])

        assign("ic_fluent_building_home_24_color", [
            "mistia.category.parent.expense.home_bills",
            "mistia.category.expense.home_bills.rent"
        ])

        assign("ic_fluent_vault_24_color", [
            "mistia.category.expense.home_bills.mortgage_installment"
        ])

        assign("ic_fluent_lightbulb_24_color", [
            "mistia.category.expense.home_bills.electricity"
        ])

        assign("ic_fluent_cloud_24_color", [
            "mistia.category.expense.home_bills.water"
        ])

        assign("ic_fluent_wifi_24_color", [
            "mistia.category.expense.home_bills.internet"
        ])

        assign("ic_fluent_phone_24_color", [
            "mistia.category.expense.home_bills.phone"
        ])

        assign("ic_fluent_lightbulb_filament_24_color", [
            "mistia.category.expense.home_bills.gas"
        ])

        assign("ic_fluent_building_multiple_24_color", [
            "mistia.category.expense.home_bills.condo_fee",
            "mistia.category.expense.transport_vehicle.parking"
        ])

        assign("ic_fluent_wrench_screwdriver_24_color", [
            "mistia.category.expense.home_bills.home_repair",
            "mistia.category.expense.transport_vehicle.repair"
        ])

        assign("ic_fluent_home_24_color", [
            "mistia.category.expense.home_bills.furniture_appliance",
            "mistia.category.expense.family_children.baby_gear",
            "mistia.category.income.liquidation.liquidate_household",
            "mistia.goal.home"
        ])

        assign("ic_fluent_people_home_24_color", [
            "mistia.category.parent.expense.family_children",
            "mistia.category.expense.family_relations.parents_support",
            "mistia.category.income.support_gift.child_allowance",
            "mistia.goal.family",
            "mistia.wallet.family"
        ])

        assign("ic_fluent_people_team_24_color", [
            "mistia.category.parent.expense.family_relations",
            "mistia.category.expense.family_children.child_supplies",
            "mistia.category.expense.family_children.childcare",
            "mistia.category.expense.entertainment_social.parties_gatherings",
            "mistia.category.income.support_gift.subsidy"
        ])

        assign("ic_fluent_food_24_color", [
            "mistia.category.expense.family_children.baby_food"
        ])

        assign("ic_fluent_gift_24_color", [
            "mistia.category.expense.family_children.child_toys",
            "mistia.category.expense.entertainment_social.gifts_ceremonies",
            "mistia.category.income.support_gift.gift"
        ])

        assign("ic_fluent_book_open_24_color", [
            "mistia.category.expense.family_children.child_tuition",
            "mistia.category.income.support_gift.support_received",
            "mistia.goal.education"
        ])

        assign("ic_fluent_book_24_color", [
            "mistia.category.expense.family_children.school_books_supplies"
        ])

        assign("ic_fluent_sport_24_color", [
            "mistia.category.expense.family_children.child_extracurricular"
        ])

        assign("ic_fluent_patient_24_color", [
            "mistia.category.expense.family_children.child_medical",
            "mistia.category.parent.expense.health",
            "mistia.category.expense.health.checkup",
            "mistia.category.expense.health.dental",
            "mistia.category.expense.health.hospital",
            "mistia.category.expense.pet_care.pet_medical"
        ])

        assign("ic_fluent_molecule_24_color", [
            "mistia.category.expense.health.medicine",
            "mistia.category.expense.health.lab_tests",
            "mistia.category.expense.family_children.child_medicine"
        ])

        assign("ic_fluent_sport_24_color", [
            "mistia.category.expense.health.fitness_gym"
        ])

        assign("ic_fluent_location_ripple_24_color", [
            "mistia.category.parent.expense.transport_vehicle",
            "mistia.category.expense.transport_vehicle.fuel",
            "mistia.category.expense.transport_vehicle.public_transport",
            "mistia.category.expense.work_study.business_travel",
            "mistia.goal.vehicle"
        ])

        assign("ic_fluent_receipt_24_color", [
            "mistia.category.expense.transport_vehicle.tolls",
            "mistia.category.income.refund_adjustment.reimbursement",
            "mistia.category.expense.financial_obligations.fines_fees"
        ])

        assign("ic_fluent_shield_checkmark_24_color", [
            "mistia.category.expense.transport_vehicle.insurance",
            "mistia.category.expense.health.insurance",
            "mistia.category.income.refund_adjustment.insurance_payout"
        ])

        assign("ic_fluent_document_text_24_color", [
            "mistia.category.expense.transport_vehicle.registration"
        ])

        assign("ic_fluent_gift_card_24_color", [
            "mistia.category.parent.expense.personal_shopping",
            "mistia.category.expense.personal_shopping.personal_supplies",
            "mistia.category.income.salary_work.allowance",
            "mistia.category.expense.pet_care.pet_supplies"
        ])

        assign("ic_fluent_premium_24_color", [
            "mistia.category.expense.personal_shopping.clothes",
            "mistia.category.expense.personal_shopping.footwear",
            "mistia.wallet.credit_card_premium"
        ])

        assign("ic_fluent_paint_brush_24_color", [
            "mistia.category.expense.personal_shopping.cosmetics_skincare"
        ])

        assign("ic_fluent_person_heart_24_color", [
            "mistia.category.expense.personal_shopping.personal_care",
            "mistia.category.expense.family_relations.gifts",
            "mistia.category.income.support_gift.maternity_allowance"
        ])

        assign("ic_fluent_apps_24_color", [
            "mistia.category.parent.expense.entertainment_social",
            "mistia.category.expense.entertainment_social.movies_leisure",
            "mistia.category.expense.entertainment_social.games_apps"
        ])

        assign("ic_fluent_paint_brush_24_color", [
            "mistia.category.expense.entertainment_social.hobbies",
            "mistia.category.expense.pet_care.pet_grooming"
        ])

        assign("ic_fluent_apps_list_detail_24_color", [
            "mistia.wallet.other",
            "mistia.category.expense.family_children.family_other",
            "mistia.category.expense.entertainment_social.subscriptions",
            "mistia.category.parent.expense.other",
            "mistia.category.expense.other.expense",
            "mistia.category.income.business.other_business_income",
            "mistia.category.income.investment_finance.other_financial_income",
            "mistia.category.parent.income.other",
            "mistia.category.income.other.income",
            "mistia.category.income.liquidation.other_liquidation_income",
            "mistia.category.expense.pet_care.pet_other"
        ])

        assign("ic_fluent_beach_24_color", [
            "mistia.category.expense.entertainment_social.travel",
            "mistia.goal.travel",
            "mistia.wallet.travel"
        ])

        assign("ic_fluent_headphones_24_color", [
            "mistia.category.expense.entertainment_social.books_music"
        ])

        assign("ic_fluent_gift_24_color", [
            "mistia.category.expense.family_children.child_toys",
            "mistia.category.expense.entertainment_social.gifts_ceremonies",
            "mistia.category.income.support_gift.gift"
        ])

        assign("ic_fluent_heart_24_color", [
            "mistia.category.expense.entertainment_social.charity",
            "mistia.category.expense.family_children.diapers_milk",
            "mistia.category.parent.expense.pet_care",
            "mistia.category.parent.income.support_gift"
        ])

        assign("ic_fluent_briefcase_24_color", [
            "mistia.category.parent.expense.work_study",
            "mistia.category.parent.income.salary_work"
        ])

        assign("ic_fluent_toolbox_24_color", [
            "mistia.category.expense.transport_vehicle.maintenance",
            "mistia.category.expense.work_study.tools"
        ])

        assign("ic_fluent_phone_laptop_24_color", [
            "mistia.category.expense.work_study.software",
            "mistia.category.income.salary_work.freelance"
        ])

        assign("ic_fluent_people_chat_24_color", [
            "mistia.category.expense.work_study.client_entertainment",
            "mistia.category.income.business.service_revenue",
            "mistia.category.expense.entertainment_social.coffee_friends"
        ])

        assign("ic_fluent_people_sync_24_color", [
            "mistia.category.expense.family_relations.family_support",
            "mistia.category.income.support_gift.family_support",
            "mistia.category.income.refund_adjustment.people_repayment",
            "mistia.flow.transfer.debt"
        ])

        assign("ic_fluent_book_open_lightbulb_24_color", [
            "mistia.category.expense.work_study.courses"
        ])

        assign("ic_fluent_book_database_24_color", [
            "mistia.category.expense.work_study.professional_books"
        ])

        assign("ic_fluent_certificate_24_color", [
            "mistia.category.expense.work_study.exams_certificates"
        ])

        assign("ic_fluent_data_pie_24_color", [
            "mistia.category.parent.income.investment_finance",
            "mistia.category.income.investment_finance.dividends"
        ])

        assign("ic_fluent_lock_shield_24_color", [
            "mistia.category.expense.financial_obligations.insurance"
        ])

        assign("ic_fluent_building_government_24_color", [
            "mistia.category.expense.financial_obligations.taxes_fees"
        ])

        assign("ic_fluent_building_24_color", [
            "mistia.category.expense.financial_obligations.banking_fees",
            "mistia.category.income.investment_finance.bank_interest",
            "mistia.wallet.bank"
        ])

        assign("ic_fluent_data_trending_24_color", [
            "mistia.category.expense.financial_obligations.loan_interest",
            "mistia.category.income.salary_work.commission",
            "mistia.category.income.business.business_profit",
            "mistia.category.income.investment_finance.investment_gain"
        ])

        assign("ic_fluent_contact_card_24_color", [
            "mistia.category.parent.expense.financial_obligations",
            "mistia.category.expense.financial_obligations.loan_repayment",
            "mistia.wallet.credit_card",
            "mistia.wallet.prepaid",
            "mistia.plan.card_bill"
        ])

        assign("ic_fluent_document_lock_24_color", [
            "mistia.category.expense.financial_obligations.other_obligations"
        ])

        assign("ic_fluent_coin_multiple_24_color", [
            "mistia.flow.income",
            "mistia.wallet.cash",
            "mistia.category.income.salary_work.salary",
            "mistia.category.income.salary_work.side_salary",
            "mistia.category.income.investment_finance.loan_interest_received"
        ])

        assign("ic_fluent_trophy_24_color", [
            "mistia.category.income.salary_work.bonus"
        ])

        assign("ic_fluent_building_store_24_color", [
            "mistia.category.parent.income.business",
            "mistia.category.income.business.sales"
        ])

        assign("ic_fluent_phone_laptop_24_color", [
            "mistia.category.income.business.online_collaborator_income"
        ])

        assign("ic_fluent_arrow_clockwise_dashes_24_color", [
            "mistia.category.parent.income.refund_adjustment",
            "mistia.category.income.refund_adjustment.refund",
            "mistia.category.expense.transport_vehicle.car_wash"
        ])

        assign("ic_fluent_reward_24_color", [
            "mistia.category.expense.personal_shopping.accessories",
            "mistia.category.expense.health.supplements",
            "mistia.category.income.refund_adjustment.cashback",
            "mistia.wallet.credit_card_rewards"
        ])

        assign("ic_fluent_savings_24_color", [
            "mistia.goal.savings",
            "mistia.wallet.savings"
        ])

        assign("ic_fluent_calendar_clock_24_color", [
            "mistia.category.income.salary_work.overtime",
            "mistia.plan.bill",
            "mistia.plan.payment"
        ])

        assign("ic_fluent_calendar_sync_24_color", [
            "mistia.plan.installment"
        ])

        assign("ic_fluent_vault_24_color", [
            "mistia.plan.loan",
            "mistia.wallet.emergency",
            "mistia.wallet.investment",
            "mistia.wallet.crypto"
        ])

        assign("ic_fluent_scan_type_24_color", [
            "mistia.wallet.paypay",
            "mistia.wallet.e_wallet"
        ])

        assign("ic_fluent_arrow_square_down_24_color", [
            "mistia.flow.expense",
            "mistia.debt.collect"
        ])

        assign("ic_fluent_arrow_sync_24_color", [
            "mistia.flow.transfer",
            "mistia.flow.transfer.internal",
            "mistia.category.expense.transport_vehicle.grab_taxi",
            "mistia.category.income.refund_adjustment.expense_recovery"
        ])

        assign("ic_fluent_send_24_color", [
            "mistia.category.expense.food.delivery",
            "mistia.debt.lend"
        ])

        assign("ic_fluent_arrow_square_24_color", [
            "mistia.debt.borrow",
            "mistia.category.parent.income.liquidation",
            "mistia.category.income.liquidation.sell_used_items"
        ])

        assign("ic_fluent_checkmark_circle_24_color", [
            "mistia.debt.repay"
        ])

        assign("ic_fluent_building_store_24_color", [
            "mistia.category.expense.food.grocery"
        ])

        assign("ic_fluent_food_24_color", [
            "mistia.category.expense.food.dine_out"
        ])

        assign("ic_fluent_chat_24_color", [
            "mistia.category.expense.food.cafe_tea"
        ])

        assign("ic_fluent_scan_type_24_color", [
            "mistia.category.expense.food.daily_supplies"
        ])

        assign("ic_fluent_send_24_color", [
            "mistia.category.expense.food.delivery"
        ])

        assign("ic_fluent_people_chat_24_color", [
            "mistia.category.expense.food.business_meals"
        ])
        
        assign("ic_fluent_lightbulb_24_color", [
            "mistia.category.expense.food.small_appliances"
        ])

        assign("ic_fluent_reward_24_color", [
            "mistia.category.expense.food.snacks"
        ])

        assign("ic_fluent_arrow_square_down_24_color", [
            "mistia.category.expense.cost_of_goods.import_goods"
        ])

        assign("ic_fluent_location_ripple_24_color", [
            "mistia.category.expense.cost_of_goods.goods_sourcing"
        ])

        assign("ic_fluent_fast_forward_circle_24_color", [
            "mistia.category.expense.cost_of_goods.shipping_fee"
        ])

        assign("ic_fluent_ribbon_24_color", [
            "mistia.category.expense.cost_of_goods.packaging"
        ])

        assign("ic_fluent_globe_24_color", [
            "mistia.category.expense.cost_of_goods.platform_fee"
        ])

        assign("ic_fluent_megaphone_loud_24_color", [
            "mistia.category.expense.cost_of_goods.marketing_ads"
        ])

        assign("ic_fluent_receipt_24_color", [
            "mistia.category.expense.cost_of_goods.other_sales_cost"
        ])

        assign("ic_fluent_book_contacts_24_color", [
            "mistia.category.expense.family_relations.parents_support"
        ])

        assign("ic_fluent_building_people_24_color", [
            "mistia.category.expense.family_children.child_tuition",
            "mistia.category.expense.health.hospital",
            "mistia.category.income.support_gift.subsidy"
        ])

        assign("ic_fluent_calendar_checkmark_24_color", [
            "mistia.category.expense.family_children.childcare",
            "mistia.category.expense.health.checkup"
        ])

        assign("ic_fluent_board_24_color", [
            "mistia.category.expense.family_children.child_toys"
        ])

        assign("ic_fluent_book_star_24_color", [
            "mistia.category.expense.family_children.school_books_supplies"
        ])

        assign("ic_fluent_flag_24_color", [
            "mistia.category.expense.family_children.child_extracurricular"
        ])

        assign("ic_fluent_gauge_24_color", [
            "mistia.category.expense.transport_vehicle.fuel"
        ])

        assign("ic_fluent_building_government_search_24_color", [
            "mistia.category.expense.transport_vehicle.registration"
        ])

        assign("ic_fluent_clipboard_task_24_color", [
            "mistia.category.expense.health.lab_tests"
        ])

        assign("ic_fluent_clipboard_text_edit_24_color", [
            "mistia.category.expense.health.dental"
        ])

        assign("ic_fluent_globe_shield_24_color", [
            "mistia.category.expense.health.insurance"
        ])

        assign("ic_fluent_animal_paw_print_24_color", [
            "mistia.category.parent.expense.pet_care"
        ])

        assign("ic_fluent_food_24_color", [
            "mistia.category.expense.pet_care.pet_food"
        ])

        assign("ic_fluent_gift_card_24_color", [
            "mistia.category.expense.family_relations.gifts"
        ])

        assign("ic_fluent_chat_multiple_24_color", [
            "mistia.category.expense.entertainment_social.parties_gatherings"
        ])

        assign("ic_fluent_camera_24_color", [
            "mistia.category.expense.entertainment_social.movies_leisure"
        ])

        assign("ic_fluent_library_24_color", [
            "mistia.category.expense.entertainment_social.books_music"
        ])

        assign("ic_fluent_bookmark_24_color", [
            "mistia.category.expense.entertainment_social.subscriptions"
        ])

        assign("ic_fluent_comment_multiple_24_color", [
            "mistia.category.expense.entertainment_social.coffee_friends"
        ])

        assign("ic_fluent_document_edit_24_color", [
            "mistia.category.expense.financial_obligations.fines_fees"
        ])

        assign("ic_fluent_document_folder_24_color", [
            "mistia.category.expense.financial_obligations.other_obligations"
        ])

        assign("ic_fluent_vault_24_color", [
            "mistia.category.expense.financial_obligations.loan_repayment"
        ])

        assign("ic_fluent_chart_multiple_24_color", [
            "mistia.category.income.salary_work.commission",
            "mistia.category.parent.income.investment_finance"
        ])

        assign("ic_fluent_clock_alarm_24_color", [
            "mistia.category.income.salary_work.overtime"
        ])

        assign("ic_fluent_data_area_24_color", [
            "mistia.category.income.business.business_profit"
        ])

        assign("ic_fluent_link_multiple_24_color", [
            "mistia.category.income.business.online_collaborator_income"
        ])

        assign("ic_fluent_data_line_24_color", [
            "mistia.category.income.investment_finance.investment_gain"
        ])

        assign("ic_fluent_data_scatter_24_color", [
            "mistia.category.income.investment_finance.other_financial_income"
        ])

        assign("ic_fluent_document_add_24_color", [
            "mistia.category.income.refund_adjustment.reimbursement"
        ])

        assign("ic_fluent_food_carrot_24_filled", [
            "mistia.category.expense.food.grocery"
        ])

        assign("ic_fluent_drink_to_go_24_filled", [
            "mistia.category.expense.food.cafe_tea"
        ])

        assign("ic_fluent_drink_coffee_24_filled", [
            "mistia.category.expense.entertainment_social.coffee_friends"
        ])

        assign("ic_fluent_drop_24_filled", [
            "mistia.category.expense.home_bills.water"
        ])

        assign("ic_fluent_clock_bill_24_filled", [
            "mistia.category.expense.home_bills.condo_fee"
        ])

        assign("ic_fluent_gas_pump_24_filled", [
            "mistia.category.expense.transport_vehicle.fuel"
        ])

        assign("ic_fluent_vehicle_car_parking_24_filled", [
            "mistia.category.expense.transport_vehicle.parking"
        ])

        assign("ic_fluent_vehicle_cab_24_filled", [
            "mistia.category.expense.transport_vehicle.grab_taxi"
        ])

        assign("ic_fluent_vehicle_subway_24_filled", [
            "mistia.category.expense.transport_vehicle.public_transport"
        ])

        assign("ic_fluent_vehicle_car_collision_24_filled", [
            "mistia.category.expense.transport_vehicle.repair"
        ])

        assign("ic_fluent_broom_24_filled", [
            "mistia.category.expense.transport_vehicle.car_wash"
        ])

        assign("ic_fluent_clothes_hanger_24_filled", [
            "mistia.category.parent.expense.personal_shopping",
            "mistia.category.expense.personal_shopping.clothes"
        ])

        assign("ic_fluent_cart_24_filled", [
            "mistia.category.expense.personal_shopping.personal_supplies"
        ])

        assign("ic_fluent_document_heart_pulse_24_filled", [
            "mistia.category.expense.health.insurance"
        ])

        assign("ic_fluent_filmstrip_play_24_filled", [
            "mistia.category.expense.entertainment_social.movies_leisure"
        ])

        assign("ic_fluent_games_24_filled", [
            "mistia.category.expense.entertainment_social.games_apps"
        ])

        assign("ic_fluent_headphones_sound_wave_24_filled", [
            "mistia.category.expense.entertainment_social.books_music"
        ])

        assign("ic_fluent_calendar_play_24_filled", [
            "mistia.category.expense.entertainment_social.subscriptions"
        ])

        assign("ic_fluent_gift_open_24_filled", [
            "mistia.category.expense.family_relations.gifts",
            "mistia.category.income.support_gift.gift"
        ])

        assign("ic_fluent_clipboard_heart_24_filled", [
            "mistia.category.expense.entertainment_social.charity"
        ])

        assign("ic_fluent_animal_paw_print_24_color", [
            "mistia.category.parent.expense.pet_care"
        ])

        assign("ic_fluent_animal_paw_print_24_color", [
            "mistia.category.expense.pet_care.pet_other"
        ])

        assign("ic_fluent_animal_dog_24_filled", [
            "mistia.category.expense.pet_care.pet_food"
        ])

        assign("ic_fluent_animal_cat_24_filled", [
            "mistia.category.expense.pet_care.pet_supplies"
        ])

        assign("ic_fluent_building_bank_24_filled", [
            "mistia.category.income.investment_finance.bank_interest",
            "mistia.wallet.bank"
        ])

        assign("ic_fluent_building_bank_toolbox_24_filled", [
            "mistia.category.expense.financial_obligations.banking_fees"
        ])

        assign("ic_fluent_credit_card_clock_24_filled", [
            "mistia.category.expense.financial_obligations.loan_repayment",
            "mistia.plan.card_bill"
        ])

        assign("ic_fluent_card_ui_24_filled", [
            "mistia.wallet.credit_card"
        ])

        assign("ic_fluent_card_ui_portrait_flip_24_filled", [
            "mistia.wallet.credit_card_premium"
        ])

        assign("ic_fluent_gift_card_money_24_filled", [
            "mistia.wallet.credit_card_rewards"
        ])

        return mapping
    }()

    private static func option(token: String, title: String, group: MistiaFinanceIconGroup) -> MistiaFinancePickerOption {
        MistiaFinancePickerOption(
            token: token,
            title: title,
            group: group,
            defaultColorHex: defaultColorHex(for: token)
        )
    }

    private static func fluentAssetName(for token: String, group: MistiaFinanceIconGroup) -> String? {
        if let assetName = fluentAssetNamesByToken[token] {
            return assetName
        }

        switch group {
        case .wallet:
            return "ic_fluent_coin_multiple_24_color"
        case .food:
            return "ic_fluent_food_24_color"
        case .home:
            return "ic_fluent_building_home_24_color"
        case .family:
            return "ic_fluent_people_home_24_color"
        case .mobility:
            return "ic_fluent_location_ripple_24_color"
        case .personal:
            return "ic_fluent_gift_card_24_color"
        case .health:
            return "ic_fluent_patient_24_color"
        case .leisure:
            return "ic_fluent_apps_24_color"
        case .work:
            return "ic_fluent_briefcase_24_color"
        case .finance:
            return "ic_fluent_data_pie_24_color"
        case .income:
            return "ic_fluent_coin_multiple_24_color"
        case .planning:
            return "ic_fluent_calendar_clock_24_color"
        case .generic:
            return "ic_fluent_apps_list_detail_24_color"
        }
    }

    static func assetUsesTemplate(_ assetName: String) -> Bool {
        assetName.hasSuffix("_filled") || assetName.hasSuffix("_regular")
    }

    private static func badge(for group: MistiaFinanceIconGroup) -> String? {
        switch group {
        case .wallet:
            "sparkles"
        case .food:
            "leaf.fill"
        case .home:
            "bolt.fill"
        case .family:
            "heart.fill"
        case .mobility:
            "location.fill"
        case .personal:
            "sparkles"
        case .health:
            "cross.fill"
        case .leisure:
            "play.fill"
        case .work:
            "briefcase.fill"
        case .finance:
            "percent"
        case .income:
            "plus"
        case .planning:
            "calendar"
        case .generic:
            nil
        }
    }

    private static func descriptor(
        token: String,
        fallbackSystemName: String,
        baseHex: String,
        group: MistiaFinanceIconGroup,
        badgeSystemName: String?
    ) -> MistiaFinanceIconDescriptor {
        let palette = palette(for: group, baseHex: baseHex)
        return MistiaFinanceIconDescriptor(
            token: token,
            assetName: fluentAssetName(for: token, group: group),
            fallbackSystemName: fallbackSystemName,
            primaryHex: palette.primaryHex,
            secondaryHex: palette.secondaryHex,
            accentHex: palette.accentHex,
            backgroundHexes: palette.backgroundHexes,
            group: group,
            badgeSystemName: badgeSystemName
        )
    }

    private static func palette(for group: MistiaFinanceIconGroup, baseHex: String) -> (primaryHex: String, secondaryHex: String, accentHex: String, backgroundHexes: [String]) {
        switch group {
        case .wallet:
            return (baseHex, "#F9F4FF", "#FFD36E", [baseHex, "#1E2435"])
        case .food:
            return (baseHex, "#FFF6E7", "#8DD45B", [baseHex, "#7A3B2D"])
        case .home:
            return (baseHex, "#EDF6FF", "#FFD36E", [baseHex, "#283A78"])
        case .family:
            return (baseHex, "#FFF0F5", "#FFD36E", [baseHex, "#7A305B"])
        case .mobility:
            return (baseHex, "#EAFBFF", "#FFD36E", [baseHex, "#224C63"])
        case .personal:
            return (baseHex, "#F6EDFF", "#FFD36E", [baseHex, "#533074"])
        case .health:
            return (baseHex, "#FFF0F3", "#9FE7C7", [baseHex, "#713449"])
        case .leisure:
            return (baseHex, "#FFF7ED", "#7FE3FF", [baseHex, "#74462B"])
        case .work:
            return (baseHex, "#EEF5FF", "#FFD36E", [baseHex, "#2A4578"])
        case .finance:
            return (baseHex, "#EEF2FF", "#9FE7C7", [baseHex, "#30395F"])
        case .income:
            return (baseHex, "#EEFFF7", "#FFD36E", [baseHex, "#215A4A"])
        case .planning:
            return (baseHex, "#EEF7FF", "#FFD36E", [baseHex, "#36476A"])
        case .generic:
            return (baseHex, "#F5F5F7", "#D7DEE8", [baseHex, "#525866"])
        }
    }
}

struct MistiaFinanceIconView: View {
    let icon: String
    var fallbackColor: Color = Color(hex: "#8A8A8E")
    var size: CGFloat = 34

    var body: some View {
        if let descriptor = MistiaFinanceIconRegistry.descriptor(for: icon) {
            financeTile(descriptor: descriptor)
        } else {
            legacyTile
        }
    }

    @ViewBuilder
    private func financeTile(descriptor: MistiaFinanceIconDescriptor) -> some View {
        if let assetName = descriptor.assetName {
            if MistiaFinanceIconRegistry.assetUsesTemplate(assetName) {
                Image(assetName)
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: size * 0.86, height: size * 0.86)
                    .foregroundStyle(Color(hex: descriptor.primaryHex))
                    .frame(width: size, height: size)
            } else {
                Image(assetName)
                    .resizable()
                    .renderingMode(.original)
                    .scaledToFit()
                    .frame(width: size * 0.86, height: size * 0.86)
                    .frame(width: size, height: size)
            }
        } else {
            let cornerRadius = size * 0.32
            let primary = Color(hex: descriptor.primaryHex)

            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(primary.opacity(0.14))

                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(primary.opacity(0.16), lineWidth: 0.8)

                Image(systemName: descriptor.fallbackSystemName)
                    .foregroundStyle(primary)
                    .font(.system(size: size * 0.42, weight: .bold))
            }
            .frame(width: size, height: size)
        }
    }

    private var legacyTile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                .fill(fallbackColor.opacity(0.14))

            Image(systemName: icon)
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundStyle(fallbackColor)
        }
        .frame(width: size, height: size)
    }
}

struct MistiaFinanceIconPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let options: [MistiaFinancePickerOption]
    let selectedToken: String
    let onSave: (String, String) -> Void

    @State private var draftToken: String

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    init(
        title: String,
        options: [MistiaFinancePickerOption],
        selectedToken: String,
        onSave: @escaping (String, String) -> Void
    ) {
        self.title = title
        self.options = options
        self.selectedToken = selectedToken
        self.onSave = onSave
        _draftToken = State(initialValue: selectedToken)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(groupedOptions, id: \.0.id) { group, groupOptions in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(group.title)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)

                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(groupOptions) { option in
                                    Button {
                                        draftToken = option.token
                                    } label: {
                                        VStack(spacing: 8) {
                                            MistiaFinanceIconView(
                                                icon: option.token,
                                                fallbackColor: Color(hex: option.defaultColorHex),
                                                size: 48
                                            )

                                            Text(option.title)
                                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                                .foregroundStyle(.primary)
                                                .multilineTextAlignment(.center)
                                                .lineLimit(2)
                                                .frame(maxWidth: .infinity)
                                        }
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 10)
                                        .frame(maxWidth: .infinity, minHeight: 102)
                                        .background(
                                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                                .fill(draftToken == option.token ? Color.primary.opacity(0.08) : Color.primary.opacity(0.03))
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                                .strokeBorder(draftToken == option.token ? Color.accentColor.opacity(0.65) : Color.clear, lineWidth: 1.2)
                                        )
                                    }
                                    .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 20))
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 18)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.core.ui.mistiafinanceicons.close) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.core.ui.mistiafinanceicons.save) {
                        onSave(draftToken, MistiaFinanceIconRegistry.defaultColorHex(for: draftToken))
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private var groupedOptions: [(MistiaFinanceIconGroup, [MistiaFinancePickerOption])] {
        let grouped = Dictionary(grouping: options) { $0.group }
        return MistiaFinanceIconGroup.allCases.compactMap { group in
            guard let items = grouped[group], !items.isEmpty else { return nil }
            return (group, items)
        }
    }
}
