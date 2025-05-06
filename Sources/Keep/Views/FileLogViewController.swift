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
        view.addSubview(clearButton)
        view.backgroundColor = .systemBackground

        navigationItem.searchController = searchController

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            clearButton.heightAnchor.constraint(equalToConstant: 56),
            clearButton.widthAnchor.constraint(equalToConstant: 56),
            clearButton.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            clearButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
        ])

        configureTableHeader()
        configureObservers()
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
        return viewModel.logs.count
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard
            let cell = tableView.dequeueReusableCell(withIdentifier: "logCell", for: indexPath)
                as? LogCell
        else {
            let tableViewCell = UITableViewCell()
            tableViewCell.textLabel?.text = viewModel.logs[indexPath.row].description
            return tableViewCell
        }
        cell.configure(with: viewModel.logs[indexPath.row], parent: self)
        return cell
    }

    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let log = viewModel.logs[indexPath.row]
        let controller = LogDetailsViewController(log: log)
        navigationController?.pushViewController(controller, animated: true)
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
        rootViewController: FileLogViewController(
            viewModel: FileLogViewModel(configuration: KeepConfiguration(logHandler: .inMemoryCache))))
}
