import SwiftUI

enum MistiaAccent: String, Codable {
    case mint
    case teal
    case cyan
    case indigo
    case amber
    case coral
    case rose
    case slate
    case sky
    case purple
    case expense // Màu rose đỏ của số tiền chi tiêu
    case income // Màu xanh của số tiền thu nhập
    case transfer // Màu trắng xám của số tiền chuyển tiền
    case debtLend // Màu cho vay
    case debtCollect // Màu thu nợ
    case debtBorrow // Màu nợ phải trả
    case debtRepay // Màu trả nợ
    case lightPurple // Màu tím nhạt cho text thêm hoặc dark mode highlight
    case checkmarkPurple // Màu tím nhạt cho checkmark/button
    case tabActive // Màu active tab sáng dùng cho nút thêm mới

    var color: Color {
        switch self {
        case .mint:
            .mint
        case .teal:
            .teal
        case .cyan:
            .cyan
        case .indigo:
            .indigo
        case .amber:
            Color(red: 0.97, green: 0.66, blue: 0.25)
        case .coral:
            Color(red: 0.98, green: 0.46, blue: 0.41)
        case .rose:
            Color(red: 0.96, green: 0.36, blue: 0.56)
        case .slate:
            Color(red: 0.55, green: 0.58, blue: 0.67)
        case .sky:
            Color(red: 0.39, green: 0.68, blue: 1.0)
        case .purple:
            // Màu tím chính của app (Plus button, sao kê, ghi nhanh...)
            Color(red: 0.43, green: 0.23, blue: 0.76)
        case .expense:
            // Màu rose đỏ cho chi tiêu
            Color(red: 0.97, green: 0.43, blue: 0.46)
        case .income:
            // Màu xanh cho thu nhập
            Color(red: 0.25, green: 0.76, blue: 0.34)
        case .transfer:
            // Màu xám cho chuyển khoản
            Color(red: 0.55, green: 0.58, blue: 0.67)
        case .debtLend:
            Color(red: 0.95, green: 0.56, blue: 0.14)
        case .debtCollect:
            Color(red: 0.0, green: 0.68, blue: 0.50)
        case .debtBorrow:
            Color(red: 0.38, green: 0.58, blue: 1.0)
        case .debtRepay:
            Color(red: 1.0, green: 0.34, blue: 0.52)
        case .lightPurple:
            // Màu tím nhạt cho text thêm hoặc dark mode highlight
            Color(red: 0.65, green: 0.45, blue: 0.98)
        case .checkmarkPurple:
            // Màu tím nhạt cho checkmark/button
            Color(red: 0.88, green: 0.78, blue: 1.0)
        case .tabActive:
            // Màu active tab ở dark mode
            Color(red: 0.90, green: 0.74, blue: 1.00)
        }
    }
}
