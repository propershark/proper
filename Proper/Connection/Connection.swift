//
//  Connection.swift
//  Proper
//
//  Created by Elliott Williams on 6/19/16.
//  Copyright © 2016 Elliott Williams. All rights reserved.
//

import UIKit
import MDWamp
import ReactiveSwift
import Result

class Connection: NSObject, MDWampClientDelegate, ConnectionType {
    
    static var sharedInstance = Connection.init()
    
    // Produces signals that passes the MDWamp object when it is available, and that handles reconnections transparently.
    lazy var producer: SignalProducer<MDWamp, ProperError> = self.connectionProducer()
    
    private static let maxConnectionFailures = 5
    private var observer: Observer<MDWamp, ProperError>?

    // MARK: Startup
    
    // Lazy evaluator for self.producer
    func connectionProducer() -> SignalProducer<MDWamp, ProperError> {
        NSLog("opening connection to wamp router")
        let (signal, observer) = Signal<MDWamp, ProperError>.pipe()
        let producer = SignalProducer(signal).replayLazily(upTo: 1)
        
        // Set the instance observer and connect
        self.observer = observer
        let ws = MDWampTransportWebSocket(server: Config.connection.server as URL!,
                                          protocolVersions: [kMDWampProtocolWamp2msgpack, kMDWampProtocolWamp2json])
        let wamp = MDWamp(transport: ws, realm: Config.connection.realm, delegate: self)
        wamp?.connect()
        
        // Return a producer that retries for awhile on in the event of a connection failure...
        return producer
        .retry(upTo: Connection.maxConnectionFailures).flatMapError() { _ in
            NSLog("connection failure after \(Connection.maxConnectionFailures) retries")
            return SignalProducer(error: .maxConnectionFailures)
        }
        // ...and logs all events for debugging
        .logEvents(identifier: "Connection.connectionProducer", logger: logSignalEvent)
    }

    // MARK: Communication Methods

    /// Subscribe to `topic` and forward parsed events. Disposing of signals created from this method will unsubscribe
    /// `topic`.
    func subscribe(to topic: String) -> EventProducer {
        return self.producer
            .map { wamp in wamp.subscribeWithSignal(topic) }
            .flatten(.latest)
            .map { TopicEvent.parse(from: topic, event: $0) }
            .unwrapOrSendFailure(ProperError.eventParseFailure)
            .logEvents(identifier: "Connection.subscribe", logger: logSignalEvent)
    }

    /// Call `proc` and forward the result. Disposing the signal created will cancel the RPC call.
    func call(_ proc: String, with args: WampArgs = [], kwargs: WampKwargs = [:]) -> EventProducer {
        return self.producer.map({ wamp in
            wamp.callWithSignal(proc, args, kwargs, [:])
                .timeout(after: 10.0, raising: .timeout, on: QueueScheduler.main)
            })
            .flatten(.latest)
            .map { TopicEvent.parse(fromRPC: proc, args, kwargs, $0) }
            .unwrapOrSendFailure(ProperError.eventParseFailure)
    }

    // MARK: MDWamp Delegate
    func mdwamp(_ wamp: MDWamp!, sessionEstablished info: [AnyHashable: Any]!) {
        NSLog("session established")
        self.observer?.send(value: wamp)
    }
    
    func mdwamp(_ wamp: MDWamp!, closedSession code: Int, reason: String!, details: WampKwargs!) {
        NSLog("session closed, reason: \(reason)")

        // MDWamp uses the `explicit_closed` key to indicate a deliberate failure.
        if reason == "MDWamp.session.explicit_closed" {
            self.observer?.sendCompleted()
            return
        }
        
        // Otherwise, it is assumed that the session closed due to an error.
        self.observer?.send(error: .connectionLost(reason: reason))
    }
}

// MARK: MDWamp Extensions
extension MDWamp {
    /// Follows semantics of `call` but returns a signal producer, rather than taking a result callback.
    func callWithSignal(_ procUri: String, _ args: WampArgs, _ argsKw: WampKwargs, _ options: [AnyHashable: Any])
        -> SignalProducer<MDWampResult, ProperError>
    {
        return SignalProducer<MDWampResult, ProperError> { observer, _ in
            NSLog("Calling \(procUri)")
            self.call(procUri, args: args, kwArgs: argsKw, options: options) { result, error in
                if error != nil {
                    observer.send(error: .mdwampError(topic: procUri, object: error))
                    return
                }
                observer.send(value: result!)
                observer.sendCompleted()
            }
        }.logEvents(identifier: "MDWamp.callWithSignal", logger: logSignalEvent)
    }
    
    func subscribeWithSignal(_ topic: String) -> SignalProducer<MDWampEvent, ProperError> {
        return SignalProducer<MDWampEvent, ProperError> { observer, disposable in
            self.subscribe(
                topic,
                options: nil,
                onEvent: { event in event.map(observer.send(value:)) },
                result: { error in
                    NSLog("Subscribed to \(topic)")
                    if error != nil { observer.send(error: .mdwampError(topic: topic, object: error)) }
                }
            )
            disposable.add {
                self.unsubscribe(topic) { error in
                    NSLog("Unsubscribed from \(topic)")
                    if error != nil { observer.send(error: .mdwampError(topic: topic, object: error)) }
                }
            }
        }.logEvents(identifier: "MDWamp.subscribeWithSignal", logger: logSignalEvent)
    }
}
