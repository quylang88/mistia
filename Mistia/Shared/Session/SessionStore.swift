import Foundation
import Observation
import SwiftData

struct SessionSummary: Equatable {
    let userID: UUID
    let displayName: String
    let email: String
    let avatarURL: URL?

    var initials: String {
        let components = displayName
            .split(separator: " ")
            .prefix(2)
            .map { String($0.prefix(1)).uppercased() }

        if components.isEmpty {
            return "MI"
        }

        return components.joined()
    }
}

enum SessionAuthPhase: Equatable {
    case signIn
    case signUp
    case forgotPassword
    case verifyEmailPending
}

enum SessionAuthField: Hashable {
    case displayName
    case email
    case password
    case confirmPassword
}

enum SessionAuthBannerStyle: Equatable {
    case info
    case success
    case error
}

enum SessionAuthAction: Equatable {
    case credentials
    case google
    case passwordReset
    case resendConfirmation
}

struct SessionAuthBanner: Equatable {
    let title: String
    let message: String
    let style: SessionAuthBannerStyle
}

@MainActor
@Observable
final class SessionStore {
    var summary: SessionSummary?
    var isWorking = false
    var syncStatusTitle: String
    var syncStatusDetail: String
    var syncStatusSystemImage: String
    var lastErrorMessage: String?
    var lastSyncAt: Date?
    var authPhase: SessionAuthPhase = .signIn
    var authBanner: SessionAuthBanner?
    var authPendingEmail: String?
    var authFieldErrors: [SessionAuthField: String] = [:]
    var activeAuthAction: SessionAuthAction?

    @ObservationIgnored private let authService: SupabaseAuthService
    @ObservationIgnored private let syncCoordinator: SyncCoordinator
    @ObservationIgnored private var currentSession: SupabaseAuthSession?
    @ObservationIgnored private var didBootstrap = false
    @ObservationIgnored private var liveSyncTask: Task<Void, Never>?
    @ObservationIgnored private var isSyncInFlight = false
    @ObservationIgnored private var requiresInitialSync = false

    init(modelContainer: ModelContainer) {
        authService = SupabaseAuthService()
        syncCoordinator = SyncCoordinator(modelContainer: modelContainer)

        if MistiaSyncConfiguration.load() == nil {
            syncStatusTitle = mistiaLocalized(
                vi: "Chưa cấu hình dịch vụ đồng bộ",
                en: "Cloud sync isn't configured",
                ja: "クラウド同期が未設定です"
            )
            syncStatusDetail = mistiaLocalized(
                vi: "Điền URL dịch vụ và public key trong MistiaSyncConfig.plist để bật đăng nhập và đồng bộ.",
                en: "Fill in the service URL and public key in MistiaSyncConfig.plist to enable sign-in and sync.",
                ja: "ログインと同期を有効にするには MistiaSyncConfig.plist にサービス URL と公開キーを設定してください。"
            )
            syncStatusSystemImage = "bolt.horizontal.circle"
        } else {
            syncStatusTitle = mistiaLocalized(
                vi: "Chưa đăng nhập",
                en: "Signed out",
                ja: "未ログイン"
            )
            syncStatusDetail = mistiaLocalized(
                vi: "Đăng nhập để đồng bộ dữ liệu Mistia giữa các thiết bị.",
                en: "Sign in to sync Mistia data across devices.",
                ja: "ログインすると Mistia のデータを端末間で同期できます。"
            )
            syncStatusSystemImage = "person.crop.circle.badge.plus"
        }
    }

    var isConfigured: Bool {
        MistiaSyncConfiguration.load() != nil
    }

    var isSignedIn: Bool {
        summary != nil
    }

    var canManageSync: Bool {
        currentSession != nil && isConfigured
    }

    func showAuthPhase(_ phase: SessionAuthPhase) {
        authPhase = phase
        authBanner = nil
        authFieldErrors = [:]
        activeAuthAction = nil
        if phase != .verifyEmailPending {
            authPendingEmail = nil
        }
    }

    func setAuthFieldErrors(_ errors: [SessionAuthField: String]) {
        authFieldErrors = errors
    }

    func clearAuthFieldError(_ field: SessionAuthField) {
        authFieldErrors.removeValue(forKey: field)
    }

    func clearAuthBanner() {
        authBanner = nil
    }

    func bootstrapIfNeeded() async {
        guard !didBootstrap else { return }
        didBootstrap = true

        guard isConfigured else {
            applyConfigurationMissingState()
            return
        }

        // Nếu đã có session do thao tác đăng nhập thủ công chạy trước, bỏ qua bootstrap
        guard summary == nil else { return }

        syncStatusTitle = mistiaLocalized(
            vi: "Đang khôi phục phiên",
            en: "Restoring session",
            ja: "セッションを復元中"
        )
        syncStatusDetail = mistiaLocalized(
            vi: "Mistia đang kiểm tra tài khoản đã đăng nhập trước đó.",
            en: "Mistia is checking for a previously signed-in account.",
            ja: "以前のログイン状態を確認しています。"
        )
        syncStatusSystemImage = "key.horizontal"

        do {
            guard let restoredSession = try await authService.restoreSession() else {
                if summary == nil {
                    applySignedOutState()
                }
                return
            }

            if summary == nil {
                try await finishAuthentication(
                    restoredSession,
                    restoringExistingSession: true
                )
            }
        } catch {
            lastErrorMessage = friendlyErrorMessage(for: error)
            if summary == nil {
                applySignedOutState(preservingBanner: true)
                authBanner = SessionAuthBanner(
                    title: mistiaLocalized(
                        vi: "Chưa thể khôi phục tài khoản",
                        en: "Couldn't restore account",
                        ja: "アカウントを復元できませんでした"
                    ),
                    message: friendlyErrorMessage(for: error),
                    style: .error
                )
            }
        }
    }

    func signIn(email: String, password: String) async {
        guard isConfigured else {
            applyConfigurationMissingState()
            return
        }

        isWorking = true
        lastErrorMessage = nil
        authBanner = nil
        activeAuthAction = .credentials

        do {
            let session = try await authService.signIn(email: email, password: password)
            try await finishAuthentication(session, restoringExistingSession: false)
        } catch {
            handleSignInFailure(error, email: email)
        }

        activeAuthAction = nil
        isWorking = false
    }

    func signUp(email: String, password: String, displayName: String) async {
        guard isConfigured else {
            applyConfigurationMissingState()
            return
        }

        isWorking = true
        lastErrorMessage = nil
        authBanner = nil
        activeAuthAction = .credentials

        do {
            let result = try await authService.signUp(
                email: email,
                password: password,
                displayName: displayName
            )
            switch result {
            case .signedIn(let session):
                try await finishAuthentication(session, restoringExistingSession: false)
            case .emailConfirmationRequired:
                presentEmailConfirmationState(for: email)
            }
        } catch {
            handleSignUpFailure(error)
        }

        activeAuthAction = nil
        isWorking = false
    }

    func signInWithGoogle() async {
        guard isConfigured else {
            applyConfigurationMissingState()
            return
        }

        isWorking = true
        lastErrorMessage = nil
        authBanner = nil
        activeAuthAction = .google

        do {
            let session = try await authService.signInWithGoogle()
            try await finishAuthentication(session, restoringExistingSession: false)
        } catch {
            handleGoogleSignInFailure(error)
        }

        activeAuthAction = nil
        isWorking = false
    }

    func requestPasswordReset(email: String) async {
        guard isConfigured else {
            applyConfigurationMissingState()
            return
        }

        isWorking = true
        authBanner = nil
        activeAuthAction = .passwordReset

        do {
            try await authService.requestPasswordReset(email: email)
            authBanner = SessionAuthBanner(
                title: mistiaLocalized(
                    vi: "Kiểm tra email của bạn",
                    en: "Check your email",
                    ja: "メールを確認してください"
                ),
                message: mistiaLocalized(
                    vi: "Nếu email hợp lệ, Mistia sẽ gửi một email đặt lại mật khẩu trong giây lát.",
                    en: "If the email is valid, Mistia will send a password reset email shortly.",
                    ja: "有効なメールアドレスであれば、まもなくパスワード再設定メールが送信されます。"
                ),
                style: .success
            )
        } catch {
            handleRecoveryFailure(error, isResend: false)
        }

        activeAuthAction = nil
        isWorking = false
    }

    func resendConfirmation(email: String) async {
        guard isConfigured else {
            applyConfigurationMissingState()
            return
        }

        isWorking = true
        authBanner = nil
        activeAuthAction = .resendConfirmation

        do {
            try await authService.resendConfirmation(email: email)
            authBanner = SessionAuthBanner(
                title: mistiaLocalized(
                    vi: "Đã gửi lại email xác nhận",
                    en: "Confirmation email sent again",
                    ja: "確認メールを再送しました"
                ),
                message: mistiaLocalized(
                    vi: "Nếu email đang chờ xác nhận, hệ thống sẽ gửi lại email mới đến hộp thư của bạn.",
                    en: "If this account is pending confirmation, the system will send a fresh email to your inbox.",
                    ja: "このアカウントが確認待ちの場合、システムが新しい確認メールを再送します。"
                ),
                style: .info
            )
        } catch {
            handleRecoveryFailure(error, isResend: true)
        }

        activeAuthAction = nil
        isWorking = false
    }

    func signOut() async {
        stopLiveSyncLoop()
        isWorking = true
        let activeSession = currentSession

        currentSession = nil
        summary = nil
        lastSyncAt = nil
        lastErrorMessage = nil
        syncCoordinator.clearQueuedMutations()

        do {
            try await authService.signOut(session: activeSession)
        } catch {
            lastErrorMessage = friendlyErrorMessage(for: error)
        }

        isWorking = false
        applySignedOutState()
    }

    func syncNow() async {
        guard currentSession != nil, !isSyncInFlight else { return }
        await drainSyncQueue()
    }

    func recordUpsert(
        entity: MistiaSyncEntity,
        recordID: UUID,
        modifiedAt: Date
    ) {
        guard currentSession != nil else { return }

        syncCoordinator.queue(
            MistiaSyncMutation(
                entity: entity,
                recordID: recordID,
                kind: .upsert,
                modifiedAt: modifiedAt
            )
        )
    }

    func recordDelete(
        entity: MistiaSyncEntity,
        recordID: UUID,
        modifiedAt: Date
    ) {
        guard currentSession != nil else { return }

        syncCoordinator.queue(
            MistiaSyncMutation(
                entity: entity,
                recordID: recordID,
                kind: .delete,
                modifiedAt: modifiedAt
            )
        )
    }

    func recordMutations(_ mutations: [MistiaSyncMutation]) {
        guard currentSession != nil else { return }

        syncCoordinator.queue(mutations)
    }

    private func handleSignInFailure(_ error: Error, email: String) {
        if isEmailConfirmationError(error) {
            presentEmailConfirmationState(for: email)
            return
        }

        authPhase = .signIn

        if isInfrastructureAuthError(error) {
            authBanner = SessionAuthBanner(
                title: mistiaLocalized(
                    vi: "Chưa thể kết nối",
                    en: "Can't connect right now",
                    ja: "現在接続できません"
                ),
                message: infrastructureErrorMessage(for: error),
                style: .error
            )
            return
        }

        authBanner = SessionAuthBanner(
            title: mistiaLocalized(
                vi: "Đăng nhập chưa thành công",
                en: "Couldn't sign in",
                ja: "ログインできませんでした"
            ),
            message: mistiaLocalized(
                vi: "Email hoặc mật khẩu chưa đúng. Kiểm tra lại rồi thử thêm lần nữa.",
                en: "The email or password is incorrect. Check them and try again.",
                ja: "メールアドレスまたはパスワードが正しくありません。確認してもう一度お試しください。"
            ),
            style: .error
        )
    }

    private func handleSignUpFailure(_ error: Error) {
        authPhase = .signUp

        if isInfrastructureAuthError(error) {
            authBanner = SessionAuthBanner(
                title: mistiaLocalized(
                    vi: "Chưa thể tạo tài khoản",
                    en: "Can't create the account right now",
                    ja: "現在アカウントを作成できません"
                ),
                message: infrastructureErrorMessage(for: error),
                style: .error
            )
            return
        }

        if isRateLimitedError(error) {
            authBanner = SessionAuthBanner(
                title: mistiaLocalized(
                    vi: "Bạn thao tác hơi nhanh",
                    en: "You're moving a bit fast",
                    ja: "少し操作が速すぎます"
                ),
                message: mistiaLocalized(
                    vi: "Hệ thống tạm chậm lại để bảo vệ tài khoản. Chờ một chút rồi thử lại nhé.",
                    en: "The service temporarily slowed things down to protect the account flow. Please wait a moment and try again.",
                    ja: "サービス保護のため一時的に制限されています。少し待ってからもう一度お試しください。"
                ),
                style: .error
            )
            return
        }

        authBanner = SessionAuthBanner(
            title: mistiaLocalized(
                vi: "Tạo tài khoản chưa thành công",
                en: "Couldn't create the account",
                ja: "アカウントを作成できませんでした"
            ),
            message: mistiaLocalized(
                vi: "Email này chưa sẵn sàng để tạo tài khoản mới. Thử đăng nhập hoặc dùng quên mật khẩu nhé.",
                en: "This email isn't ready for a new account right now. Try signing in or use password recovery instead.",
                ja: "このメールアドレスでは現在新しいアカウントを作成できません。ログインするか、パスワード再設定をお試しください。"
            ),
            style: .error
        )
    }

    private func handleGoogleSignInFailure(_ error: Error) {
        authPhase = .signIn

        if let serviceError = error as? SupabaseServiceError, case .oauthCancelled = serviceError {
            authBanner = SessionAuthBanner(
                title: mistiaLocalized(
                    vi: "Đã hủy đăng nhập Google",
                    en: "Google sign-in was cancelled",
                    ja: "Google ログインはキャンセルされました"
                ),
                message: mistiaLocalized(
                    vi: "Bạn có thể thử lại bất cứ lúc nào khi sẵn sàng.",
                    en: "You can try again any time when you're ready.",
                    ja: "準備ができたらいつでも再試行できます。"
                ),
                style: .info
            )
            return
        }

        if isGoogleSignInSetupError(error) {
            authBanner = SessionAuthBanner(
                title: mistiaLocalized(
                    vi: "Google Sign-In chưa sẵn sàng",
                    en: "Google sign-in isn't ready yet",
                    ja: "Google ログインの設定がまだ完了していません"
                ),
                message: googleSetupErrorMessage(for: error),
                style: .error
            )
            return
        }

        if isInfrastructureAuthError(error) {
            authBanner = SessionAuthBanner(
                title: mistiaLocalized(
                    vi: "Google chưa thể kết nối",
                    en: "Google sign-in can't connect right now",
                    ja: "現在 Google ログインに接続できません"
                ),
                message: infrastructureErrorMessage(for: error),
                style: .error
            )
            return
        }

        authBanner = SessionAuthBanner(
            title: mistiaLocalized(
                vi: "Google đăng nhập chưa thành công",
                en: "Google sign-in couldn't finish",
                ja: "Google ログインを完了できませんでした"
            ),
            message: friendlyErrorMessage(for: error),
            style: .error
        )
    }

    private func handleRecoveryFailure(_ error: Error, isResend: Bool) {
        if isInfrastructureAuthError(error) {
            authBanner = SessionAuthBanner(
                title: mistiaLocalized(
                    vi: isResend ? "Chưa thể gửi lại email" : "Chưa thể gửi email",
                    en: isResend ? "Can't resend the email yet" : "Can't send the email yet",
                    ja: isResend ? "メールを再送できません" : "メールを送信できません"
                ),
                message: infrastructureErrorMessage(for: error),
                style: .error
            )
            return
        }

        if isRateLimitedError(error) {
            authBanner = SessionAuthBanner(
                title: mistiaLocalized(
                    vi: "Bạn vừa yêu cầu gần đây",
                    en: "A request was just sent",
                    ja: "直前にリクエストされました"
                ),
                message: mistiaLocalized(
                    vi: "Chờ một chút rồi thử lại để tránh gửi email quá dày.",
                    en: "Please wait a bit before trying again to avoid sending too many emails.",
                    ja: "メール送信が多すぎないよう、少し待ってからもう一度お試しください。"
                ),
                style: .info
            )
            return
        }

        authBanner = SessionAuthBanner(
            title: mistiaLocalized(
                vi: isResend ? "Email đang được xử lý" : "Yêu cầu đang được xử lý",
                en: isResend ? "The email request is being processed" : "The request is being processed",
                ja: isResend ? "メール再送を処理中です" : "リクエストを処理中です"
            ),
                message: mistiaLocalized(
                    vi: isResend
                    ? "Nếu tài khoản đang chờ xác nhận, hệ thống sẽ tiếp tục gửi email xác nhận đến đúng hộp thư."
                    : "Nếu email hợp lệ, hệ thống sẽ tiếp tục gửi email đặt lại mật khẩu đến đúng hộp thư.",
                en: isResend
                    ? "If the account is pending confirmation, the system will still deliver the confirmation email to the right inbox."
                    : "If the email is valid, the system will still deliver the reset email to the right inbox.",
                ja: isResend
                    ? "アカウントが確認待ちであれば、システムが正しい受信箱へ確認メールを送信します。"
                    : "有効なメールアドレスであれば、システムが正しい受信箱へ再設定メールを送信します。"
            ),
            style: .info
        )
    }

    private func presentEmailConfirmationState(for email: String) {
        authPhase = .verifyEmailPending
        authPendingEmail = email
        authBanner = SessionAuthBanner(
            title: mistiaLocalized(
                vi: "Kiểm tra email để xác nhận",
                en: "Check your email to confirm",
                ja: "確認メールをチェックしてください"
            ),
            message: mistiaLocalized(
                vi: "Tài khoản của bạn đã được tạo. Mở email xác nhận rồi quay lại đăng nhập trong Mistia nhé.",
                en: "Your account has been created. Open the confirmation email, then come back and sign in to Mistia.",
                ja: "アカウントが作成されました。確認メールを開いてから Mistia にログインしてください。"
            ),
            style: .info
        )
    }

    private func finishAuthentication(
        _ session: SupabaseAuthSession,
        restoringExistingSession: Bool
    ) async throws {
        do {
            let validSession = try await authService.refreshSessionIfNeeded(session)

            currentSession = validSession
            summary = SessionSummary(user: validSession.user)
            lastErrorMessage = nil
            authBanner = nil
            authFieldErrors = [:]
            authPendingEmail = nil
            authPhase = .signIn
            activeAuthAction = nil
            requiresInitialSync = true

            syncStatusTitle = mistiaLocalized(
                vi: "Đã đăng nhập",
                en: "Signed in",
                ja: "ログイン済み"
            )
            syncStatusDetail = mistiaLocalized(
                vi: restoringExistingSession
                    ? "Phiên đã được khôi phục. Nhấn Sync ngay khi bạn muốn đồng bộ với cloud."
                    : "Đăng nhập thành công. Nhấn Sync ngay để bắt đầu đồng bộ dữ liệu.",
                en: restoringExistingSession
                    ? "Your session has been restored. Tap Sync now when you want to sync with the cloud."
                    : "Sign-in succeeded. Tap Sync now to start syncing your data.",
                ja: restoringExistingSession
                    ? "セッションを復元しました。クラウドと同期するには「今すぐ同期」を押してください。"
                    : "ログインに成功しました。データ同期を始めるには「今すぐ同期」を押してください。"
            )
            syncStatusSystemImage = "checkmark.circle"
        } catch {
            requiresInitialSync = false
            lastErrorMessage = friendlyErrorMessage(for: error)
            summary = nil
            currentSession = nil
            applySignedOutState(preservingBanner: true)

            authBanner = SessionAuthBanner(
                title: mistiaLocalized(
                    vi: "Không thể hoàn tất đăng nhập",
                    en: "Couldn't finish sign-in",
                    ja: "ログインを完了できませんでした"
                ),
                message: friendlyErrorMessage(for: error),
                style: .error
            )

            throw error
        }
    }

    private func applyConfigurationMissingState() {
        summary = nil
        currentSession = nil
        requiresInitialSync = false
        authPhase = .signIn
        authBanner = nil
        authPendingEmail = nil
        authFieldErrors = [:]
        activeAuthAction = nil
        syncStatusTitle = mistiaLocalized(
            vi: "Chưa cấu hình dịch vụ đồng bộ",
            en: "Cloud sync isn't configured",
            ja: "クラウド同期が未設定です"
        )
        syncStatusDetail = mistiaLocalized(
            vi: "Điền URL dịch vụ và public key trong MistiaSyncConfig.plist rồi build lại app.",
            en: "Fill in the service URL and public key in MistiaSyncConfig.plist, then rebuild the app.",
            ja: "MistiaSyncConfig.plist にサービス URL と公開キーを設定してから再ビルドしてください。"
        )
        syncStatusSystemImage = "wrench.and.screwdriver"
    }

    private func applySignedOutState(preservingBanner: Bool = false) {
        summary = nil
        currentSession = nil
        requiresInitialSync = false
        authPhase = .signIn
        if !preservingBanner {
            authBanner = nil
        }
        authPendingEmail = nil
        authFieldErrors = [:]
        activeAuthAction = nil
        syncStatusTitle = mistiaLocalized(
            vi: "Chưa đăng nhập",
            en: "Signed out",
            ja: "未ログイン"
        )
        syncStatusDetail = mistiaLocalized(
            vi: "Đăng nhập để đồng bộ ví, danh mục, giao dịch và kế hoạch giữa các thiết bị.",
            en: "Sign in to sync wallets, categories, transactions, and planning data across devices.",
            ja: "ログインするとウォレット、カテゴリ、取引、計画データを端末間で同期できます。"
        )
        syncStatusSystemImage = "person.crop.circle.badge.plus"
    }

    private func applySyncingState() {
        syncStatusTitle = mistiaLocalized(
            vi: "Đang đồng bộ",
            en: "Syncing",
            ja: "同期中"
        )
        syncStatusDetail = mistiaLocalized(
            vi: "Mistia đang đẩy thay đổi local và kéo dữ liệu mới từ cloud.",
            en: "Mistia is pushing local changes and pulling the latest cloud data.",
            ja: "ローカル変更を送信し、最新のクラウドデータを取得しています。"
        )
        syncStatusSystemImage = "arrow.triangle.2.circlepath.circle"
    }

    private func applySyncErrorState(_ error: Error) {
        lastErrorMessage = friendlyErrorMessage(for: error)
        syncStatusTitle = syncErrorTitle(for: error)
        syncStatusDetail = friendlyErrorMessage(for: error)
        syncStatusSystemImage = syncErrorSystemImage(for: error)
    }

    private func isInfrastructureAuthError(_ error: Error) -> Bool {
        if error is URLError {
            return true
        }

        guard let serviceError = error as? SupabaseServiceError else {
            return false
        }

        switch serviceError {
        case .configurationMissing, .invalidURL, .invalidResponse, .missingSession, .missingRefreshToken, .googlePresentationContextMissing, .googleTokensMissing:
            return true
        case .serverMessage, .oauthCancelled, .googleClientIDMissing, .googleServerClientIDMissing, .googleCallbackSchemeMissing:
            return false
        }
    }

    private func isEmailConfirmationError(_ error: Error) -> Bool {
        errorMessage(for: error).contains("email not confirmed")
            || errorMessage(for: error).contains("confirm your email")
    }

    private func isRateLimitedError(_ error: Error) -> Bool {
        let message = errorMessage(for: error)
        return message.contains("rate limit") || message.contains("too many requests")
    }

    private func isGoogleSignInSetupError(_ error: Error) -> Bool {
        if let serviceError = error as? SupabaseServiceError {
            switch serviceError {
            case .googleClientIDMissing, .googleServerClientIDMissing, .googleCallbackSchemeMissing:
                return true
            case .configurationMissing, .invalidURL, .invalidResponse, .serverMessage, .missingSession, .missingRefreshToken, .oauthCancelled, .googlePresentationContextMissing, .googleTokensMissing:
                break
            }
        }

        let message = errorMessage(for: error)
        return message.contains("provider is not enabled")
            || message.contains("unsupported provider")
            || message.contains("client id")
            || message.contains("callback")
    }

    private func googleSetupErrorMessage(for error: Error) -> String {
        if let serviceError = error as? SupabaseServiceError {
            switch serviceError {
            case .googleClientIDMissing, .googleServerClientIDMissing:
                return mistiaLocalized(
                    vi: "Điền Google iOS client ID và Google web client ID trong MistiaInfo.plist rồi build lại app.",
                    en: "Fill in the Google iOS client ID and Google web client ID in MistiaInfo.plist, then rebuild the app.",
                    ja: "MistiaInfo.plist に Google iOS client ID と Google web client ID を設定してから再ビルドしてください。"
                )
            case .googleCallbackSchemeMissing(let expected):
                return mistiaLocalized(
                    vi: "Thêm URL scheme Google `\(expected)` vào MistiaInfo.plist rồi build lại app.",
                    en: "Add the Google URL scheme `\(expected)` to MistiaInfo.plist, then rebuild the app.",
                    ja: "Google の URL スキーム `\(expected)` を MistiaInfo.plist に追加してから再ビルドしてください。"
                )
            case .configurationMissing, .invalidURL, .invalidResponse, .serverMessage, .missingSession, .missingRefreshToken, .oauthCancelled, .googlePresentationContextMissing, .googleTokensMissing:
                break
            }
        }

        return mistiaLocalized(
            vi: "Google Sign-In của app này còn thiếu cấu hình iOS cần thiết. Kiểm tra lại client ID và URL scheme rồi thử lại nhé.",
            en: "This build is missing the iOS settings Google Sign-In needs. Check the client IDs and URL scheme, then try again.",
            ja: "このビルドでは Google ログインに必要な iOS 設定が不足しています。client ID と URL スキームを確認してから再試行してください。"
        )
    }

    private func infrastructureErrorMessage(for error: Error) -> String {
        if error is URLError {
            return mistiaLocalized(
                vi: "Mistia chưa thể kết nối đến dịch vụ đồng bộ. Kiểm tra mạng rồi thử lại nhé.",
                en: "Mistia can't reach the sync service right now. Check your connection and try again.",
                ja: "現在 Mistia は同期サービスに接続できません。通信状況を確認してから再度お試しください。"
            )
        }

        if let serviceError = error as? SupabaseServiceError {
            switch serviceError {
            case .configurationMissing:
                return mistiaLocalized(
                    vi: "Dịch vụ đồng bộ chưa được cấu hình đầy đủ trong app này.",
                    en: "The sync service hasn't been configured completely in this build.",
                    ja: "このビルドでは同期サービスの設定がまだ完了していません。"
                )
            case .invalidURL, .invalidResponse, .missingSession, .missingRefreshToken, .oauthCancelled, .serverMessage, .googleClientIDMissing, .googleServerClientIDMissing, .googleCallbackSchemeMissing, .googlePresentationContextMissing, .googleTokensMissing:
                break
            }
        }

        return mistiaLocalized(
            vi: "Hệ thống xác thực đang tạm bận. Thử lại sau ít phút nhé.",
            en: "The authentication service is temporarily busy. Please try again in a moment.",
            ja: "認証サービスが一時的に混み合っています。少し待ってからお試しください。"
        )
    }

    private func friendlyErrorMessage(for error: Error) -> String {
        if let serviceError = error as? SupabaseServiceError {
            switch serviceError {
            case .serverMessage(let message):
                return message
            case .configurationMissing, .invalidURL, .invalidResponse, .missingSession, .missingRefreshToken, .oauthCancelled, .googleClientIDMissing, .googleServerClientIDMissing, .googleCallbackSchemeMissing, .googlePresentationContextMissing, .googleTokensMissing:
                break
            }
        }

        if let decodingError = error as? DecodingError {
            return localizedDecodingErrorMessage(decodingError)
        }

        let message = error.localizedDescription.lowercased()

        if message.contains("404") || message.contains("not found") {
            return mistiaLocalized(
                vi: "Máy chủ chưa sẵn sàng (Lỗi 404). Có thể bạn chưa chạy database migrations trên Supabase.",
                en: "Server not ready (Error 404). You might need to run database migrations on Supabase.",
                ja: "サーバーの準備ができていません (Error 404)。Supabase でデータベースのマイグレーションを実行する必要があるかもしれません。"
            )
        }

        if message.contains("403") || message.contains("forbidden") || message.contains("policy") {
            return mistiaLocalized(
                vi: "Bị từ chối truy cập (Lỗi 403). Kiểm tra lại quyền hạn (RLS) trên database Supabase nhé.",
                en: "Access denied (Error 403). Please check your database Row Level Security (RLS) policies.",
                ja: "アクセスが拒否されました (Error 403)。Supabase のデータベース権限 (RLS) を確認してください。"
            )
        }

        if message.contains("401") || message.contains("unauthorized") || message.contains("jwt") {
            return mistiaLocalized(
                vi: "Phiên đăng nhập hết hạn hoặc không hợp lệ. Thử đăng nhập lại nhé.",
                en: "Session expired or invalid. Please try signing in again.",
                ja: "セッションの期限が切れたか無効です。もう一度ログインをお試しください。"
            )
        }

        if message.contains("400") || message.contains("bad request") {
            return mistiaLocalized(
                vi: "Yêu cầu không hợp lệ (Lỗi 400). Kiểm tra lại cấu hình Client ID và URL Scheme của Google nhé.",
                en: "Bad request (Error 400). Please check your Google Client ID and URL Scheme configuration.",
                ja: "不正なリクエストです (Error 400)。Google の Client ID と URL スキームの設定を確認してください。"
            )
        }

        if message.contains("connection") || message.contains("offline") {
            return mistiaLocalized(
                vi: "Không có kết nối mạng. Kiểm tra wifi hoặc 4G rồi thử lại nhé.",
                en: "No internet connection. Check your Wi-Fi or cellular data and try again.",
                ja: "ネットワーク接続がありません. Wi-Fi またはデータ通信を確認してもう一度お試しください。"
            )
        }

        if message.contains("data couldn") || message.contains("missing") || message.contains("no data") {
            return mistiaLocalized(
                vi: "Không đọc được dữ liệu sync trả về. Khả năng response từ Supabase đang thiếu dữ liệu hoặc sai định dạng.",
                en: "The sync response couldn't be read. Supabase may be returning missing or malformed data.",
                ja: "同期レスポンスを読み取れませんでした。Supabase が不足または不正な形式のデータを返している可能性があります。"
            )
        }

        return error.localizedDescription
    }

    private func localizedDecodingErrorMessage(_ error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, _):
            return mistiaLocalized(
                vi: "Supabase đang trả về dữ liệu thiếu trường `\(key.stringValue)`. Có thể schema cloud chưa khớp với app hiện tại.",
                en: "Supabase is returning data without the `\(key.stringValue)` field. The cloud schema may be out of sync with this app build.",
                ja: "Supabase が `\(key.stringValue)` フィールドのないデータを返しています。クラウドスキーマがこのアプリのビルドと一致していない可能性があります。"
            )
        case .typeMismatch(_, _), .valueNotFound(_, _), .dataCorrupted(_):
            return mistiaLocalized(
                vi: "Dữ liệu đồng bộ từ Supabase không đúng định dạng app đang cần. Kiểm tra lại schema bảng hoặc dữ liệu cũ trên cloud.",
                en: "The sync data from Supabase doesn't match the format this app expects. Check the table schema or older cloud data.",
                ja: "Supabase からの同期データが、このアプリが想定する形式と一致しません。テーブルスキーマまたは既存のクラウドデータを確認してください。"
            )
        @unknown default:
            return mistiaLocalized(
                vi: "Không đọc được dữ liệu đồng bộ từ Supabase. Kiểm tra lại schema và dữ liệu cloud nhé.",
                en: "The sync data from Supabase couldn't be read. Please check the cloud schema and data.",
                ja: "Supabase からの同期データを読み取れませんでした。クラウドのスキーマとデータを確認してください。"
            )
        }
    }

    private func syncErrorTitle(for error: Error) -> String {
        if error is URLError {
            return mistiaLocalized(
                vi: "Đồng bộ đang chờ mạng",
                en: "Sync is waiting for the network",
                ja: "同期はネットワーク待ちです"
            )
        }

        let message = errorMessage(for: error)

        if message.contains("failed to decode remote data") {
            return mistiaLocalized(
                vi: "Dữ liệu cloud hiện có không khớp format app đang cần.",
                en: "The existing cloud data doesn't match the format this app expects.",
                ja: "既存のクラウドデータが、このアプリの想定フォーマットと一致していません。"
            )
        }

        if message.contains("403") || message.contains("forbidden") || message.contains("policy") {
            return mistiaLocalized(
                vi: "Đồng bộ bị từ chối",
                en: "Sync access denied",
                ja: "同期アクセスが拒否されました"
            )
        }

        if message.contains("404") || message.contains("not found") || message.contains("relation") {
            return mistiaLocalized(
                vi: "Thiếu bảng đồng bộ",
                en: "Sync tables missing",
                ja: "同期テーブルが見つかりません"
            )
        }

        if message.contains("401") || message.contains("unauthorized") || message.contains("jwt") {
            return mistiaLocalized(
                vi: "Phiên sync không hợp lệ",
                en: "Sync session invalid",
                ja: "同期セッションが無効です"
            )
        }

        return mistiaLocalized(
            vi: "Đồng bộ cần kiểm tra cấu hình",
            en: "Sync needs configuration checks",
            ja: "同期設定の確認が必要です"
        )
    }

    private func syncErrorSystemImage(for error: Error) -> String {
        if error is URLError {
            return "wifi.exclamationmark"
        }

        let message = errorMessage(for: error)

        if message.contains("403") || message.contains("forbidden") || message.contains("policy") {
            return "lock.slash"
        }

        if message.contains("404") || message.contains("not found") || message.contains("relation") {
            return "externaldrive.badge.exclamationmark"
        }

        if message.contains("401") || message.contains("unauthorized") || message.contains("jwt") {
            return "key.slash"
        }

        return "exclamationmark.icloud"
    }

    private func errorMessage(for error: Error) -> String {
        error.localizedDescription.lowercased()
    }

    private func startLiveSyncLoop() {
        stopLiveSyncLoop()
        liveSyncTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                await self.syncNow()
            }
        }
    }

    private func stopLiveSyncLoop() {
        liveSyncTask?.cancel()
        liveSyncTask = nil
    }

    private func drainSyncQueue() async {
        isSyncInFlight = true
        defer { isSyncInFlight = false }

        do {
            guard let activeSession = currentSession else { return }
            let validSession = try await authService.refreshSessionIfNeeded(activeSession)
            currentSession = validSession
            let result: MistiaSyncResult

            if requiresInitialSync {
                syncStatusTitle = mistiaLocalized(
                    vi: "Đang đồng bộ lần đầu",
                    en: "Running initial sync",
                    ja: "初回同期を実行中"
                )
                syncStatusDetail = mistiaLocalized(
                    vi: "Mistia sẽ lấy dữ liệu local hiện có và đồng bộ với Supabase khi bạn chủ động bắt đầu.",
                    en: "Mistia will take your existing local data and sync it with Supabase when you start it.",
                    ja: "Mistia は現在のローカルデータを使って、開始時に Supabase と同期します。"
                )
                syncStatusSystemImage = "arrow.triangle.2.circlepath"
                result = try await syncCoordinator.performInitialSync(session: validSession)
                requiresInitialSync = false
            } else {
                applySyncingState()
                result = try await syncCoordinator.sync(session: validSession)
            }

            lastSyncAt = .now
            lastErrorMessage = nil
            syncStatusTitle = mistiaLocalized(
                vi: "Đồng bộ đã hoàn tất",
                en: "Sync completed",
                ja: "同期が完了しました"
            )
            syncStatusDetail = result.statusMessage
            syncStatusSystemImage = "checkmark.icloud"
        } catch {
            applySyncErrorState(error)
        }
    }
}

private extension SessionSummary {
    init(user: SupabaseAuthUser) {
        let resolvedEmail = user.email ?? ""
        let resolvedName = user.userMetadata?.displayName
            ?? user.userMetadata?.fullName
            ?? user.userMetadata?.name
            ?? resolvedEmail.components(separatedBy: "@").first
            ?? "Mistia"
        let resolvedAvatarURL = user.userMetadata?.resolvedAvatarURL

        self.init(
            userID: user.id,
            displayName: resolvedName,
            email: resolvedEmail,
            avatarURL: resolvedAvatarURL
        )
    }
}
