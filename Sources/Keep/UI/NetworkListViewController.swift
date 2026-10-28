#if canImport(UIKit)
    import Combine
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
                case .successful: return transaction.statusCode.map { (200 ..< 300).contains($0) } ?? false
                case .clientError: return transaction.statusCode.map { (400 ..< 500).contains($0) } ?? false
                case .serverError: return transaction.statusCode.map { (500 ..< 600).contains($0) } ?? false
                case .failed: return transaction.statusCode == nil || transaction.errorDescription != nil
                }
            }
        }

        private var dataSource: UITableViewDiffableDataSource<Int, KeepHTTPTransaction>!
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
                (cell as? NetworkCell)?.configure(with: transaction)
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
            tableView.backgroundView = visible.isEmpty ? emptyLabel(
                all.isEmpty ? "No network requests yet in this session." : "No requests match the search or status."
            ) : nil
        }

        private func emptyLabel(_ text: String) -> UILabel {
            let label = UILabel()
            label.text = text
            label.numberOfLines = 0
            label.textAlignment = .center
            label.textColor = .secondaryLabel
            return label
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

    /// Dense network row with method, status, path, host and response size.
    final class NetworkCell: UITableViewCell {
        static let reuseIdentifier = "NetworkCell"
        private static let timeFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "HH:mm:ss.SSS"
            return formatter
        }()

        private let methodPill = PillLabel(
            text: "", color: .systemIndigo, background: UIColor.systemIndigo.withAlphaComponent(0.12)
        )
        private let statusPill = PillLabel(
            text: "", color: .systemRed, background: UIColor.systemRed.withAlphaComponent(0.12)
        )
        private let durationLabel = UILabel()
        private let sizeLabel = UILabel()
        private let pathLabel = UILabel()
        private let hostLabel = UILabel()
        private let errorLabel = UILabel()

        override init(style _: UITableViewCell.CellStyle, reuseIdentifier: String?) {
            super.init(style: .default, reuseIdentifier: reuseIdentifier)
            selectionStyle = .default

            for label in [durationLabel, sizeLabel] {
                label.font = KeepTheme.codeFont(ofSize: 10)
                label.adjustsFontForContentSizeCategory = true
                label.textColor = .secondaryLabel
                label.textAlignment = .right
                label.setContentCompressionResistancePriority(.required, for: .horizontal)
            }

            pathLabel.font = KeepTheme.codeFont(ofSize: 12, weight: .medium)
            pathLabel.adjustsFontForContentSizeCategory = true
            pathLabel.textColor = .label
            pathLabel.numberOfLines = 2
            pathLabel.lineBreakMode = .byTruncatingMiddle

            hostLabel.font = .preferredFont(forTextStyle: .caption1)
            hostLabel.adjustsFontForContentSizeCategory = true
            hostLabel.textColor = .secondaryLabel
            hostLabel.lineBreakMode = .byTruncatingTail

            errorLabel.font = .preferredFont(forTextStyle: .caption2)
            errorLabel.adjustsFontForContentSizeCategory = true
            errorLabel.textColor = .systemRed
            errorLabel.numberOfLines = 2

            let statusGroup = UIStackView(arrangedSubviews: [methodPill, statusPill])
            statusGroup.axis = .horizontal
            statusGroup.spacing = 6

            let timingGroup = UIStackView(arrangedSubviews: [durationLabel, sizeLabel])
            timingGroup.axis = .vertical
            timingGroup.alignment = .trailing
            timingGroup.spacing = 2

            let topRow = UIStackView(arrangedSubviews: [statusGroup, UIView(), timingGroup])
            topRow.axis = .horizontal
            topRow.alignment = .center
            topRow.spacing = 8

            let stack = UIStackView(arrangedSubviews: [topRow, pathLabel, hostLabel, errorLabel])
            stack.axis = .vertical
            stack.alignment = .fill
            stack.spacing = 4
            stack.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 9),
                stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
                stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
                stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -9)
            ])
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        func configure(with transaction: KeepHTTPTransaction) {
            let statusText = transaction.statusCode.map(String.init) ?? "ERR"
            let statusColor = KeepTheme.statusColor(transaction.statusCode)
            methodPill.text = transaction.method.uppercased()
            statusPill.text = statusText
            statusPill.textColor = statusColor
            statusPill.backgroundColor = statusColor.withAlphaComponent(0.12)
            durationLabel.text = String(format: "%.0f ms", transaction.duration * 1000)
            sizeLabel.text = transaction.responseBody.map { ByteCountDisplay.string($0.byteCount) } ?? "—"
            pathLabel.text = transaction.displayPath.isEmpty ? "/" : transaction.displayPath
            let host = URLComponents(string: transaction.url)?.host ?? transaction.url
            hostLabel.text = [host, Self.timeFormatter.string(from: transaction.startedAt), transaction.label]
                .joined(separator: " · ")
            errorLabel.text = transaction.errorDescription
            errorLabel.isHidden = transaction.errorDescription == nil
            contentView.backgroundColor = transaction.errorDescription == nil
                ? .systemBackground
                : UIColor.systemRed.withAlphaComponent(0.055)
            accessoryType = .disclosureIndicator
        }
    }
#endif
