//
//  ArrivalsTableViewController.swift
//  Proper
//
//  Created by Elliott Williams on 7/26/16.
//  Copyright © 2016 Elliott Williams. All rights reserved.
//

import UIKit
import ReactiveSwift
import Dwifft
import Result

class ArrivalsTableViewController: UITableViewController, ProperViewController {

  var station: MutableStation!

  // MARK: Internal properties
  internal var diffCalculator: SingleSectionTableViewDiffCalculator<MutableVehicle>!
  internal var disposable = CompositeDisposable()
  internal var routeDisposables = [MutableRoute: Disposable]()

  internal weak var routesCollectionView: UICollectionView?
  internal var routesCollectionModel: RoutesCollectionViewModel!

  // MARK: Signalled properties
  lazy var vehicles: Property<Set<MutableVehicle>> = {
    // Given a signal emitting the list of MutableRoutes for this station...
    let producer = self.station.routes.producer
      // ...flatMap down to a joint set of vehicles.
      .flatMap(.latest) { (routes: Set<MutableRoute>) -> SignalProducer<Set<MutableVehicle>, NoError> in

        // Each member of `routes` has a producer for vehicles on that route. Combine the sets produced by each
        // producer into a joint set.

        // Obtain the first set's producer and combine all other sets' producers with this one. Return an empty set
        // if there are no routes in the set.
        guard let firstProducer = routes.first?.vehicles.producer else {
          return SignalProducer(value: Set())
        }

        return routes.dropFirst().reduce(firstProducer) { producer, route in
          let vehicles = route.vehicles.producer
          // `combineLatest` causes the producer to wait until the two signals being combines have emitted. In
          // this case, it means that no vehicles will be forwarded until all routes have produced a list of
          // vehicles. After that, changes to vehicles of any route will forward the entire set again.
          return producer.combineLatest(with: vehicles).map { $0.union($1) }
        }
    }

    return Property(initial: Set(), then: producer)
  }()

  // MARK: Methods
  convenience init(observing station: MutableStation, style: UITableViewStyle)
  {
    self.init(style: style)
    self.station = station
  }

  override func viewDidLoad() {
    // Initialize the diff calculator for the table, which starts using any routes already on `station`.
    diffCalculator = SingleSectionTableViewDiffCalculator(tableView: self.tableView, initialRows: vehicles.value.sorted())

    // Create a controller to manage the routes collection view within the table.
    routesCollectionModel = RoutesCollectionViewModel(routes: Property(station.routes))

    // Register the arrival nib for use in the table.
    tableView.register(UINib(nibName: "ArrivalTableViewCell", bundle: nil), forCellReuseIdentifier: "arrivalCell")
  }

  override func viewDidAppear(_ animated: Bool) {
    // Follow changes to routes on the station. As routes are associated and disassociated, maintain signals on all
    // current routes, so that vehicle information can be obtained. Dispose these signals as routes go away.
    disposable += station.routes.producer.combinePrevious(Set())
      .startWithValues { old, new in
        new.subtracting(old).forEach { route in
          self.routeDisposables[route] = route.producer.startWithFailed(self.displayError)
          self.disposable += self.routeDisposables[route]
        }
        old.subtracting(new).forEach { route in
          self.routeDisposables[route]?.dispose()
        }
    }

    // When the list of vehicles for this station changes, update the table.
    disposable += vehicles.producer.startWithValues { vehicles in
      self.tableView.beginUpdates()
      self.diffCalculator.rows = vehicles.sorted()
      self.tableView.endUpdates()
    }
  }

  override func viewWillDisappear(_ animated: Bool) {
    disposable.dispose()
    super.viewWillDisappear(animated)
  }

  // Bind vehicle attributes to a given cell
  func arrivalCell(for indexPath: IndexPath) -> ArrivalTableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: "arrivalCell", for: indexPath) as! ArrivalTableViewCell
    _ = diffCalculator.rows[indexPath.row]

    //        cell.apply(vehicle)
    return cell
  }

  // Get a cell for displaying the routes collection, and connect it to the routes collection controller instantiated
  // at start. Since there is only one routes collection cell (its `numbersOfRows` call always returns 1), the
  // assignment onto `routesCollection` won't overwrite some other cell.
  func routesCollectionCell(for indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: "routesCollectionCell", for: indexPath) as! ArrivalTableRouteCollectionCell
    cell.bind(routesCollectionModel)

    // Store a weak reference to the cell's collection view so that we can examine its state without needing a
    // a reference to this particular table view cell.
    routesCollectionView = cell.collectionView
    return cell
  }

  // MARK: Table View Delegate Methods
  override func numberOfSections(in tableView: UITableView) -> Int { return 2 }
  override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
    return ["Routes Served", "Arrivals"][section]
  }
  override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    return [1, diffCalculator.rows.count][section]
  }
  override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
    // The routes collection cell has a custom height, while other cells go off of the table view's default.
    return [70, tableView.rowHeight][indexPath.section]
  }

  override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    switch indexPath.section {
    case 0:
      return routesCollectionCell(for: indexPath)
    case 1:
      return arrivalCell(for: indexPath)
    default:
      fatalError("Bad ArrivalsTable section number (\(indexPath.section))")
    }
  }

  override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
    switch segue.identifier ?? "" {
    case "showRoute":
      let dest = segue.destination as! RouteViewController
      let index = routesCollectionView!.indexPathsForSelectedItems!.first!
      let route = routesCollectionModel.routes.value[index.row]
      dest.route = route
    default:
      return
    }
  }
}


struct VehicleOnRoute: Equatable {
  let vehicle: Vehicle
  let route: MutableRoute
}

func ==(a: VehicleOnRoute, b: VehicleOnRoute) -> Bool {
  return a.route == b.route && a.vehicle == b.vehicle
}
