//
//  NilConnection.swift
//  Proper
//
//  Created by Elliott Williams on 8/4/16.
//  Copyright © 2016 Elliott Williams. All rights reserved.
//

import Foundation
import ReactiveSwift
@testable import Proper

class NilConnection: ConnectionType {
    func call(proc: String, args: WampArgs, kwargs: WampKwargs) -> SignalProducer<TopicEvent, ProperError> {
        // A signal producer that does nothing
        return SignalProducer { _, _ in () }
    }
    func subscribe(topic: String) -> SignalProducer<TopicEvent, ProperError> {
        return SignalProducer { _, _ in () }
    }
}
