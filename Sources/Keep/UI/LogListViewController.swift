#if canImport(UIKit)
    import Combine
    import Logging
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

        private var dataSource: UITableViewDiffableDataSource<Section, LogEntry>!
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
                (cell as? LogCell)?.configure(with: entry)
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
            tableView.backgroundView = visible.isEmpty ? emptyLabel(
                allEntries.isEmpty ? "No logs yet in this session." : "No logs match the search or level."
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

    /// Dense row with a level marker, time, source, message and a metadata summary.
    final class LogCell: UITableViewCell {
        static let reuseIdentifier = "LogCell"
        private static let timeFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "HH:mm:ss.SSS"
            return formatter
        }()

        private let levelBar = UIView()
        private let levelPill = PillLabel(text: "", color: .label, background: .clear)
        private let timeLabel = UILabel()
        private let sourceLabel = UILabel()
        private let pinImageView = UIImageView(image: UIImage(systemName: "pin.fill"))
        private let messageLabel = UILabel()
        private let summaryLabel = UILabel()

        override init(style _: UITableViewCell.CellStyle, reuseIdentifier: String?) {
            super.init(style: .default, reuseIdentifier: reuseIdentifier)
            selectionStyle = .default
            levelBar.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(levelBar)

            timeLabel.font = KeepTheme.codeFont(ofSize: 11, weight: .medium)
            timeLabel.textColor = .secondaryLabel
            timeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

            sourceLabel.font = .preferredFont(forTextStyle: .caption1)
            sourceLabel.adjustsFontForContentSizeCategory = true
            sourceLabel.textColor = .secondaryLabel
            sourceLabel.textAlignment = .right
            sourceLabel.lineBreakMode = .byTruncatingMiddle
            sourceLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

            pinImageView.tintColor = .systemOrange
            pinImageView.contentMode = .scaleAspectFit
            pinImageView.setContentHuggingPriority(.required, for: .horizontal)

            let topRow = UIStackView(arrangedSubviews: [levelPill, timeLabel, sourceLabel, pinImageView])
            topRow.axis = .horizontal
            topRow.alignment = .center
            topRow.spacing = 8

            messageLabel.font = .preferredFont(forTextStyle: .subheadline)
            messageLabel.adjustsFontForContentSizeCategory = true
            messageLabel.textColor = .label
            messageLabel.numberOfLines = 3
            messageLabel.lineBreakMode = .byTruncatingTail

            summaryLabel.font = KeepTheme.codeFont(ofSize: 10, weight: .regular)
            summaryLabel.adjustsFontForContentSizeCategory = true
            summaryLabel.textColor = .secondaryLabel
            summaryLabel.numberOfLines = 1
            summaryLabel.lineBreakMode = .byTruncatingTail

            let stack = UIStackView(arrangedSubviews: [topRow, messageLabel, summaryLabel])
            stack.axis = .vertical
            stack.alignment = .fill
            stack.spacing = 5
            stack.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(stack)
            NSLayoutConstraint.activate([
                levelBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                levelBar.topAnchor.constraint(equalTo: contentView.topAnchor),
                levelBar.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
                levelBar.widthAnchor.constraint(equalToConstant: 3),
                stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 9),
                stack.leadingAnchor.constraint(equalTo: levelBar.trailingAnchor, constant: 10),
                stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
                stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -9),
                pinImageView.widthAnchor.constraint(equalToConstant: 12),
                pinImageView.heightAnchor.constraint(equalToConstant: 14)
            ])
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        func configure(with entry: LogEntry) {
            let color = entry.level.uiColor
            levelBar.backgroundColor = color
            levelPill.text = entry.level.shortCode
            levelPill.textColor = color
            levelPill.backgroundColor = color.withAlphaComponent(0.12)
            timeLabel.text = Self.timeFormatter.string(from: entry.timestamp)
            sourceLabel.text = entry.source.isEmpty ? entry.label : entry.source
            pinImageView.isHidden = !entry.isPinned
            messageLabel.text = entry.message
            let summary = Self.metadataSummary(entry)
            let tag = entry.tag == "Unknown" ? nil : entry.tag
            summaryLabel.text = [tag, summary].compactMap { $0 }.joined(separator: " · ")
            summaryLabel.isHidden = summaryLabel.text?.isEmpty ?? true
            contentView.backgroundColor = entry.level >= .error ? entry.level.backgroundTint : .systemBackground
            accessoryType = .disclosureIndicator
        }

        private static func metadataSummary(_ entry: LogEntry) -> String? {
            guard !entry.metadata.isEmpty else { return nil }
            let key = entry.metadata.keys.sorted().first ?? "metadata"
            let data = try? KeepCodec.encoder().encode(entry.metadata)
            let count = data?.count ?? entry.metadata.reduce(0) { $0 + $1.key.utf8.count + $1.value.text.utf8.count }
            return "{ } \(key) · \(ByteCountDisplay.string(count))"
        }
    }
#endif
