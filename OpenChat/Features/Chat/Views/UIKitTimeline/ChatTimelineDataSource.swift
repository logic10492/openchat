import UIKit

@MainActor
final class ChatTimelineDataSource {
    typealias Section = ChatTimelineSection
    typealias DataSource = UICollectionViewDiffableDataSource<Section, String>

    private let collectionView: UICollectionView
    private var dataSource: DataSource!
    private var itemsByID: [String: ChatTimelineItem] = [:]
    private var configuration: ChatTimelineConfiguration

    init(collectionView: UICollectionView, configuration: ChatTimelineConfiguration) {
        self.collectionView = collectionView
        self.configuration = configuration
        registerCells()
        configureDataSource()
    }

    func updateConfiguration(_ configuration: ChatTimelineConfiguration) {
        self.configuration = configuration
    }

    func apply(
        items newItems: [ChatTimelineItem],
        animated: Bool,
        completion: @escaping () -> Void
    ) {
        let oldItemsByID = itemsByID
        let oldIDs = currentItemIdentifiers()
        let newIDs = newItems.map(\.stableID)
        itemsByID = Dictionary(uniqueKeysWithValues: newItems.map { ($0.stableID, $0) })

        if oldIDs == newIDs {
            reconfigureChangedItems(newItems, oldItemsByID: oldItemsByID, completion: completion)
            return
        }

        var snapshot = NSDiffableDataSourceSnapshot<Section, String>()
        snapshot.appendSections([.main])
        snapshot.appendItems(newIDs, toSection: .main)

        let changedIDs = newItems.compactMap { item -> String? in
            guard oldItemsByID[item.stableID] != nil, oldItemsByID[item.stableID] != item else {
                return nil
            }
            return item.stableID
        }
        if !changedIDs.isEmpty {
            snapshot.reloadItems(changedIDs)
        }

        dataSource.apply(snapshot, animatingDifferences: animated, completion: completion)
    }

    private func currentItemIdentifiers() -> [String] {
        let snapshot = dataSource.snapshot()
        guard snapshot.indexOfSection(.main) != nil else { return [] }
        return snapshot.itemIdentifiers(inSection: .main)
    }

    private func reconfigureChangedItems(
        _ newItems: [ChatTimelineItem],
        oldItemsByID: [String: ChatTimelineItem],
        completion: @escaping () -> Void
    ) {
        let changedIDs = newItems.compactMap { item -> String? in
            guard oldItemsByID[item.stableID] != nil, oldItemsByID[item.stableID] != item else {
                return nil
            }
            return item.stableID
        }
        guard !changedIDs.isEmpty else {
            completion()
            return
        }

        var snapshot = dataSource.snapshot()
        if #available(iOS 15.0, *) {
            snapshot.reconfigureItems(changedIDs)
        } else {
            snapshot.reloadItems(changedIDs)
        }
        dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
            self?.collectionView.collectionViewLayout.invalidateLayout()
            completion()
        }
    }

    private func registerCells() {
        collectionView.register(ChatMessageCell.self, forCellWithReuseIdentifier: ChatMessageCell.reuseIdentifier)
        collectionView.register(ChatTimelineLoadEarlierCell.self, forCellWithReuseIdentifier: ChatTimelineLoadEarlierCell.reuseIdentifier)
        collectionView.register(ChatTimelineDateSeparatorCell.self, forCellWithReuseIdentifier: ChatTimelineDateSeparatorCell.reuseIdentifier)
        collectionView.register(ChatTimelineEmptyCell.self, forCellWithReuseIdentifier: ChatTimelineEmptyCell.reuseIdentifier)
        collectionView.register(ChatTimelineExtractionCell.self, forCellWithReuseIdentifier: ChatTimelineExtractionCell.reuseIdentifier)
        collectionView.register(ChatTimelineDiagnosticsCell.self, forCellWithReuseIdentifier: ChatTimelineDiagnosticsCell.reuseIdentifier)
        collectionView.register(ChatTimelinePerformanceMarkerCell.self, forCellWithReuseIdentifier: ChatTimelinePerformanceMarkerCell.reuseIdentifier)
    }

    private func configureDataSource() {
        dataSource = DataSource(collectionView: collectionView) { [weak self] collectionView, indexPath, identifier in
            guard let self, let item = self.itemsByID[identifier] else {
                return UICollectionViewCell()
            }
            return self.cell(for: item, collectionView: collectionView, indexPath: indexPath)
        }
    }

    private func cell(
        for item: ChatTimelineItem,
        collectionView: UICollectionView,
        indexPath: IndexPath
    ) -> UICollectionViewCell {
        switch item {
        case let .loadEarlier(hasMore, isLoading):
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: ChatTimelineLoadEarlierCell.reuseIdentifier,
                for: indexPath
            ) as! ChatTimelineLoadEarlierCell
            cell.apply(hasMore: hasMore, isLoading: isLoading, action: configuration.onLoadEarlier)
            return cell
        case .empty:
            return collectionView.dequeueReusableCell(
                withReuseIdentifier: ChatTimelineEmptyCell.reuseIdentifier,
                for: indexPath
            )
        case let .dateSeparator(_, date):
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: ChatTimelineDateSeparatorCell.reuseIdentifier,
                for: indexPath
            ) as! ChatTimelineDateSeparatorCell
            cell.apply(date: date)
            return cell
        case let .message(row):
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: ChatMessageCell.reuseIdentifier,
                for: indexPath
            ) as! ChatMessageCell
            cell.apply(
                row: row,
                onEdit: configuration.onEdit,
                onDelete: configuration.onDelete,
                onRegenerate: configuration.onRegenerate
            )
            return cell
        case let .extraction(extraction):
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: ChatTimelineExtractionCell.reuseIdentifier,
                for: indexPath
            ) as! ChatTimelineExtractionCell
            cell.apply(item: extraction, onDismiss: configuration.onDismissExtraction)
            return cell
        case let .diagnostics(summary):
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: ChatTimelineDiagnosticsCell.reuseIdentifier,
                for: indexPath
            ) as! ChatTimelineDiagnosticsCell
            cell.apply(summary: summary)
            return cell
        case .performanceCompletion:
            return collectionView.dequeueReusableCell(
                withReuseIdentifier: ChatTimelinePerformanceMarkerCell.reuseIdentifier,
                for: indexPath
            )
        }
    }
}

enum ChatTimelineSection {
    case main
}
