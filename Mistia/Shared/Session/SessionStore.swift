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
    @ObservationIgnored private var needsAnotherSync = false

    init(modelContainer: ModelContainer) {
        authService = SupabaseAuthService()
        syncCoordinator = SyncCoordinator(modelContainer: modelContainer)

        if MistiaSyncConfiguration.load() == nil {
            syncStatusTitle = mistiaLocalized(
                vi: "Chưa cấu hình Supabase",
                en: "Supabase is not configured",
                ja: "Supabase が未設定です"
            )
            syncStatusDetail = mistiaLocalized(
                vi: "Điền SUPABASE_URL và SUPABASE_ANON_KEY trong MistiaSyncConfig.plist để bật đăng nhập và đồng bộ.",
                en: "Fill SUPABASE_URL and SUPABASE_ANON_KEY in MistiaSyncConfig.plist to enable sign-in and sync.",
                ja: "サインインと同期を有効にするには MistiaSyncConfig.plist に SUPABASE_URL と SUPABASE_ANON_KEY を設定してください。"
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
                applySignedOutState()
                return
            }

            try await finishAuthentication(
                restoredSession,
                restoringExistingSession: true
            )
        } catch {
            lastErrorMessage = error.localizedDescription
            applySignedOutState()
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
                    vi: "Nếu email đang chờ xác nhận, Supabase sẽ gửi lại email mới đến hộp thư của bạn.",
                    en: "If this account is pending confirmation, Supabase will send a fresh email to your inbox.",
                    ja: "このアカウントが確認待ちの場合、Supabase が新しい確認メールを再送します。"
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
            try syncCoordinator.clearLocalCache()
        } catch {
            lastErrorMessage = error.localizedDescription
        }

        do {
            try await authService.signOut(session: activeSession)
        } catch {
            lastErrorMessage = error.localizedDescription
        }

        isWorking = false
        applySignedOutState()
    }

    func syncNow() async {
        guard currentSession != nil else { return }
        needsAnotherSync = true
        guard !isSyncInFlight else { return }
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
        scheduleSync()
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
        scheduleSync()
    }

    func recordMutations(_ mutations: [MistiaSyncMutation]) {
        guard currentSession != nil else { return }

        syncCoordinator.queue(mutations)
        scheduleSync()
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
                    vi: "Supabase vừa chặn tạm thời để bảo vệ hệ thống. Chờ một chút rồi thử lại nhé.",
                    en: "Supabase temporarily slowed things down to protect the service. Please wait a moment and try again.",
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

        if isGoogleOAuthSetupError(error) {
            authBanner = SessionAuthBanner(
                title: mistiaLocalized(
                    vi: "Google Sign-In chưa sẵn sàng",
                    en: "Google sign-in isn't ready yet",
                    ja: "Google ログインの設定がまだ完了していません"
                ),
                message: mistiaLocalized(
                    vi: "Bật Google provider trong Supabase rồi thêm redirect URL của Mistia trước khi thử lại.",
                    en: "Enable the Google provider in Supabase and add Mistia's redirect URL before trying again.",
                    ja: "再試行する前に、Supabase で Google プロバイダを有効にして Mistia のリダイレクト URL を追加してください。"
                ),
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
            message: mistiaLocalized(
                vi: "Flow Google vừa bị ngắt giữa chừng. Thử lại một lần nữa nhé.",
                en: "The Google flow was interrupted before it could finish. Please try again.",
                ja: "Google フローが完了前に中断されました。もう一度お試しください。"
            ),
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
                    ? "Nếu tài khoản đang chờ xác nhận, Supabase sẽ tiếp tục gửi email xác nhận đến đúng hộp thư."
                    : "Nếu email hợp lệ, Supabase sẽ tiếp tục gửi email đặt lại mật khẩu đến đúng hộp thư.",
                en: isResend
                    ? "If the account is pending confirmation, Supabase will still deliver the confirmation email to the right inbox."
                    : "If the email is valid, Supabase will still deliver the reset email to the right inbox.",
                ja: isResend
                    ? "アカウントが確認待ちであれば、Supabase が正しい受信箱へ確認メールを送信します。"
                    : "有効なメールアドレスであれば、Supabase が正しい受信箱へ再設定メールを送信します。"
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
                vi: "Supabase đã tạo tài khoản. Mở email xác nhận rồi quay lại đăng nhập trong Mistia nhé.",
                en: "Supabase created the account. Open the confirmation email, then come back and sign in to Mistia.",
                ja: "Supabase でアカウントを作成しました。確認メールを開いてから Mistia にログインしてください。"
            ),
            style: .info
        )
    }

    private func finishAuthentication(
        _ session: SupabaseAuthSession,
        restoringExistingSession: Bool
    ) async throws {
        let validSession = try await authService.refreshSessionIfNeeded(session)
        currentSession = validSession
        summary = SessionSummary(user: validSession.user)
        lastErrorMessage = nil
        authBanner = nil
        authFieldErrors = [:]
        authPendingEmail = nil
        authPhase = .signIn
        activeAuthAction = nil

        syncStatusTitle = mistiaLocalized(
            vi: restoringExistingSession ? "Đang nạp dữ liệu cloud" : "Đang đồng bộ lần đầu",
            en: restoringExistingSession ? "Loading cloud data" : "Running initial sync",
            ja: restoringExistingSession ? "クラウドデータを読み込み中" : "初回同期を実行中"
        )
        syncStatusDetail = mistiaLocalized(
            vi: "Mistia đang chuẩn bị dữ liệu local-first cho tài khoản này.",
            en: "Mistia is preparing the local-first cache for this account.",
            ja: "このアカウント向けにローカルファーストのキャッシュを準備しています。"
        )
        syncStatusSystemImage = "arrow.triangle.2.circlepath"

        let result = try await syncCoordinator.performInitialSync(session: validSession)
        lastSyncAt = .now
        syncStatusTitle = mistiaLocalized(
            vi: "Đồng bộ đang hoạt động",
            en: "Sync is active",
            ja: "同期が有効です"
        )
        syncStatusDetail = result.statusMessage
        syncStatusSystemImage = "checkmark.icloud"
        startLiveSyncLoop()
    }

    private func applyConfigurationMissingState() {
        authPhase = .signIn
        authBanner = nil
        authPendingEmail = nil
        authFieldErrors = [:]
        activeAuthAction = nil
        syncStatusTitle = mistiaLocalized(
            vi: "Chưa cấu hình Supabase",
            en: "Supabase is not configured",
            ja: "Supabase が未設定です"
        )
        syncStatusDetail = mistiaLocalized(
            vi: "Điền SUPABASE_URL và SUPABASE_ANON_KEY trong MistiaSyncConfig.plist rồi build lại app.",
            en: "Fill SUPABASE_URL and SUPABASE_ANON_KEY in MistiaSyncConfig.plist, then rebuild the app.",
            ja: "MistiaSyncConfig.plist に SUPABASE_URL と SUPABASE_ANON_KEY を設定してから再ビルドしてください。"
        )
        syncStatusSystemImage = "wrench.and.screwdriver"
    }

    private func applySignedOutState() {
        authPhase = .signIn
        authBanner = nil
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
        lastErrorMessage = error.localizedDescription
        syncStatusTitle = mistiaLocalized(
            vi: "Đồng bộ đang chờ mạng",
            en: "Sync is waiting for the network",
            ja: "同期はネットワーク待ちです"
        )
        syncStatusDetail = error.localizedDescription
        syncStatusSystemImage = "wifi.exclamationmark"
    }

    private func isInfrastructureAuthError(_ error: Error) -> Bool {
        if error is URLError {
            return true
        }

        guard let serviceError = error as? SupabaseServiceError else {
            return false
        }

        switch serviceError {
        case .configurationMissing, .invalidURL, .invalidResponse, .missingSession, .missingRefreshToken, .oauthCallbackSchemeMissing, .oauthSessionStartFailed:
            return true
        case .serverMessage, .oauthCancelled, .oauthCallbackMissing:
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

    private func isGoogleOAuthSetupError(_ error: Error) -> Bool {
        let message = errorMessage(for: error)
        return message.contains("provider is not enabled")
            || message.contains("unsupported provider")
            || message.contains("redirect")
            || message.contains("callback")
    }

    private func infrastructureErrorMessage(for error: Error) -> String {
        if error is URLError {
            return mistiaLocalized(
                vi: "Mistia chưa thể kết nối đến Supabase. Kiểm tra mạng rồi thử lại nhé.",
                en: "Mistia can't reach Supabase right now. Check your connection and try again.",
                ja: "現在 Mistia は Supabase に接続できません。通信状況を確認してから再度お試しください。"
            )
        }

        if let serviceError = error as? SupabaseServiceError {
            switch serviceError {
            case .configurationMissing:
                return mistiaLocalized(
                    vi: "Supabase chưa được cấu hình đầy đủ trong app này.",
                    en: "Supabase hasn't been configured completely in this build.",
                    ja: "このビルドでは Supabase の設定がまだ完了していません。"
                )
            case .invalidURL, .invalidResponse, .missingSession, .missingRefreshToken, .oauthCancelled, .oauthCallbackMissing, .oauthCallbackSchemeMissing, .oauthSessionStartFailed, .serverMessage:
                break
            }
        }

        return mistiaLocalized(
            vi: "Hệ thống xác thực đang tạm bận. Thử lại sau ít phút nhé.",
            en: "The authentication service is temporarily busy. Please try again in a moment.",
            ja: "認証サービスが一時的に混み合っています。少し待ってからお試しください。"
        )
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

    private func scheduleSync() {
        Task { [weak self] in
            await self?.syncNow()
        }
    }

    private func drainSyncQueue() async {
        isSyncInFlight = true
        while needsAnotherSync {
            needsAnotherSync = false
            applySyncingState()

            do {
                guard let activeSession = currentSession else { break }
                let validSession = try await authService.refreshSessionIfNeeded(activeSession)
                currentSession = validSession
                let result = try await syncCoordinator.sync(session: validSession)
                lastSyncAt = .now
                lastErrorMessage = nil
                syncStatusTitle = mistiaLocalized(
                    vi: "Đồng bộ đang hoạt động",
                    en: "Sync is active",
                    ja: "同期が有効です"
                )
                syncStatusDetail = result.statusMessage
                syncStatusSystemImage = "checkmark.icloud"
            } catch {
                applySyncErrorState(error)
            }
        }
        isSyncInFlight = false
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
