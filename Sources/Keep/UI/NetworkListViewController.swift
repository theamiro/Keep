#if canImport(UIKit)
    import Combine
    import UIKit

    /// Network transactions for the current session, newest first, searchable by method, URL and status.
    final class NetworkListViewController: KeepListViewController {
        private var dataSource: UITableViewDiffableDataSource<Int, KeepHTTPTransaction>!
        private var searchTerm = ""
        private var searchDebounce: DispatchWorkItem?
        private var cancellables = Set<AnyCancellable>()

        override func viewDidLoad() {
            super.viewDidLoad()
            tableView.register(UITableViewCell.self, forCellReuseIdentifier: "NetworkCell")
            dataSource = UITableViewDiffableDataSource(tableView: tableView) { tableView, indexPath, transaction in
                let cell = tableView.dequeueReusableCell(withIdentifier: "NetworkCell", for: indexPath)
                cell.textLabel?.font = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
                cell.textLabel?.numberOfLines = 2
                cell.textLabel?.text = "\(transaction.method)  \(transaction.statusCode.map(String.init) ?? "ERR")  \(transaction.displayPath)"
                cell.textLabel?.textColor = NetworkListViewController.color(for: transaction.statusCode)
                cell.detailTextLabel?.text = "\(Int(transaction.duration * 1000)) ms · \(transaction.label)"
                cell.accessoryType = .disclosureIndicator
                return cell
            }
            let search = UISearchController(searchResultsController: nil)
            search.obscuresBackgroundDuringPresentation = false
            search.searchResultsUpdater = self
            search.searchBar.placeholder = "Search method, URL, status"
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
            navigationController?.pushViewController(NetworkDetailViewController(transaction: transaction), animated: true)
        }

        private func reload() {
            let all = core.transactions.snapshot()
            let visible = searchTerm.isEmpty ? all : all.filter { NetworkListViewController.matches($0, term: searchTerm) }
            var snapshot = NSDiffableDataSourceSnapshot<Int, KeepHTTPTransaction>()
            snapshot.appendSections([0])
            snapshot.appendItems(visible, toSection: 0)
            dataSource.apply(snapshot, animatingDifferences: false)
            title = "Network (\(visible.count))"
            tableView.backgroundView = visible.isEmpty ? {
                let label = UILabel()
                label.text = all.isEmpty ? "No network requests yet in this session." : "No requests match the search."
                label.numberOfLines = 0
                label.textAlignment = .center
                label.textColor = .secondaryLabel
                return label
            }() : nil
        }

        private static func matches(_ transaction: KeepHTTPTransaction, term: String) -> Bool {
            let needle = term.lowercased()
            return transaction.method.lowercased().contains(needle)
                || transaction.url.lowercased().contains(needle)
                || (transaction.statusCode.map(String.init) ?? "err").contains(needle)
        }

        private static func color(for statusCode: Int?) -> UIColor {
            switch statusCode {
            case let code? where (200 ..< 300).contains(code): return .systemGreen
            case let code? where (300 ..< 400).contains(code): return .systemBlue
            case nil: return .systemRed
            default: return .systemOrange
            }
        }
    }

    extension NetworkListViewController: UISearchResultsUpdating {
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
    }
#endif
