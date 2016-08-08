//
//  Route.swift
//  Proper
//
//  Created by Elliott Williams on 7/3/16.
//  Copyright © 2016 Elliott Williams. All rights reserved.
//

import Foundation
import Argo
import Curry

struct Route: Model {
    typealias Identifier = String

    // Attributes
    let shortName: String
    let code: Int?
    let name: String?
    let description: String?
    let color: UIColor?
    let path: [Point]?
    
    // Associated objects
    let stations: [Station]?
    let vehicles: [Vehicle]?

    let itinerary: [Station]?

    static var namespace: String { return "routes" }
    static var fullyQualified: String { return "Shark::Route" }
    var identifier: Identifier { return self.shortName }
    var topic: String { return Route.topicFor(self.identifier) }
}

extension Route {
    init(id shortName: String) {
        self.init(shortName: shortName, code: nil, name: nil, description: nil, color: nil,
                  path: nil, stations: nil, vehicles: nil, itinerary: nil)
    }
}

extension Route: Decodable {
    static func decode(json: JSON) -> Decoded<Route> {
        switch json {
        case .String(let id):
            let shortName = Route.unqualify(namespaced: id)
            return pure(Route(id: shortName))
        default:
            let r = curry(Route.init)
                <^> (json <| "short_name").or(Route.decodeNamespacedIdentifier(json))
                <*> json <|? "code"
            return r
                <*> json <|? "name"
                <*> json <|? "description"
                <*> json <|? "color"
                <*> json <||? "path"
                // See shark#12 for discussion on which stations attribute should be used.
                <*> json <||? ["associated_objects", Station.fullyQualified]
                <*> json <||? ["associated_objects", Vehicle.fullyQualified]
                <*> json <||? "stations"
        }

    }
}