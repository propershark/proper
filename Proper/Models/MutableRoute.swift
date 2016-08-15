//
//  MutableRoute.swift
//  Proper
//
//  Created by Elliott Williams on 7/10/16.
//  Copyright © 2016 Elliott Williams. All rights reserved.
//

import Foundation
import ReactiveCocoa
import Result
import Argo

class MutableRoute: MutableModel {
    typealias FromModel = Route

    // MARK: Internal Properties
    internal let connection: ConnectionType
    internal var delegate: MutableModelDelegate
    private static let retryAttempts = 3

    // MARK: Route Support
    var identifier: FromModel.Identifier { return self.shortName }
    var topic: String { return FromModel.topicFor(self.identifier) }

    // MARK: Route Attributes
    let shortName: FromModel.Identifier
    var code: MutableProperty<Int?> = .init(nil)
    var name: MutableProperty<String?> = .init(nil)
    var description: MutableProperty<String?> = .init(nil)
    var color: MutableProperty<UIColor?> = .init(nil)
    var path:  MutableProperty<[Point]?> = .init(nil)
    var stations: MutableProperty<Set<MutableStation>?> = .init(nil)
    var vehicles: MutableProperty<Set<MutableVehicle>?> = .init(nil)
    var itinerary: MutableProperty<[MutableStation]?> = .init(nil)

    // MARK: Signal Producer
    lazy var producer: SignalProducer<TopicEvent, PSError> = {
        let now = self.connection.call("meta.last_event", args: [self.topic, self.topic])
        let future = self.connection.subscribe(self.topic)
        return SignalProducer<SignalProducer<TopicEvent, PSError>, PSError>(values: [now, future])
            .flatten(.Merge)
            .logEvents(identifier: "MutableRoute.producer", logger: logSignalEvent)
            .attempt { event in
                if let error = event.error {
                    return .Failure(PSError(code: .decodeFailure, associated: error))
                }

                switch event {
                case .Route(.update(let route, _)):
                    do {
                        try self.apply(route.value!)
                    } catch {
                        return .Failure(error as? PSError ?? PSError(code: .mutableModelFailedApply))
                    }
                case .Route(.vehicleUpdate(let vehicle, _)):
                    self.handleEvent(vehicleUpdate: vehicle.value!)
                default:
                    self.delegate.mutableModel(self, receivedTopicEvent: event)
                }
                return .Success()
            }
    }()

    // MARK: Functions
    required init(from route: Route, delegate: MutableModelDelegate, connection: ConnectionType)
    {
        self.shortName = route.shortName
        self.delegate = delegate
        self.connection = connection
        try! apply(route)

        // Create back-references to this MutableRoute on all vehicles associated with the route. 
        self.vehicles.producer.ignoreNil().flatten(.Latest).startWithNext { [weak self] vehicle in
            vehicle.route.modify { $0 ?? self }
        }
    }

    func apply(route: Route) throws {
        if route.identifier != self.identifier {
            throw PSError(code: .mutableModelFailedApply)
        }

        self.name <- route.name
        self.code <- route.code
        self.description <- route.description
        self.color <- route.color
        self.path <-| route.path

        try applyChanges(to: self.stations, from: route.stations)
        try applyChanges(to: self.vehicles, from: route.vehicles)

        // Map the station stubs in `route.stations` to mutables in `self.stations`, then update the itinerary property
        // if objects or ordering has changed.
        if let itinerary = try route.stations.map(mappedItinerary) where itinerary != self.itinerary.value! {
            self.itinerary.swap(itinerary)
        }
    }

    /// Map an itinerary of static Stations to MutableStations contained by this object's `stations` set.
    func mappedItinerary(source: [Station]) throws -> [MutableStation] {
        guard let mutables = self.stations.value else {
            throw PSError(code: .modelStateInconsistency, associated: "Expected a set of stations to be defined on this MutableRoute")
        }
        let dict: [Station.Identifier: MutableStation] = mutables.reduce([:]) { dict, station in
            var dict = dict
            dict[station.identifier] = station
            return dict
        }
        return try source.map { station in
            guard let mutable = dict[station.identifier] else {
                throw PSError(code: .modelStateInconsistency, associated: "Expected mutable for \(station.identifier) to exist in the set")
            }
            return mutable
        }
    }

    func condensedRoute() {

    }

    // MARK: Event Handlers

    /// If any vehicles on this route match `vehicle`, update their information to match `vehicle`.
    func handleEvent(vehicleUpdate vehicle: Vehicle) {
        self.vehicles.value?.filter { $0 == vehicle }.forEach { $0.apply(vehicle) }
    }
}
