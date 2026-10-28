#if canImport(UIKit)
    import Combine
    import Logging
    import SwiftUI
    import UIKit

    /// Logs for the current session: newest first, pinned entries first, searchable and filterable by level.
    final class LogListViewController: KeepListViewController, ToastPresentable {
        private enum Section: Hashable {
            case pinned
            case all
        }

        private enum Scope: Int {
            case all
            case info
            case warning
            case error

            var minimumLevel: Logger.Level {
                switch self {
                case .all: return .trace
                case .info: return .info
                case .warning: return .warning
                case .error: return .error
                }
            }
        }

        private typealias LogCell = KeepHostingCell<LogRow>

        private var dataSource: UITableViewDiffableDataSource<Section, LogEntry>!
        private let emptyState = KeepHostingView(KeepEmptyState(message: ""))
        private var allEntries: [LogEntry] = []
        private var scope = Scope.all
        private var searchTerm = ""
        private var searchDebounce: DispatchWorkItem?
        private var cancellables = Set<AnyCancellable>()

        override func viewDidLoad() {
            super.viewDidLoad()
            tableView.register(LogCell.self, forCellReuseIdentifier: LogCell.reuseIdentifier)
            tableView.estimatedRowHeight = 92
            tableView.rowHeight = UITableView.automaticDimension
            tableView.separatorInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 0)
            dataSource = UITableViewDiffableDataSource(tableView: tableView) { tableView, indexPath, entry in
                let cell = tableView.dequeueReusableCell(withIdentifier: LogCell.reuseIdentifier, for: indexPath)
                (cell as? LogCell)?.setContent(LogRow(entry: entry))
                return cell
            }

            let search = UISearchController(searchResultsController: nil)
            search.obscuresBackgroundDuringPresentation = false
            search.searchResultsUpdater = self
            search.searchBar.delegate = self
            search.searchBar.placeholder = "Search message, tag, metadata"
            search.searchBar.scopeButtonTitles = ["All", "Info+", "Warn+", "Error"]
            search.searchBar.selectedScopeButtonIndex = Scope.all.rawValue
            search.searchBar.showsScopeBar = true
            navigationItem.searchController = search
            navigationItem.hidesSearchBarWhenScrolling = false
            definesPresentationContext = true

            core.changes
                .throttle(for: .milliseconds(250), scheduler: DispatchQueue.main, latest: true)
                .sink { [weak self] in self?.reload() }
                .store(in: &cancellables)
            reload()
        }

        override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
            tableView.deselectRow(at: indexPath, animated: true)
            guard let entry = dataSource.itemIdentifier(for: indexPath) else { return }
            navigationController?.pushViewController(LogDetailViewController(entry: entry), animated: true)
        }

        override func tableView(
            _: UITableView,
            leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath
        ) -> UISwipeActionsConfiguration? {
            guard let entry = dataSource.itemIdentifier(for: indexPath) else { return nil }
            let action = UIContextualAction(
                style: .normal,
                title: entry.isPinned ? "Unpin" : "Pin"
            ) { [weak self] _, _, done in
                Task { @MainActor in
                    guard let self, let pinned = self.core.togglePin(id: entry.id) else {
                        done(false)
                        return
                    }
                    self.reload()
                    self.showPopup(message: pinned ? "Pinned" : "Unpinned")
                    done(true)
                }
            }
            action.backgroundColor = UIColor.systemBlue
            return UISwipeActionsConfiguration(actions: [action])
        }

        private func reload() {
            allEntries = core.logs.snapshot()
            let visible = allEntries.filter { entry in
                entry.level >= scope.minimumLevel && (searchTerm.isEmpty || entry.matches(searchTerm))
            }
            var snapshot = NSDiffableDataSourceSnapshot<Section, LogEntry>()
            let pinned = visible.filter(\.isPinned)
            let others = visible.filter { !$0.isPinned }
            if !pinned.isEmpty {
                snapshot.appendSections([.pinned])
                snapshot.appendItems(pinned, toSection: .pinned)
            }
            if !others.isEmpty {
                snapshot.appendSections([.all])
                snapshot.appendItems(others, toSection: .all)
            }
            dataSource.apply(snapshot, animatingDifferences: false)
            title = "Logs"
            tabBarItem.badgeValue = visible.isEmpty ? nil : String(visible.count)
            emptyState.update(
                KeepEmptyState(
                    message: allEntries.isEmpty ? "No logs yet in this session." : "No logs match the search or level."
                ))
            tableView.backgroundView = visible.isEmpty ? emptyState : nil
        }
    }

    extension LogListViewController: UISearchResultsUpdating, UISearchBarDelegate {
        func updateSearchResults(for searchController: UISearchController) {
            searchDebounce?.cancel()
            let term = searchController.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let work = DispatchWorkItem { [weak self] in
                self?.searchTerm = term
                self?.reload()
            }
            searchDebounce = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        }

        func searchBar(_ searchBar: UISearchBar, selectedScopeButtonIndexDidChange selectedScope: Int) {
            scope = Scope(rawValue: selectedScope) ?? .all
            reload()
            searchBar.setShowsCancelButton(!searchTerm.isEmpty, animated: false)
        }
    }

    #if DEBUG
        @available(iOS 17, *)
        #Preview {
            UINavigationController(rootViewController: LogListViewController(core: PreviewSamples.makeCore()))
        }
    #endif
#endif
