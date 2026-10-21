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

        private var dataSource: UITableViewDiffableDataSource<Section, LogEntry>!
        private var allEntries: [LogEntry] = []
        private var minimumLevel: Logger.Level = .trace
        private var searchTerm = ""
        private var searchDebounce: DispatchWorkItem?
        private var cancellables = Set<AnyCancellable>()

        override func viewDidLoad() {
            super.viewDidLoad()
            tableView.register(LogCell.self, forCellReuseIdentifier: LogCell.reuseIdentifier)
            tableView.estimatedRowHeight = 72
            tableView.rowHeight = UITableView.automaticDimension
            dataSource = UITableViewDiffableDataSource(tableView: tableView) { tableView, indexPath, entry in
                let cell = tableView.dequeueReusableCell(withIdentifier: LogCell.reuseIdentifier, for: indexPath)
                (cell as? LogCell)?.configure(with: entry)
                return cell
            }
            navigationItem.leftBarButtonItems = [
                UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(doneTapped)),
                UIBarButtonItem(title: "Levels", style: .plain, target: self, action: #selector(levelsTapped))
            ]
            let search = UISearchController(searchResultsController: nil)
            search.obscuresBackgroundDuringPresentation = false
            search.searchResultsUpdater = self
            search.searchBar.placeholder = "Search message, tag, metadata"
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
            let action = UIContextualAction(style: .normal, title: entry.isPinned ? "Unpin" : "Pin") { [weak self] _, _, done in
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
            action.backgroundColor = .systemBlue
            return UISwipeActionsConfiguration(actions: [action])
        }

        // MARK: Filtering

        @objc private func levelsTapped() {
            let sheet = UIAlertController(title: "Show levels", message: nil, preferredStyle: .actionSheet)
            let options: [(String, Logger.Level)] = [
                ("All levels", .trace), ("Debug and above", .debug), ("Info and above", .info),
                ("Warning and above", .warning), ("Error and above", .error)
            ]
            for (title, level) in options {
                sheet.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                    Task { @MainActor in
                        self?.minimumLevel = level
                        self?.reload()
                    }
                })
            }
            sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            sheet.popoverPresentationController?.barButtonItem = navigationItem.leftBarButtonItems?.last
            present(sheet, animated: true)
        }

        private func reload() {
            allEntries = core.logs.snapshot()
            let visible = allEntries.filter { entry in
                entry.level >= minimumLevel && (searchTerm.isEmpty || entry.matches(searchTerm))
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
            title = "Logs (\(visible.count))"
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

    extension LogListViewController: UISearchResultsUpdating {
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

    /// One log row: time, level and tag on the first line; the message below.
    final class LogCell: UITableViewCell {
        static let reuseIdentifier = "LogCell"

        override init(style _: UITableViewCell.CellStyle, reuseIdentifier: String?) {
            super.init(style: .subtitle, reuseIdentifier: reuseIdentifier)
            textLabel?.numberOfLines = 3
            textLabel?.font = .preferredFont(forTextStyle: .subheadline)
            detailTextLabel?.numberOfLines = 1
            detailTextLabel?.font = UIFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        func configure(with entry: LogEntry) {
            textLabel?.text = entry.message
            detailTextLabel?.text = "\(KeepCodec.displayString(for: entry.timestamp))  \(entry.level.rawValue.uppercased())  \(entry.tag)"
            detailTextLabel?.textColor = entry.level.uiColor
            accessoryType = entry.isPinned ? .none : .disclosureIndicator
            accessoryView = entry.isPinned ? UIImageView(image: UIImage(systemName: "pin.fill")) : nil
        }
    }
#endif
