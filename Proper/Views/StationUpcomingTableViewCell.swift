//
//  StationUpcomingTableViewCell.swift
//  Proper
//
//  Created by Elliott Williams on 12/26/16.
//  Copyright © 2016 Elliott Williams. All rights reserved.
//

import UIKit
import ReactiveCocoa

class StationUpcomingTableViewCell: UITableViewCell, StationUpcomingCell {
    @IBOutlet weak var title: TransitLabel!
    @IBOutlet weak var subtitle: TransitLabel!
    @IBOutlet weak var collectionView: UICollectionView!

    var disposable: CompositeDisposable?
    var viewModel: RoutesCollectionViewModel?
    let routes = MutableProperty<Set<MutableRoute>>(Set())

    override init(style: UITableViewCellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        contentView.addSubview(stationUpcomingCellView())
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        disposable?.dispose()
    }

    override func prepareForReuse() {
        disposable?.dispose()
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        initStationUpcomingCell()
    }
}
