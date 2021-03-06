//
//  MutableVehicle.swift
//  Proper
//
//  Created by Elliott Williams on 7/10/16.
//  Copyright © 2016 Elliott Williams. All rights reserved.
//

import Foundation
import ReactiveSwift
import Curry
import Result
import Argo

class MutableVehicle: MutableModel, Comparable {
  typealias FromModel = Vehicle
  typealias StationType = MutableStation
  typealias RouteType = MutableRoute

  // MARK: Internal Properties
  internal let connection: ConnectionType
  private static let retryAttempts = 3

  // MARK: Vehicle Support
  var identifier: FromModel.Identifier { return self.name }
  var topic: String { return Vehicle.topic(for: self.identifier) }

  // MARK: Vehicle Attributes
  let name: FromModel.Identifier
  var code: MutableProperty<Int?> = .init(nil)
  var position: MutableProperty<Point?> = .init(nil)
  var capacity: MutableProperty<Int?> = .init(nil)
  var onboard: MutableProperty<Int?> = .init(nil)
  var saturation: MutableProperty<Double?> = .init(nil)
  var lastStation: MutableProperty<StationType?> = .init(nil)
  var nextStation: MutableProperty<StationType?> = .init(nil)
  var route: MutableProperty<RouteType?> = .init(nil)
  var scheduleDelta: MutableProperty<Double?> = .init(nil)
  var heading: MutableProperty<Double?> = .init(nil)
  var speed: MutableProperty<Double?> = .init(nil)

  // MARK: Signal Producer
  lazy var producer: SignalProducer<TopicEvent, ProperError> = {
    let now = self.connection.call("meta.last_event", with: [self.topic, self.topic])
    let future = self.connection.subscribe(to: self.topic)
    return SignalProducer<SignalProducer<TopicEvent, ProperError>, ProperError>([now, future])
      .flatten(.merge)
      .logEvents(identifier: "MutableVehicle.producer", logger: logSignalEvent)
      .attempt(operation: self.handle)
  }()

  // MARK: Functions
  required init(from vehicle: Vehicle, connection: ConnectionType) throws {
    self.name = vehicle.name
    self.connection = connection
    try apply(vehicle)
  }

  func handle(event: TopicEvent) -> Result<(), ProperError> {
    if let error = event.error {
      return .failure(.decodeFailure(error))
    }

    return ProperError.capture({
      switch event {
      case .vehicle(.update(let vehicle, _)):
        try self.apply(vehicle.value!)
      default: break
      }
    })
  }

  func apply(_ vehicle: Vehicle) throws {
    if vehicle.identifier != self.identifier {
      throw ProperError.applyFailure(from: vehicle.identifier, onto: self.identifier)
    }

    self.code <- vehicle.code
    self.position <- vehicle.position
    self.capacity <- vehicle.capacity
    self.onboard <- vehicle.onboard
    self.saturation <- vehicle.saturation
    self.scheduleDelta <- vehicle.scheduleDelta
    self.heading <- vehicle.heading
    self.speed <- vehicle.speed

    try attachOrApply(to: lastStation, from: vehicle.lastStation)
    try attachOrApply(to: nextStation, from: vehicle.nextStation)
    try attachOrApply(to: route, from: vehicle.route)
  }

  func snapshot() -> FromModel {
    return Vehicle(name: name, code: code.value, position: position.value, capacity: capacity.value,
                   onboard: onboard.value, saturation: saturation.value,
                   lastStation: lastStation.value?.snapshot(), nextStation: nextStation.value?.snapshot(),
                   route: route.value?.snapshot(), scheduleDelta: scheduleDelta.value, heading: heading.value,
                   speed: speed.value)
  }
}

func < (a: MutableVehicle, b: MutableVehicle) -> Bool {
  return a.name < b.name
}
