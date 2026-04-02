import Foundation
import Observation
import SwiftData

struct SessionSummary: Equatable {
    let userID: UUID
    let displayName: String
    let email: String

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

        do {
            let session = try await authService.signIn(email: email, password: password)
            try await finishAuthentication(session, restoringExistingSession: false)
        } catch {
            lastErrorMessage = error.localizedDescription
            syncStatusTitle = mistiaLocalized(
                vi: "Đăng nhập chưa thành công",
                en: "Couldn't sign in",
                ja: "ログインできませんでした"
            )
            syncStatusDetail = error.localizedDescription
            syncStatusSystemImage = "exclamationmark.triangle"
        }

        isWorking = false
    }

    func signUp(email: String, password: String, displayName: String) async {
        guard isConfigured else {
            applyConfigurationMissingState()
            return
        }

        isWorking = true
        lastErrorMessage = nil

        do {
            let session = try await authService.signUp(
                email: email,
                password: password,
                displayName: displayName
            )
            try await finishAuthentication(session, restoringExistingSession: false)
        } catch SupabaseServiceError.emailConfirmationRequired {
            lastErrorMessage = nil
            syncStatusTitle = mistiaLocalized(
                vi: "Kiểm tra email để xác nhận",
                en: "Check your email to confirm",
                ja: "確認メールをチェックしてください"
            )
            syncStatusDetail = mistiaLocalized(
                vi: "Supabase đã tạo tài khoản. Hãy mở email xác nhận rồi quay lại đăng nhập trong Mistia.",
                en: "Supabase created the account. Open the confirmation email, then come back and sign in to Mistia.",
                ja: "Supabase でアカウントを作成しました。確認メールを開いてから Mistia にログインしてください。"
            )
            syncStatusSystemImage = "envelope.badge"
        } catch {
            lastErrorMessage = error.localizedDescription
            syncStatusTitle = mistiaLocalized(
                vi: "Tạo tài khoản chưa thành công",
                en: "Couldn't create the account",
                ja: "アカウントを作成できませんでした"
            )
            syncStatusDetail = error.localizedDescription
            syncStatusSystemImage = "exclamationmark.triangle"
        }

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

    private func finishAuthentication(
        _ session: SupabaseAuthSession,
        restoringExistingSession: Bool
    ) async throws {
        let validSession = try await authService.refreshSessionIfNeeded(session)
        currentSession = validSession
        summary = SessionSummary(user: validSession.user)
        lastErrorMessage = nil

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
            ?? user.userMetadata?.name
            ?? resolvedEmail.components(separatedBy: "@").first
            ?? "Mistia"

        self.init(
            userID: user.id,
            displayName: resolvedName,
            email: resolvedEmail
        )
    }
}
