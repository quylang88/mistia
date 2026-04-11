import SwiftUI

struct MistiaPrivacySheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    // Hero Icon
                    HStack {
                        Spacer()
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(MistiaAccent.purple.color)
                        Spacer()
                    }
                    .padding(.top, 30)

                    VStack(alignment: .leading, spacing: 16) {
                        Text(mistiaLocalized(
                            vi: "Chia sẻ Gia đình & Quyền riêng tư",
                            en: "Family Sharing & Privacy",
                            ja: "ファミリー共有とプライバシーについて"
                        ))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.leading)

                        Text(mistiaLocalized(
                            vi: "Chia sẻ gia đình được thiết kế để bảo vệ thông tin cá nhân của bạn và cho phép bạn chọn những gì mình muốn chia sẻ.",
                            en: "Family Sharing is designed to protect your information and let you choose what you share.",
                            ja: "ファミリー共有はあなたの個人情報を保護するように設計され、どの情報を共有するかを選択できるようになっています。"
                        ))
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 24) {
                        privacyBulletItem(
                            description: mistiaLocalized(
                                vi: "Độ tuổi và quốc gia hoặc khu vực được liên kết với tài khoản của bạn được sử dụng để xác nhận xem bạn là người lớn, trẻ vị thành niên hay trẻ em.",
                                en: "The age and country or region associated with your account are used to confirm whether you are an adult, a minor, or a child.",
                                ja: "アカウントに関連付けられている年齢および国または地域は、あなたが成人、未成年、または子供であるかどうかを確認するために使用されます。"
                            )
                        )

                        privacyBulletItem(
                            description: mistiaLocalized(
                                vi: "Khi bạn bắt đầu hoặc tham gia một nhóm gia đình, bạn và các thành viên gia đình có thể chia sẻ các đăng ký, giao dịch và thông tin tài chính để cùng nhau quản lý hiệu quả.",
                                en: "When you start or join a family group, you and family members can share subscriptions, transactions, and financial information to manage effectively together.",
                                ja: "ファミリーグループを開始するかファミリーグループに参加すると、あなたとファミリーメンバーがサブスクリプション、取引、財務情報を共有して効果的に管理できるようになります。"
                            )
                        )

                        privacyBulletItem(
                            description: mistiaLocalized(
                                vi: "Mistia sử dụng dữ liệu về tư cách thành viên gia đình của bạn để cải thiện trải nghiệm và đảm bảo tính minh bạch trong quản lý chi tiêu chung.",
                                en: "Mistia uses data about your family membership to improve the experience and ensure transparency in shared spending management.",
                                ja: "Mistiaはファミリーメンバーシップに関するデータを使用して、体験を向上させ、共有支出管理の透明性を確保します。"
                            )
                        )
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 40)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                            .padding(7)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay {
                                Circle()
                                    .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func privacyBulletItem(description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("•")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.secondary)

            Text(description)
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
