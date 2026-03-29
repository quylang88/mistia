import Foundation

enum MockDataLoader {
    static let dashboard: DashboardDump = load("MockDashboard")
    static let transactions: TransactionScreenDump = load("MockTransactions")
    static let planning: PlanningScreenDump = load("MockPlanning")
    static let management: ManagementScreenDump = load("MockManagement")

    private static func load<T: Decodable>(_ resourceName: String) -> T {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "json") else {
            fatalError("Missing \(resourceName).json in app bundle.")
        }

        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            fatalError("Unable to decode \(resourceName).json: \(error)")
        }
    }
}
