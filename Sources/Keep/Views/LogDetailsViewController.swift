//
//  LogDetailsViewController.swift
//  Keep
//
//  Created by Michael Amiro on 24/04/2025.
//

import UIKit

@available(iOS 13.0, *)
final class LogDetailsViewController: UIViewController {
    var log: Log

    private lazy var collectionView: UICollectionView = {
        let layout = createLayout()
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.contentInset.bottom = 64
        return collectionView

    }()

    init(log: Log) {
        self.log = log
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Log Details"
        collectionView.delegate = self
        collectionView.dataSource = self
        configureUI()
        setupVerticalToolbar()
    }

    private func configureUI() {
        view.backgroundColor = .systemBackground
        view.addSubview(collectionView)
        collectionView.register(LogHeaderCollectionCell.self, forCellWithReuseIdentifier: "headerCollectionCell")
        collectionView.register(LogMetadataCollectionCell.self, forCellWithReuseIdentifier: "metadataCollectionCell")
        collectionView.register(TitleHeaderReusableViewCell.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "titleHeaderReusableCell")
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }

    private func setupVerticalToolbar() {
        let toolbarContainer = UIView()
        toolbarContainer.backgroundColor = UIColor.systemGray6
        view.addSubview(toolbarContainer)

        let shareButton = UIButton(type: .system)
        shareButton.setTitle("Share", for: .normal)
        shareButton.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        shareButton.backgroundColor = UIColor.systemBlue
        shareButton.setTitleColor(UIColor.white, for: .normal)
        shareButton.layer.cornerRadius = 8
        shareButton.addTarget(self, action: #selector(shareButtonTapped), for: .touchUpInside)

        toolbarContainer.addSubview(shareButton)
        toolbarContainer.translatesAutoresizingMaskIntoConstraints = false
        shareButton.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            toolbarContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            toolbarContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbarContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            shareButton.topAnchor.constraint(equalTo: toolbarContainer.topAnchor, constant: 10),
            shareButton.leadingAnchor.constraint(equalTo: toolbarContainer.leadingAnchor, constant: 16),
            shareButton.trailingAnchor.constraint(equalTo: toolbarContainer.trailingAnchor, constant: -16),
            shareButton.heightAnchor.constraint(equalToConstant: 50),
            shareButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10)
        ])
    }

    @objc private func shareButtonTapped() {
        let items: [Any] = [log.description]
        let activityController = UIActivityViewController(activityItems: items, applicationActivities: nil)
        navigationController?.present(activityController, animated: true)
    }

    private func createLayout(spacing: CGFloat = 0) -> UICollectionViewLayout {
        let item = NSCollectionLayoutItem(
            layoutSize: NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0),
                heightDimension: .estimated(100)
            )
        )
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0),
                heightDimension: .estimated(100)
            ),
            subitems: [item]
        )
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = spacing
        section.contentInsets = NSDirectionalEdgeInsets(top: spacing, leading: 0, bottom: spacing, trailing: 0)

        return UICollectionViewCompositionalLayout(section: section)
    }
}

@available(iOS 13.0, *)
extension LogDetailsViewController: UICollectionViewDataSource, UICollectionViewDelegate {
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 2
    }
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return 1
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        switch getCellType(for: indexPath) {
        case .header:
            guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "headerCollectionCell", for: indexPath) as? LogHeaderCollectionCell else {
                return UICollectionViewCell()
            }
            cell.configure(with: log, parent: self)
            return cell
        case .metadata:
            guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "metadataCollectionCell", for: indexPath) as? LogMetadataCollectionCell else {
                return UICollectionViewCell()
            }
            cell.configure(with: log.metadata, parent: self)
            return cell
        }
    }

    private func getCellType(for indexPath: IndexPath) -> CellType {
        switch indexPath.section {
        case 0:
            return .header
        case 1:
            return .metadata
        default:
            return .header
        }
    }

    enum CellType {
        case header, metadata
    }
}

@available(iOS 17.0, *)
#Preview {
    LogDetailsViewController(log: Log(id: "747474", level: .critical, description: "Something crazy went wrong", timestamp: Date(), metadata: [
        "url": .string("https://api.example.com"),
        "method": .string("GET"),
        "headers": .dictionary([
            "Authorization": .string("Bearer ***"),
            "Content-Type": .string("application/json")
        ])
    ], source: "Somewhere"))
}
