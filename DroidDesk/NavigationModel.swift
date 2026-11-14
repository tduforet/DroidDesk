import Foundation
import Observation

@MainActor
@Observable
final class NavigationModel {
    var section: AppSection = .dashboard

    func show(_ section: AppSection) {
        self.section = section
    }
}
