//
//  ArrivalsTableViewControllerTests.swift
//  Proper
//
//  Created by Elliott Williams on 8/5/16.
//  Copyright © 2016 Elliott Williams. All rights reserved.
//

import XCTest
import ReactiveSwift
import Result
@testable import Proper

class ArrivalsTableViewControllerTests: XCTestCase {
  var station: MutableStation!
  var mock: ConnectionMock!
  var controller: ArrivalsTableViewController!
  var disposable: CompositeDisposable!

  override func setUp() {
    super.setUp()
    mock = ConnectionMock()
    disposable = CompositeDisposable()

    let expectation = self.expectation(description: "fixtures")
    Station.fixture(id: "stations.BUS100W").startWithValues { model in
      self.station = try! MutableStation(from: model, connection: self.mock)
      self.controller = ArrivalsTableViewController(observing: self.station, style: .plain, connection: self.mock)
      expectation.fulfill()
    }
    self.continueAfterFailure = false
    waitForExpectations(timeout: 5.0, handler: nil)
    self.continueAfterFailure = true
  }

  override func tearDown() {
    disposable.dispose()
    super.tearDown()
  }

  func requestView() {
    let _ = controller.view
    controller.viewWillAppear(false)
    controller.viewDidAppear(false)
  }

  func testSubscribeToStation() {
    // When the view is loaded...
    requestView()

    // ...then the topic for its station should be subscribed to.
    XCTAssertTrue(mock.subscribed(to: "stations.BUS100W"))
  }


  func testRoutesSignalSubscribesToRoutes() {
    // When view loads, route should be subscribed to.
    requestView()
    XCTAssertTrue(mock.subscribed(to: "routes.10"))
  }


  func testRouteUnsubscribedWhenLeft() {
    // Given a route subscribed to from when the view was created
    requestView()
    XCTAssertTrue(mock.subscribed(to: "routes.10"))

    // When a route is removed from the station's associatons...
    controller.station.routes.swap(Set())

    // ...it should be unsubscribed from.
    XCTAssertFalse(mock.subscribed(to: "routes.10"))
  }

  func testVehiclesSignalForNewVehicles() {
    // Given
    let vehicles = [
      Vehicle(id: "test1"),
      Vehicle(id: "test2"),
      Vehicle(id: "test3")
    ]
    let modifiedRoute = Route(shortName: "10", vehicles: vehicles)

    // When Route 10 is modified to contain a new list of vehicles...
    requestView()
    XCTAssertNotNil(controller.station.routes.value.first)
    if let route = controller.station.routes.value.first {
      XCTAssertNotNil(try? route.apply(modifiedRoute))
    }

    // ...then the list of vehicles should be updated
    XCTAssertEqual(controller.vehicles.value.map { $0.name }.sorted(), vehicles.map { $0.name }.sorted())
  }

  func testVehiclesSignalOnInitialVehicles() {
    // When the view is loaded...
    requestView()

    // ...then there should be no known vehicles.
    XCTAssertEqual(controller.vehicles.value.count, 0)
  }

  func testVehiclesSignalFromMultipleRoutes() {
    // Given a station with two routes, each with vehicles:
    let routeA = Route(shortName: "r1", vehicles: [
      Vehicle(id: "v1"), Vehicle(id: "v2"), Vehicle(id: "v3")
      ])
    let routeB = Route(shortName: "r2", vehicles: [
      Vehicle(id: "v4"), Vehicle(id: "v5")
      ])
    let modifiedStation = Station(stopCode: station.stopCode, routes: [routeA, routeB])

    // When the view is loaded and the new routes are applied...
    requestView()
    XCTAssertNotNil(try? controller.station.apply(modifiedStation))

    // Then the list of vehicles should contain vehicles from both routes.
    XCTAssertEqual(controller.vehicles.value.map { $0.identifier }.sorted(), ["v1", "v2", "v3", "v4", "v5"])
  }

  func testVehiclesSignalForVehiclelessRoute() {
    // Given a station with two routes, one of which has no vehicles:
    let routeA = Route(shortName: "r1", vehicles: [
      Vehicle(id: "v1"), Vehicle(id: "v2"), Vehicle(id: "v3")
      ])
    // `vehicles: nil` is the result of having no associated_objects["Shark::Station"] key in the serialized model
    let routeB = Route(shortName: "r2", vehicles: nil)
    let modifiedStation = Station(stopCode: station.stopCode, routes: [routeA, routeB])

    // When the view is loaded and the new routes are applied...
    requestView()
    XCTAssertNotNil(try? controller.station.apply(modifiedStation))

    // Then the list of vehicles should have values from routeA.
    XCTAssertEqual(controller.vehicles.value.map { $0.identifier }.sorted(), ["v1", "v2", "v3"])
  }
}
