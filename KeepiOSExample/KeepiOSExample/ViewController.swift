//
//  ViewController.swift
//  KeepiOSExample
//
//  Created by Michael Amiro on 28/09/2025.
//

import UIKit
import Keep
import Logging

// swiftlint:disable:next type_body_length
class ViewController: UIViewController {
    private enum Constants {
        static let autoLoggingInterval: TimeInterval = 6
        static let startingBalance: Double = 12_840.42
    }

    private let apiClient = FinanceAPIClient()
    private var transactions: [Transaction] = []
    private var autoLoggingTimer: Timer?
    private var autoLogStep = 0
    private var currentBalance: Double = Constants.startingBalance
    private var isLoggingActive = false
    private var hasLoggedInitialLayoutMetrics = false
    private var hasLoggedEmptyTableState = false

    private let accountLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .headline)
        label.textColor = .secondaryLabel
        label.text = "Freelancer Treasury"
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let balanceLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.monospacedDigitSystemFont(ofSize: 34, weight: .bold)
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let statusLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = .tertiaryLabel
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let fetchButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Fetch Latest Activity", for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        button.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.12)
        button.layer.cornerRadius = 10
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let loggingButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Start Auto Logging", for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        button.backgroundColor = UIColor.systemTeal.withAlphaComponent(0.12)
        button.layer.cornerRadius = 10
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let viewLogsButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Open Keep Log Viewer", for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        button.backgroundColor = UIColor.systemIndigo.withAlphaComponent(0.12)
        button.layer.cornerRadius = 10
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()

    private lazy var actionStack: UIStackView = {
        let stack = UIStackView(
            arrangedSubviews: [
                fetchButton,
                loggingButton,
                viewLogsButton
            ]
        )
        stack.axis = .vertical
        stack.spacing = 12
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.rowHeight = 64
        table.separatorInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        table.tableFooterView = UIView()
        return table
    }()

    private lazy var currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = Locale.current.currencyCode ?? "USD"
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    private lazy var dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    deinit {
        autoLoggingTimer?.invalidate()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureUI()
        renderBalance()
        FinanceLogger.dashboard.trace("viewDidLoad lifecycle finished", metadata: [
            "device": .string(UIDevice.current.model),
            "buttons": .string(String(actionStack.arrangedSubviews.count))
        ])
        FinanceLogger.dashboard.notice("Dashboard loaded", metadata: [
            "auto_logging_interval": .string("\(Constants.autoLoggingInterval)s"),
            "starting_balance": .string(String(Constants.startingBalance))
        ])
        startAutoLogging()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !hasLoggedInitialLayoutMetrics else { return }
        hasLoggedInitialLayoutMetrics = true
        let safeArea = view.safeAreaInsets
        FinanceLogger.dashboard.debug("Captured initial layout metrics", metadata: [
            "safe_area_top": .string(String(format: "%.0f", safeArea.top)),
            "safe_area_bottom": .string(String(format: "%.0f", safeArea.bottom)),
            "table_height": .string(String(format: "%.0f", tableView.bounds.height))
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        FinanceLogger.dashboard.debug("Dashboard became visible", metadata: [
            "animated": .string(String(animated)),
            "trait_collection": .string(traitCollection.preferredContentSizeCategory.rawValue)
        ])
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else {
            return
        }
        FinanceLogger.dashboard.trace("Trait collection color appearance changed", metadata: [
            "new_style": .string(traitCollection.userInterfaceStyle == .dark ? "dark" : "light")
        ])
    }

    private func configureUI() {
        view.backgroundColor = .systemBackground

        fetchButton.addTarget(self, action: #selector(fetchTransactionsTapped), for: .touchUpInside)
        loggingButton.addTarget(self, action: #selector(toggleAutoLoggingTapped), for: .touchUpInside)
        viewLogsButton.addTarget(self, action: #selector(openLogsTapped), for: .touchUpInside)

        tableView.dataSource = self
        tableView.delegate = self

        [fetchButton, loggingButton, viewLogsButton].forEach { button in
            button.contentEdgeInsets = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
            button.setTitleColor(.label, for: .normal)
        }

        view.addSubview(accountLabel)
        view.addSubview(balanceLabel)
        view.addSubview(statusLabel)
        view.addSubview(activityIndicator)
        view.addSubview(actionStack)
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            accountLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            accountLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),

            balanceLabel.topAnchor.constraint(equalTo: accountLabel.bottomAnchor, constant: 4),
            balanceLabel.leadingAnchor.constraint(equalTo: accountLabel.leadingAnchor),

            statusLabel.topAnchor.constraint(equalTo: balanceLabel.bottomAnchor, constant: 8),
            statusLabel.leadingAnchor.constraint(equalTo: accountLabel.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            activityIndicator.centerYAnchor.constraint(equalTo: fetchButton.centerYAnchor),
            activityIndicator.trailingAnchor.constraint(equalTo: actionStack.trailingAnchor),

            actionStack.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 24),
            actionStack.leadingAnchor.constraint(equalTo: accountLabel.leadingAnchor),
            actionStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            tableView.topAnchor.constraint(equalTo: actionStack.bottomAnchor, constant: 20),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            fetchButton.heightAnchor.constraint(equalToConstant: 48),
            loggingButton.heightAnchor.constraint(equalTo: fetchButton.heightAnchor),
            viewLogsButton.heightAnchor.constraint(equalTo: fetchButton.heightAnchor)
        ])

        statusLabel.text = "Auto logging will record scheduled finance events."

        FinanceLogger.dashboard.debug("Configured dashboard UI hierarchy", metadata: [
            "view_count": .string(String(view.subviews.count)),
            "table_style": .string("inset_grouped")
        ])
    }

    private func renderBalance() {
        let formatted = currencyFormatter.string(from: NSNumber(value: currentBalance)) ?? "$0.00"
        balanceLabel.text = formatted
        FinanceLogger.dashboard.info("Balance label updated", metadata: [
            "rendered_balance": .string(formatted)
        ])
    }

    @objc private func fetchTransactionsTapped() {
        activityIndicator.startAnimating()
        fetchButton.isEnabled = false
        statusLabel.text = "Fetching recent transactions…"

        FinanceLogger.dashboard.debug("User initiated manual refresh")

        apiClient.fetchTransactions { [weak self] result in
            guard let self else { return }
            self.activityIndicator.stopAnimating()
            self.fetchButton.isEnabled = true

            switch result {
            case .success(let transactions):
                self.transactions = transactions
                self.hasLoggedEmptyTableState = transactions.isEmpty
                self.tableView.reloadData()
                self.recalculateBalance()
                let merchants = transactions.map { $0.merchant }.joined(separator: ", ")
                self.statusLabel.text = "Loaded \(transactions.count) transactions: \(merchants)."

                let customerToken = "cus_demo_secure_token_\(transactions.first?.id ?? 0)_ledger"
                FinanceLogger.dashboard.info("Customer ledger token refreshed", metadata: [
                    "customer_token": .string(customerToken),
                    "merchant_sample": .string(transactions.first?.merchant ?? "n/a"),
                    "transaction_count": .string(String(transactions.count))
                ])

                FinanceLogger.dashboard.notice("Transactions refreshed", metadata: [
                    "count": .string(String(transactions.count)),
                    "net_change": .string(String(format: "%.2f", transactions.reduce(0) { $0 + $1.amount }))
                ])
            case .failure(let error):
                self.statusLabel.text = "Failed to refresh: \(error.localizedDescription)"
                FinanceLogger.dashboard.error("Transaction refresh failed", metadata: [
                    "error": .string(error.localizedDescription)
                ])
            }
        }
    }

    private func recalculateBalance() {
        let delta = transactions.reduce(0) { $0 + $1.amount }
        currentBalance = Constants.startingBalance + delta
        renderBalance()
        FinanceLogger.dashboard.debug("Recalculated balance", metadata: [
            "transaction_delta": .string(String(format: "%.2f", delta))
        ])
    }

    @objc private func toggleAutoLoggingTapped() {
        if isLoggingActive {
            stopAutoLogging()
        } else {
            startAutoLogging()
        }
        FinanceLogger.dashboard.trace("Toggled auto logging", metadata: [
            "is_logging_active": .string(String(isLoggingActive))
        ])
    }

    private func startAutoLogging() {
        guard autoLoggingTimer == nil else { return }
        isLoggingActive = true
        loggingButton.setTitle("Stop Auto Logging", for: .normal)
        FinanceLogger.scheduler.info("Auto logging enabled", metadata: [
            "interval": .string("\(Constants.autoLoggingInterval)s")
            ]
        )
        FinanceLogger.scheduler.trace("Preparing scheduler timer")

        autoLoggingTimer = Timer.scheduledTimer(
            withTimeInterval: Constants.autoLoggingInterval,
            repeats: true) { [weak self] _ in
            self?.emitScheduledLog()
        }
        if let autoLoggingTimer {
            RunLoop.main.add(autoLoggingTimer, forMode: .common)
        }
        emitScheduledLog()
    }

    private func stopAutoLogging() {
        isLoggingActive = false
        loggingButton.setTitle("Start Auto Logging", for: .normal)
        autoLoggingTimer?.invalidate()
        autoLoggingTimer = nil
        FinanceLogger.scheduler.info("Auto logging disabled")
    }

    private func emitScheduledLog() {
        let events = [
            "Reconciling overnight settlements",
            "Aggregating card transactions",
            "Updating portfolio performance",
            "Refreshing cash runway projection",
            "Syncing tax estimations"
        ]

        guard !events.isEmpty else { return }
        let message = events[autoLogStep % events.count]
        autoLogStep += 1

        let balanceString = currencyFormatter.string(from: NSNumber(value: currentBalance)) ?? "$0.00"
        let hangProbability = Double(autoLogStep % 10) / 10.0
        let hangMetadata = Logger.MetadataValue.string(String(format: "%.2f", hangProbability))
        let sessionToken = "sess_demo_finance_autolog_\(String(format: "%03d", autoLogStep))"

        FinanceLogger.scheduler.trace("Heartbeat captured", metadata: [
            "sequence": .string(String(autoLogStep)),
            "hang_probability": hangMetadata
        ])
        FinanceLogger.scheduler.debug("Scheduler metrics sampled", metadata: [
            "active_transactions": .string(String(transactions.count)),
            "balance_snapshot": .string(balanceString)
        ])
        FinanceLogger.scheduler.info("Scheduler session token rotated:", metadata: [
            "session_token": .string(sessionToken),
            "sequence": .string(String(autoLogStep))
        ])

        if hangProbability > 0.8 {
            FinanceLogger.scheduler.critical("Detected elevated hang probability", metadata: [
                "hang_probability": hangMetadata,
                "detector": .string("finance.scheduler")
            ])
        } else if hangProbability > 0.5 {
            FinanceLogger.scheduler.warning("Hang trend approaching threshold", metadata: [
                "hang_probability": hangMetadata
            ])
        }

        FinanceLogger.scheduler.notice("\(message)", metadata: [
            "balance_snapshot": .string(balanceString),
            "sequence": .string(String(autoLogStep))
        ])

        statusLabel.text = "Last scheduled log: \(message)."
    }

    @objc private func openLogsTapped() {
        FinanceLogger.dashboard.trace("Presenting Keep log viewer")
        let logViewController = Keep.logViewController()
        let navigationController = UINavigationController(rootViewController: logViewController)
        present(navigationController, animated: true)
    }
}

extension ViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if transactions.isEmpty {
            if !hasLoggedEmptyTableState {
                hasLoggedEmptyTableState = true
                FinanceLogger.dashboard.warning("Transactions table empty", metadata: [
                    "has_auto_logging": .string(String(isLoggingActive))
                ])
            }
            return 1
        }
        hasLoggedEmptyTableState = false
        return transactions.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if transactions.isEmpty {
            let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "PlaceholderCell")
            cell.selectionStyle = .none
            cell.textLabel?.text = "No transactions yet"
            cell.detailTextLabel?.text = "Tap \"Fetch Latest Activity\" to load samples."
            cell.textLabel?.textColor = .secondaryLabel
            cell.detailTextLabel?.textColor = .tertiaryLabel
            return cell
        }

        let reuseIdentifier = "TransactionCell"
        let cell = tableView.dequeueReusableCell(withIdentifier: reuseIdentifier) ??
        UITableViewCell(style: .subtitle, reuseIdentifier: reuseIdentifier)

        let transaction = transactions[indexPath.row]
        cell.selectionStyle = .none
        cell.textLabel?.text = transaction.merchant
        cell.textLabel?.font = .preferredFont(forTextStyle: .headline)
        cell.detailTextLabel?.text = "\(transaction.category) • \(dateFormatter.string(from: transaction.date))"
        cell.detailTextLabel?.textColor = .secondaryLabel

        let amountLabel: UILabel
        if let existing = cell.accessoryView as? UILabel {
            amountLabel = existing
        } else {
            amountLabel = UILabel()
            amountLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 16, weight: .semibold)
            cell.accessoryView = amountLabel
        }

        amountLabel.textColor = transaction.amount >= 0 ? .systemGreen : .systemRed
        amountLabel.text = currencyFormatter.string(from: NSNumber(value: transaction.amount))
        amountLabel.sizeToFit()

        return cell
    }
}
