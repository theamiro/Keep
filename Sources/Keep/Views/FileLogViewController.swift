//
//  FileLogViewController.swift
//  Keep
//
//  Created by Michael Amiro on 24/04/2025.
//

import Combine
import SwiftUI
import UIKit

@available(iOS 13.0, *)
public final class FileLogViewController: UIViewController {
    @ObservedObject var viewModel: FileLogViewModel
    private var cancellables = Set<AnyCancellable>()
    private var hostingController: UIHostingController<FilterView>!

    private lazy var searchController: UISearchController = {
        let controller = UISearchController()
        controller.searchResultsUpdater = self
        return controller
    }()

    private lazy var clearButton: UIButton = {
        let button = UIButton()
        button.setImage(UIImage(systemName: "trash.fill"), for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(presentAlertView), for: .touchUpInside)
        button.tintColor = .white
        button.backgroundColor = .systemBlue
        button.layer.cornerRadius = 28
        button.tag = -1
        return button
    }()

    private lazy var refreshControl: UIRefreshControl = {
        let control = UIRefreshControl()
        control.addTarget(self, action: #selector(performRefresh), for: .valueChanged)
        return control
    }()

    private lazy var tableView: UITableView = {
        let tableView = UITableView()
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.estimatedRowHeight = 80
        tableView.rowHeight = UITableView.automaticDimension
        tableView.register(LogCell.self, forCellReuseIdentifier: "logCell")
        tableView.register(ContentUnavailableCell.self, forCellReuseIdentifier: "contentUnavailableCell")
        tableView.delegate = self
        tableView.dataSource = self
        tableView.refreshControl = refreshControl
        return tableView
    }()

    public init(viewModel: FileLogViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(tableView)
        view.backgroundColor = .systemBackground

        navigationItem.searchController = searchController

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        configureTableHeader()
        configureObservers()
    }

    private func configureClearButton() {
        if viewModel.logs.count < 1 {
            clearButton.removeFromSuperview()
        } else {
            guard (view.subviews.first(where: { ($0 as? UIButton)?.tag == -1 }) == nil) else {
                return
            }
            view.addSubview(clearButton)
            NSLayoutConstraint.activate([
                clearButton.heightAnchor.constraint(equalToConstant: 56),
                clearButton.widthAnchor.constraint(equalToConstant: 56),
                clearButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
                clearButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
            ])
        }
    }

    private func configureTableHeader() {
        let filterView = FilterView(selectedLevel: $viewModel.selectedLevel)
        hostingController = UIHostingController(rootView: filterView)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        let containerView = UIView(frame: CGRect(x: 0, y: 0, width: view.frame.width, height: 44))
        containerView.addSubview(hostingController.view)

        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: containerView.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            hostingController.view.heightAnchor.constraint(equalToConstant: 44),
            hostingController.view.widthAnchor.constraint(equalTo: containerView.widthAnchor),
        ])

        tableView.tableHeaderView = containerView
        addChild(hostingController)
        hostingController.didMove(toParent: self)
    }

    private func configureObservers() {
        viewModel.$logs
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.tableView.reloadData()
                self.title = "Logs (\(self.viewModel.logs.count))"
                configureClearButton()
            }
            .store(in: &cancellables)

        viewModel.$selectedLevel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in
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

@available(iOS 13.0, *)
extension FileLogViewController: UITableViewDelegate, UITableViewDataSource {
    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if viewModel.logs.count == 0 {
            return 1
        }
        return viewModel.logs.count
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if viewModel.logs.count == 0 {
            return configureContentUnavailableCell(with: tableView, indexPath: indexPath)
        } else {
            return configureLogCell(with: tableView, indexPath: indexPath)
        }
    }

    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard viewModel.logs.count > 0 else { return }
        let log = viewModel.logs[indexPath.row]
        let controller = LogDetailsViewController(log: log)
        navigationController?.pushViewController(controller, animated: true)
    }

    public func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if viewModel.logs.count == 0 {
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
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "logCell", for: indexPath) as? LogCell else {
            let tableViewCell = UITableViewCell()
            tableViewCell.textLabel?.text = viewModel.logs[indexPath.row].description
            return tableViewCell
        }
        tableView.separatorColor = .separator
        tableView.allowsSelection = true
        cell.configure(with: viewModel.logs[indexPath.row], parent: self)
        return cell
    }
}

@available(iOS 13.0, *)
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
