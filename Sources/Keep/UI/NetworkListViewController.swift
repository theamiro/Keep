#if canImport(UIKit)
    import Combine
    import SwiftUI
    import UIKit

    /// Network transactions for the current session, newest first, searchable and filterable by status.
    final class NetworkListViewController: KeepListViewController {
        private enum Scope: Int {
            case all
            case successful
            case clientError
            case serverError
            case failed

            func includes(_ transaction: KeepHTTPTransaction) -> Bool {
                switch self {
                case .all: return true
                case .successful: return transaction.statusCode.map { (200..<300).contains($0) } ?? false
                case .clientError: return transaction.statusCode.map { (400..<500).contains($0) } ?? false
                case .serverError: return transaction.statusCode.map { (500..<600).contains($0) } ?? false
                case .failed: return transaction.statusCode == nil || transaction.errorDescription != nil
                }
            }
        }

        private typealias NetworkCell = KeepHostingCell<NetworkRow>

        private var dataSource: UITableViewDiffableDataSource<Int, KeepHTTPTransaction>!
        private let emptyState = KeepHostingView(KeepEmptyState(message: ""))
        private var searchTerm = ""
        private var scope = Scope.all
        private var searchDebounce: DispatchWorkItem?
        private var cancellables = Set<AnyCancellable>()

        override func viewDidLoad() {
            super.viewDidLoad()
            tableView.register(NetworkCell.self, forCellReuseIdentifier: NetworkCell.reuseIdentifier)
            tableView.estimatedRowHeight = 94
            tableView.rowHeight = UITableView.automaticDimension
            dataSource = UITableViewDiffableDataSource(tableView: tableView) { tableView, indexPath, transaction in
                let cell = tableView.dequeueReusableCell(withIdentifier: NetworkCell.reuseIdentifier, for: indexPath)
                (cell as? NetworkCell)?.setContent(NetworkRow(transaction: transaction))
                return cell
            }

            let search = UISearchController(searchResultsController: nil)
            search.obscuresBackgroundDuringPresentation = false
            search.searchResultsUpdater = self
            search.searchBar.delegate = self
            search.searchBar.placeholder = "Search method, URL, status"
            search.searchBar.scopeButtonTitles = ["All", "2xx", "4xx", "5xx", "Failed"]
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
            guard let transaction = dataSource.itemIdentifier(for: indexPath) else { return }
            navigationController?.pushViewController(
                NetworkDetailViewController(transaction: transaction), animated: true
            )
        }

        private func reload() {
            let all = core.transactions.snapshot()
            let visible = all.filter { transaction in
                scope.includes(transaction) && (searchTerm.isEmpty || Self.matches(transaction, term: searchTerm))
            }
            var snapshot = NSDiffableDataSourceSnapshot<Int, KeepHTTPTransaction>()
            snapshot.appendSections([0])
            snapshot.appendItems(visible, toSection: 0)
            dataSource.apply(snapshot, animatingDifferences: false)
            title = "Network"
            tabBarItem.badgeValue = visible.isEmpty ? nil : String(visible.count)
            emptyState.update(
                KeepEmptyState(
                    message: all.isEmpty
                        ? "No network requests yet in this session."
                        : "No requests match the search or status."
                ))
            tableView.backgroundView = visible.isEmpty ? emptyState : nil
        }

        private static func matches(_ transaction: KeepHTTPTransaction, term: String) -> Bool {
            let needle = term.lowercased()
            return transaction.method.lowercased().contains(needle)
                || transaction.url.lowercased().contains(needle)
                || (transaction.statusCode.map(String.init) ?? "err").contains(needle)
                || transaction.label.lowercased().contains(needle)
                || (transaction.errorDescription?.lowercased().contains(needle) ?? false)
        }
    }

    extension NetworkListViewController: UISearchResultsUpdating, UISearchBarDelegate {
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
            UINavigationController(rootViewController: NetworkListViewController(core: PreviewSamples.makeCore()))
        }
    #endif
#endif
