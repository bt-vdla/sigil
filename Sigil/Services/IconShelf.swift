import Foundation
import Observation

/// The user's own icons: recently copied and starred. Stored as icon ids ("lucide:trash").
@Observable
final class IconShelf {
    static let recentLimit = 24

    private(set) var recents: [String] = UserDefaults.standard.stringArray(forKey: "recentIcons") ?? []
    private(set) var favourites: [String] = UserDefaults.standard.stringArray(forKey: "favouriteIcons") ?? []

    func recordUse(_ id: String) {
        recents.removeAll { $0 == id }
        recents.insert(id, at: 0)
        recents = Array(recents.prefix(Self.recentLimit))
        UserDefaults.standard.set(recents, forKey: "recentIcons")
    }

    func isFavourite(_ id: String) -> Bool {
        favourites.contains(id)
    }

    func toggleFavourite(_ id: String) {
        if let index = favourites.firstIndex(of: id) {
            favourites.remove(at: index)
        } else {
            favourites.insert(id, at: 0)
        }
        UserDefaults.standard.set(favourites, forKey: "favouriteIcons")
    }

    /// Ranking bonus in search results.
    var boost: [String: Int] {
        var b = Dictionary(recents.map { ($0, 100) }, uniquingKeysWith: max)
        for id in favourites { b[id] = 150 }
        return b
    }
}
