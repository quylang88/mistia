import SwiftUI
import SwiftData
import GoogleSignIn

@main
struct MistiaApp: App {
    @AppStorage(MistiaAppStorageKey.appearanceMode) private var appearanceModeRawValue = MistiaAppearanceMode.automatic.rawValue
    @AppStorage(MistiaAppStorageKey.appLanguage) private var appLanguageRawValue = ""
    private let modelContainer: ModelContainer
    private let launchIssue: MistiaDataStack.LaunchIssue?
    @State private var sessionStore: SessionStore

    init() {
        MistiaAppLanguage.bootstrapStoredPreference()
        let launchState = MistiaDataStack.sharedLaunchState
        modelContainer = launchState.modelContainer
        launchIssue = launchState.issue
        _sessionStore = State(initialValue: SessionStore(modelContainer: launchState.modelContainer))
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let launchIssue {
                    MistiaProtectedLaunchView(launchIssue: launchIssue, appLanguage: appLanguage)
                } else {
                    ContentView()
                }
            }
                .preferredColorScheme(appearanceMode.colorScheme)
                .environment(\.locale, appLanguage.locale)
                .environment(\.calendar, appLanguage.calendar)
                .environment(sessionStore)
                .modelContainer(modelContainer)
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }

    private var appearanceMode: MistiaAppearanceMode {
        MistiaAppearanceMode(rawValue: appearanceModeRawValue) ?? .automatic
    }

    private var appLanguage: MistiaAppLanguage {
        MistiaAppLanguage.resolve(storedRawValue: appLanguageRawValue)
    }
}

private struct MistiaProtectedLaunchView: View {
    let launchIssue: MistiaDataStack.LaunchIssue
    let appLanguage: MistiaAppLanguage

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.11, blue: 0.18),
                    Color(red: 0.13, green: 0.16, blue: 0.25)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(mistiaLocalized(
                        vi: "Mistia đang bảo vệ dữ liệu của bạn",
                        en: "Mistia is protecting your data",
                        ja: "Mistia はデータを保護しています",
                        language: appLanguage
                    ))
                    .font(.system(size: 31, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                    Text(mistiaLocalized(
                        vi: "Ứng dụng không thể mở cơ sở dữ liệu cục bộ sau khi cập nhật. Mistia đã chuyển sang chế độ an toàn và không xóa dữ liệu trên máy.",
                        en: "The app couldn't open the local database after the update. Mistia switched to safe mode and did not delete the data on this device.",
                        ja: "アップデート後にローカルデータベースを開けなかったため、Mistia はセーフモードに切り替わり、この端末のデータは削除していません。",
                        language: appLanguage
                    ))
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.86))

                    VStack(alignment: .leading, spacing: 12) {
                        Label(
                            mistiaLocalized(
                                vi: "Dữ liệu local vẫn được giữ nguyên trên máy",
                                en: "Local data has been kept on this device",
                                ja: "ローカルデータはこの端末に保持されています",
                                language: appLanguage
                            ),
                            systemImage: "internaldrive.fill"
                        )

                        Label(
                            mistiaLocalized(
                                vi: "App sẽ không tự tạo DB mới để tránh ghi đè hoặc đồng bộ nhầm",
                                en: "The app will not create a replacement database that could overwrite or sync bad state",
                                ja: "上書きや誤同期を防ぐため、代わりのデータベースは自動作成しません",
                                language: appLanguage
                            ),
                            systemImage: "lock.shield.fill"
                        )
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(mistiaLocalized(
                            vi: "Chi tiết kỹ thuật",
                            en: "Technical details",
                            ja: "技術的な詳細",
                            language: appLanguage
                        ))
                        .font(.headline)
                        .foregroundStyle(.white)

                        Text(launchIssue.underlyingErrorDescription)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.82))
                            .textSelection(.enabled)

                        if let storeURL = launchIssue.storeURL {
                            Text(storeURL.path)
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.68))
                                .textSelection(.enabled)
                        }
                    }
                    .padding(18)
                    .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .padding(24)
                .frame(maxWidth: 720, alignment: .leading)
            }
        }
    }
}
