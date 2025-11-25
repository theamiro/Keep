//
//  FileLogViewController.swift
//  Keep
//
//  Created by Michael Amiro on 24/04/2025.
//

#if canImport(UIKit)
import Combine
import SwiftUI
import UIKit

/// UIKit view controller that displays logs with search, filtering, and pinning support.
public final class FileLogViewController: UIViewController {
    @ObservedObject var viewModel: FileLogViewModel
    private var cancellables = Set<AnyCancellable>()
    private var hostingController: UIHostingController<FilterView>!
    private var sectionedLogs: [LogSection] = []

    private lazy var searchController: UISearchController = {
        let controller = UISearchController()
        controller.searchResultsUpdater = self
        return controller
    }()

    private lazy var clearButton: UIButton = {
        let button = UIButton()
        button.tintColor = .systemBlue
        if #available(iOS 15.0, *) {
            button.configuration = .borderedProminent()
        } else {
            button.backgroundColor = UIColor.systemBlue
        }
        button.accessibilityLabel = "Clear Logs"
        button.setImage(UIImage(systemName: "trash.fill"), for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(presentAlertView), for: .touchUpInside)
        button.layer.cornerRadius = 24
        button.layer.masksToBounds = true
        button.tag = -1
        return button
    }()

    private lazy var refreshControl: UIRefreshControl = {
        let control = UIRefreshControl()
        control.addTarget(self, action: #selector(performRefresh), for: .valueChanged)
        return control
    }()

    private lazy var filterView: UIView = {
        let filterView = FilterView(selectedLevel: $viewModel.selectedLevel)
        hostingController = UIHostingController(rootView: filterView)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        return hostingController.view
    }()

    private lazy var tableView: UITableView = {
        let tableView = UITableView()
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.estimatedRowHeight = 96
        tableView.rowHeight = UITableView.automaticDimension
        tableView.register(HostingTableViewCell<LogViewCell>.self, forCellReuseIdentifier: "logCell")
        tableView.register(ContentUnavailableCell.self, forCellReuseIdentifier: "contentUnavailableCell")
        tableView.delegate = self
        tableView.dataSource = self
        tableView.refreshControl = refreshControl
        return tableView
    }()

    /// Creates a log viewer bound to the supplied view model.
    ///
    /// - Parameter viewModel: The source responsible for providing and mutating log entries.
    public init(viewModel: FileLogViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(filterView)
        view.addSubview(tableView)
        view.backgroundColor = .systemBackground

        navigationItem.searchController = searchController

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: filterView.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            filterView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            filterView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            filterView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            filterView.heightAnchor.constraint(equalToConstant: 44),
            filterView.widthAnchor.constraint(equalTo: view.widthAnchor)
        ])
        configureObservers()
    }

    private func configureClearButton() {
        if viewModel.logs.count < 1 {
            clearButton.removeFromSuperview()
        } else {
            guard view.subviews.first(where: { ($0 as? UIButton)?.tag == -1 }) == nil else {
                return
            }
            view.addSubview(clearButton)
            NSLayoutConstraint.activate([
                clearButton.heightAnchor.constraint(equalToConstant: 48),
                clearButton.widthAnchor.constraint(equalToConstant: 48),
                clearButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
                clearButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24)
            ])
        }
    }

    private func configureObservers() {
        viewModel.$logs
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.sectionedLogs = LogSectionBuilder.makeSections(from: self.viewModel.logs)
                self.tableView.reloadData()
                self.title = "Logs (\(self.viewModel.logs.count))"
                configureClearButton()
            }
            .store(in: &cancellables)

        viewModel.$selectedLevel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                let filterView = FilterView(selectedLevel: self?.$viewModel.selectedLevel ?? .constant(nil))
                self?.hostingController.rootView = filterView
                self?.hostingController.view.setNeedsLayout()
            }
            .store(in: &cancellables)
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewModel.fetchLogs()
    }

    @objc
    private func performRefresh() {
        viewModel.fetchLogs()
        refreshControl.endRefreshing()
    }

    private func clearLog() {
        viewModel.clearLogs { [weak self] in
            self?.viewModel.fetchLogs()
        }
    }

    @objc
    private func presentAlertView() {
        let alertController = UIAlertController(
            title: "Delete Logs",
            message: "Are you sure you would like to delete all logs? This action cannot be undone.",
            preferredStyle: .alert)
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)
        let confirmAction = UIAlertAction(title: "Confirm", style: .destructive) { [weak self] _ in
            self?.clearLog()
        }
        alertController.addAction(cancelAction)
        alertController.addAction(confirmAction)
        navigationController?.present(alertController, animated: true)
    }
}

extension FileLogViewController: UITableViewDelegate, UITableViewDataSource {
    public func numberOfSections(in tableView: UITableView) -> Int {
        sectionedLogs.isEmpty ? 1 : sectionedLogs.count
    }

    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if sectionedLogs.isEmpty {
            return 1
        }
        guard sectionedLogs.indices.contains(section) else {
            return 0
        }
        return sectionedLogs[section].logs.count
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if sectionedLogs.isEmpty {
            return configureContentUnavailableCell(with: tableView, indexPath: indexPath)
        } else {
            return configureLogCell(with: tableView, indexPath: indexPath)
        }
    }

    public func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard sectionedLogs.indices.contains(section) else {
            return nil
        }
        return sectionedLogs[section].title
    }

    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let log = log(for: indexPath) else { return }
        let controller = LogDetailsViewController(log: log)
        navigationController?.pushViewController(controller, animated: true)
    }

    public func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if sectionedLogs.isEmpty {
            return tableView.frame.height - 128
        }
        return UITableView.automaticDimension
    }

    private func configureContentUnavailableCell(with tableView: UITableView, indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "contentUnavailableCell", for: indexPath) as? ContentUnavailableCell else {
            return UITableViewCell()
        }
        var title: LocalizedStringKey = "No logs available yet"
        var description: LocalizedStringKey = "Continue using the application\nto view logs later."
        if !viewModel.searchTerm.isEmpty && viewModel.selectedLevel != nil {
            title = "No logs matching search criteria"
            description = "Try searching for a different term \"\(viewModel.searchTerm)\" or selecting a different log level from \"\(viewModel.selectedLevel?.rawValue ?? "Filter")\""
        } else if !viewModel.searchTerm.isEmpty {
            title = "No logs matching \"\(viewModel.searchTerm)\""
            description = "Try searching for a different term."
        } else if viewModel.selectedLevel != nil {
            title = "No logs matching \"\(viewModel.selectedLevel?.rawValue ?? "Filter")\""
            description = "Try selecting a different log level"
        }
        let model = ContentUnavailableModel(title: title, systemImage: "tray.fill", description: description)
        tableView.separatorColor = .clear
        tableView.allowsSelection = false
        cell.configure(with: model, parent: self)
        return cell
    }

    private func configureLogCell(with tableView: UITableView, indexPath: IndexPath) -> UITableViewCell {
        guard let log = log(for: indexPath) else {
            return UITableViewCell()
        }
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "logCell", for: indexPath) as? HostingTableViewCell<LogViewCell> else {
            let tableViewCell = UITableViewCell()
            tableViewCell.textLabel?.text = log.description
            return tableViewCell
        }
        tableView.separatorColor = .separator
        tableView.allowsSelection = true
        if #available(iOS 16.0, *) {
            cell.contentConfiguration = UIHostingConfiguration {
                LogViewCell(log: log)
            }
        } else {
            // TODO: Resolve sizing issue pre-iOS 16
            cell.host(LogViewCell(log: log), parent: self)
        }
        return cell
    }

    public func tableView(
        _ tableView: UITableView,
        leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard let log = log(for: indexPath) else {
            return nil
        }
        let actionTitle = log.pinned ? "Unpin" : "Pin"
        let imageName = log.pinned ? "pin.slash" : "pin"
        let bookmarkAction = UIContextualAction(style: .normal, title: actionTitle) { [weak self] _, _, completion in
            guard let self else {
                completion(false)
                return
            }
            Task {
                await self.viewModel.togglePin(for: log.id)
                await MainActor.run {
                    completion(true)
                }
            }
        }
        bookmarkAction.backgroundColor = .systemBlue
        bookmarkAction.image = UIImage(systemName: imageName)
        let config = UISwipeActionsConfiguration(actions: [bookmarkAction])
        config.performsFirstActionWithFullSwipe = true
        return config
    }

    public func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {

        guard let log = log(for: indexPath) else {
            return nil
        }
        let deleteAction = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
            guard let self else {
                completion(false)
                return
            }
            Task {
                await self.viewModel.deleteLog(withID: log.id)
                await MainActor.run {
                    completion(true)
                }
            }
        }
        deleteAction.image = UIImage(systemName: "trash")

        let config = UISwipeActionsConfiguration(actions: [deleteAction])
        config.performsFirstActionWithFullSwipe = true
        return config
    }
}

extension FileLogViewController: UISearchResultsUpdating {
    public func updateSearchResults(for searchController: UISearchController) {
        let searchText = searchController.searchBar.text ?? ""
        viewModel.searchTerm = searchText
    }
}

@available(iOS 17.0, *)
#Preview {
    UINavigationController(
        rootViewController: FileLogViewController(viewModel: FileLogViewModel.preview))
}

private extension FileLogViewController {
    func log(for indexPath: IndexPath) -> Log? {
        guard sectionedLogs.indices.contains(indexPath.section) else {
            return nil
        }
        let sectionLogs = sectionedLogs[indexPath.section].logs
        guard sectionLogs.indices.contains(indexPath.row) else {
            return nil
        }
        return sectionLogs[indexPath.row]
    }
}

final class HostingTableViewCell<Content: View>: UITableViewCell {
    private let hostingController = UIHostingController<Content?>(rootView: nil)

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        hostingController.view.backgroundColor = .clear
    }

    private func removeHostingControllerFromParent() {
        hostingController.willMove(toParent: nil)
        hostingController.view.removeFromSuperview()
        hostingController.removeFromParent()
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func host(_ rootView: Content, parent: UIViewController) {
        hostingController.rootView = rootView
        hostingController.view.invalidateIntrinsicContentSize()

        let requiresControllerMove = hostingController.parent != parent
        if requiresControllerMove {
            removeHostingControllerFromParent()
            parent.addChild(hostingController)
        }

        if !contentView.subviews.contains(hostingController.view) {
            contentView.addSubview(hostingController.view)
            hostingController.view.translatesAutoresizingMaskIntoConstraints = false
            hostingController.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor).isActive = true
            hostingController.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor).isActive = true
            hostingController.view.topAnchor.constraint(equalTo: contentView.topAnchor).isActive = true
            hostingController.view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor).isActive = true
        }

        if requiresControllerMove {
            hostingController.didMove(toParent: parent)
        }
    }
}
#endif
