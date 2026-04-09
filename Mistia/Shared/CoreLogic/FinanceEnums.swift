import Foundation

nonisolated enum LedgerWalletKind: String, CaseIterable, Identifiable, Codable {
    case cash
    case payPay
    case bank
    case creditCard

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
        }
    }

    var defaultIconSymbolName: String {
        switch self {
        case .cash:
            "banknote.fill"
        case .payPay:
            "wallet.pass.fill"
        case .bank:
            "building.columns.fill"
        case .creditCard:
            "creditcard.fill"
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
            "#8A8A8E"
        }
    }

    var legacyDefaultColorHexes: [String] {
        switch self {
        case .creditCard:
            ["#7C85A3"]
        default:
            []
        }
    }

    func matchesDefaultIconAppearance(symbolName: String, colorHex: String) -> Bool {
        guard symbolName == defaultIconSymbolName else { return false }
        let normalizedColorHex = MistiaIconColorPalette.normalizedHex(colorHex)
        return normalizedColorHex == defaultColorHex || legacyDefaultColorHexes.contains(normalizedColorHex)
    }

    func migratedLegacyDefaultColorHex(for colorHex: String, symbolName: String) -> String? {
        guard symbolName == defaultIconSymbolName else { return nil }
        let normalizedColorHex = MistiaIconColorPalette.normalizedHex(colorHex)
        guard legacyDefaultColorHexes.contains(normalizedColorHex) else { return nil }
        return MistiaIconColorPalette.presetHex(forDefault: normalizedColorHex)
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
            "fork.knife"
        case .income:
            "briefcase.fill"
        }
    }

    var defaultColorHex: String {
        switch self {
        case .expense:
            "#FF9F1C"
        case .income:
            "#2DAA9E"
        }
    }

    var legacyDefaultColorHexes: [String] {
        switch self {
        case .expense:
            ["#F59B3F"]
        case .income:
            []
        }
    }

    func matchesDefaultIconAppearance(symbolName: String, colorHex: String) -> Bool {
        guard symbolName == defaultIconSymbolName else { return false }
        let normalizedColorHex = MistiaIconColorPalette.normalizedHex(colorHex)
        return normalizedColorHex == defaultColorHex || legacyDefaultColorHexes.contains(normalizedColorHex)
    }

    func migratedLegacyDefaultColorHex(for colorHex: String, symbolName: String) -> String? {
        guard symbolName == defaultIconSymbolName else { return nil }
        let normalizedColorHex = MistiaIconColorPalette.normalizedHex(colorHex)
        guard legacyDefaultColorHexes.contains(normalizedColorHex) else { return nil }
        return MistiaIconColorPalette.presetHex(forDefault: normalizedColorHex)
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

nonisolated enum MistiaSystemCategoryKey: String, CaseIterable, Codable, Identifiable {
    case food
    case entertainment
    case travel
    case shopping
    case transportation
    case housing
    case billing
    case health
    case education
    case loanRepayment = "loan_repayment"
    case salary
    case bonus
    case freelance
    case investment
    case refund
    case sales
    case gift
    case allowance
    case bankInterest = "bank_interest"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .food:
            mistiaLocalized(vi: "Ăn uống", en: "Food & drinks", ja: "食費")
        case .entertainment:
            mistiaLocalized(vi: "Đi chơi", en: "Entertainment", ja: "娯楽")
        case .travel:
            mistiaLocalized(vi: "Du lịch", en: "Travel", ja: "旅行")
        case .shopping:
            mistiaLocalized(vi: "Mua sắm", en: "Shopping", ja: "買い物")
        case .transportation:
            mistiaLocalized(vi: "Di chuyển", en: "Transport", ja: "交通")
        case .housing:
            mistiaLocalized(vi: "Nhà ở", en: "Housing", ja: "住居")
        case .billing:
            mistiaLocalized(vi: "Hóa đơn", en: "Bills", ja: "請求書")
        case .health:
            mistiaLocalized(vi: "Sức khỏe", en: "Health", ja: "健康")
        case .education:
            mistiaLocalized(vi: "Giáo dục", en: "Education", ja: "教育")
        case .loanRepayment:
            mistiaLocalized(vi: "Trả góp / vay", en: "Installments / loans", ja: "分割払い・借入")
        case .salary:
            mistiaLocalized(vi: "Lương", en: "Salary", ja: "給与")
        case .bonus:
            mistiaLocalized(vi: "Thưởng", en: "Bonus", ja: "ボーナス")
        case .freelance:
            mistiaLocalized(vi: "Freelance", en: "Freelance", ja: "フリーランス")
        case .investment:
            mistiaLocalized(vi: "Đầu tư", en: "Investment", ja: "投資")
        case .refund:
            mistiaLocalized(vi: "Hoàn tiền", en: "Refund", ja: "返金")
        case .sales:
            mistiaLocalized(vi: "Bán hàng", en: "Sales", ja: "売上")
        case .gift:
            mistiaLocalized(vi: "Quà tặng", en: "Gift", ja: "ギフト")
        case .allowance:
            mistiaLocalized(vi: "Phụ cấp", en: "Allowance", ja: "手当")
        case .bankInterest:
            mistiaLocalized(vi: "Lãi ngân hàng", en: "Bank interest", ja: "銀行利息")
        }
    }

    var legacyVietnameseName: String {
        switch self {
        case .food:
            "Ăn uống"
        case .entertainment:
            "Đi chơi"
        case .travel:
            "Du lịch"
        case .shopping:
            "Mua sắm"
        case .transportation:
            "Di chuyển"
        case .housing:
            "Nhà ở"
        case .billing:
            "Hóa đơn"
        case .health:
            "Sức khỏe"
        case .education:
            "Giáo dục"
        case .loanRepayment:
            "Trả góp / vay"
        case .salary:
            "Lương"
        case .bonus:
            "Thưởng"
        case .freelance:
            "Freelance"
        case .investment:
            "Đầu tư"
        case .refund:
            "Hoàn tiền"
        case .sales:
            "Bán hàng"
        case .gift:
            "Quà tặng"
        case .allowance:
            "Phụ cấp"
        case .bankInterest:
            "Lãi ngân hàng"
        }
    }

    func knownDefaultNames() -> [String] {
        [
            legacyVietnameseName,
            title,
            localizedTitle(for: .english),
            localizedTitle(for: .japanese)
        ]
    }

    func localizedTitle(for language: MistiaAppLanguage) -> String {
        switch language {
        case .vietnamese:
            mistiaLocalized(vi: legacyVietnameseName, en: "", ja: "", language: language)
        case .english, .japanese:
            switch self {
            case .food:
                mistiaLocalized(vi: legacyVietnameseName, en: "Food & drinks", ja: "食費", language: language)
            case .entertainment:
                mistiaLocalized(vi: legacyVietnameseName, en: "Entertainment", ja: "娯楽", language: language)
            case .travel:
                mistiaLocalized(vi: legacyVietnameseName, en: "Travel", ja: "旅行", language: language)
            case .shopping:
                mistiaLocalized(vi: legacyVietnameseName, en: "Shopping", ja: "買い物", language: language)
            case .transportation:
                mistiaLocalized(vi: legacyVietnameseName, en: "Transport", ja: "交通", language: language)
            case .housing:
                mistiaLocalized(vi: legacyVietnameseName, en: "Housing", ja: "住居", language: language)
            case .billing:
                mistiaLocalized(vi: legacyVietnameseName, en: "Bills", ja: "請求書", language: language)
            case .health:
                mistiaLocalized(vi: legacyVietnameseName, en: "Health", ja: "健康", language: language)
            case .education:
                mistiaLocalized(vi: legacyVietnameseName, en: "Education", ja: "教育", language: language)
            case .loanRepayment:
                mistiaLocalized(vi: legacyVietnameseName, en: "Installments / loans", ja: "分割払い・借入", language: language)
            case .salary:
                mistiaLocalized(vi: legacyVietnameseName, en: "Salary", ja: "給与", language: language)
            case .bonus:
                mistiaLocalized(vi: legacyVietnameseName, en: "Bonus", ja: "ボーナス", language: language)
            case .freelance:
                mistiaLocalized(vi: legacyVietnameseName, en: "Freelance", ja: "フリーランス", language: language)
            case .investment:
                mistiaLocalized(vi: legacyVietnameseName, en: "Investment", ja: "投資", language: language)
            case .refund:
                mistiaLocalized(vi: legacyVietnameseName, en: "Refund", ja: "返金", language: language)
            case .sales:
                mistiaLocalized(vi: legacyVietnameseName, en: "Sales", ja: "売上", language: language)
            case .gift:
                mistiaLocalized(vi: legacyVietnameseName, en: "Gift", ja: "ギフト", language: language)
            case .allowance:
                mistiaLocalized(vi: legacyVietnameseName, en: "Allowance", ja: "手当", language: language)
            case .bankInterest:
                mistiaLocalized(vi: legacyVietnameseName, en: "Bank interest", ja: "銀行利息", language: language)
            }
        }
    }
}

nonisolated enum MistiaSystemCategoryParentKey: String, CaseIterable, Codable, Identifiable {
    case livingExpense = "parent_expense_living"
    case mobilityTravel = "parent_expense_mobility_travel"
    case personalLifestyle = "parent_expense_personal_lifestyle"
    case financialObligations = "parent_expense_financial_obligations"
    case uncategorizedExpense = "parent_expense_uncategorized"
    case workIncome = "parent_income_work"
    case investmentReturn = "parent_income_investment_return"
    case salesOther = "parent_income_sales_other"
    case uncategorizedIncome = "parent_income_uncategorized"

    var id: String { rawValue }

    var kind: TransactionCategoryKind {
        switch self {
        case .livingExpense, .mobilityTravel, .personalLifestyle, .financialObligations, .uncategorizedExpense:
            .expense
        case .workIncome, .investmentReturn, .salesOther, .uncategorizedIncome:
            .income
        }
    }

    var title: String {
        switch self {
        case .livingExpense:
            mistiaLocalized(vi: "Sinh hoạt", en: "Living", ja: "生活")
        case .mobilityTravel:
            mistiaLocalized(vi: "Di chuyển & chuyến đi", en: "Mobility & travel", ja: "移動・旅行")
        case .personalLifestyle:
            mistiaLocalized(vi: "Cá nhân & phong cách sống", en: "Personal & lifestyle", ja: "個人・ライフスタイル")
        case .financialObligations:
            mistiaLocalized(vi: "Nghĩa vụ tài chính", en: "Financial obligations", ja: "支払い・債務")
        case .uncategorizedExpense:
            mistiaLocalized(vi: "Chưa phân loại chi", en: "Uncategorized expense", ja: "未分類の支出")
        case .workIncome:
            mistiaLocalized(vi: "Thu nhập công việc", en: "Work income", ja: "仕事の収入")
        case .investmentReturn:
            mistiaLocalized(vi: "Đầu tư & hoàn lại", en: "Investment & returns", ja: "投資・還元")
        case .salesOther:
            mistiaLocalized(vi: "Bán hàng & khác", en: "Sales & other", ja: "売上・その他")
        case .uncategorizedIncome:
            mistiaLocalized(vi: "Chưa phân loại thu", en: "Uncategorized income", ja: "未分類の収入")
        }
    }

    var legacyVietnameseName: String {
        switch self {
        case .livingExpense:
            "Sinh hoạt"
        case .mobilityTravel:
            "Di chuyển & chuyến đi"
        case .personalLifestyle:
            "Cá nhân & phong cách sống"
        case .financialObligations:
            "Nghĩa vụ tài chính"
        case .uncategorizedExpense:
            "Chưa phân loại chi"
        case .workIncome:
            "Thu nhập công việc"
        case .investmentReturn:
            "Đầu tư & hoàn lại"
        case .salesOther:
            "Bán hàng & khác"
        case .uncategorizedIncome:
            "Chưa phân loại thu"
        }
    }

    func knownDefaultNames() -> [String] {
        [
            legacyVietnameseName,
            title,
            localizedTitle(for: .english),
            localizedTitle(for: .japanese)
        ]
    }

    func localizedTitle(for language: MistiaAppLanguage) -> String {
        switch language {
        case .vietnamese:
            mistiaLocalized(vi: legacyVietnameseName, en: "", ja: "", language: language)
        case .english:
            switch self {
            case .livingExpense:
                "Living"
            case .mobilityTravel:
                "Mobility & travel"
            case .personalLifestyle:
                "Personal & lifestyle"
            case .financialObligations:
                "Financial obligations"
            case .uncategorizedExpense:
                "Uncategorized expense"
            case .workIncome:
                "Work income"
            case .investmentReturn:
                "Investment & returns"
            case .salesOther:
                "Sales & other"
            case .uncategorizedIncome:
                "Uncategorized income"
            }
        case .japanese:
            switch self {
            case .livingExpense:
                "生活"
            case .mobilityTravel:
                "移動・旅行"
            case .personalLifestyle:
                "個人・ライフスタイル"
            case .financialObligations:
                "支払い・債務"
            case .uncategorizedExpense:
                "未分類の支出"
            case .workIncome:
                "仕事の収入"
            case .investmentReturn:
                "投資・還元"
            case .salesOther:
                "売上・その他"
            case .uncategorizedIncome:
                "未分類の収入"
            }
        }
    }

    var iconSymbolName: String {
        switch self {
        case .livingExpense:
            "house.fill"
        case .mobilityTravel:
            "airplane"
        case .personalLifestyle:
            "sparkles"
        case .financialObligations:
            "creditcard.and.123"
        case .uncategorizedExpense:
            "questionmark.circle.fill"
        case .workIncome:
            "briefcase.fill"
        case .investmentReturn:
            "chart.line.uptrend.xyaxis"
        case .salesOther:
            "storefront.fill"
        case .uncategorizedIncome:
            "questionmark.circle.fill"
        }
    }

    var iconColorHex: String {
        switch self {
        case .livingExpense:
            "#FF9F1C"
        case .mobilityTravel:
            "#5B7BFF"
        case .personalLifestyle:
            "#F26A5A"
        case .financialObligations:
            "#8A8A8E"
        case .uncategorizedExpense:
            "#A0A0A0"
        case .workIncome:
            "#2DAA9E"
        case .investmentReturn:
            "#5B7BFF"
        case .salesOther:
            "#F26A5A"
        case .uncategorizedIncome:
            "#A0A0A0"
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
            mistiaLocalized(vi: "Khác", en: "Other", ja: "その他")
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
