//
//  main.swift
//  wirelog
//
//  Created by Noah Desch on 9/2/19.
//  Copyright © 2019 Noah Desch. All rights reserved.
//

import Foundation
import os
import Network

/// Log context for program initialization
let startupLogCtx = OSLog(subsystem: "com.wireframesoftware.wirelog", category: "Startup")

/// Listen for incoming messages on the main thread
let listenQueue = DispatchQueue.main

/// Parse and log messages with loq QoS on a background thread
let loggingQueue = DispatchQueue(label: "com.wireframesoftware.wirelog.logging", qos: .background, attributes: [], autoreleaseFrequency: .workItem, target: nil)

let listener: NWListener
var connections = [LogReceiver]()


//
// MARK: - Read Configuration
//
os_log(.info, log: startupLogCtx, "Reading config file...")
guard let configString = try? String(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])) else {
    os_log(.error, log: startupLogCtx, "Unable to read config file: %{public}", CommandLine.arguments[1])
    exit(-2)
}
Configuration.parse(configString)


//
// MARK: - Start the Network Listener
//
os_log(.info, log: startupLogCtx, "Starting UDP listener on port 514...")
do {
    let parameters = NWParameters(dtls: nil, udp: NWProtocolUDP.Options())
    parameters.prohibitedInterfaceTypes = [.cellular]
    parameters.serviceClass = .background
    
    listener = try NWListener(using: parameters, on: 514)
    
    listener.stateUpdateHandler = { (state: NWListener.State) in
        let stateStr: String
        switch (state) {
        case .setup:
            stateStr = "setup"
        case .waiting:
            stateStr = "waiting"
        case .ready:
            stateStr = "ready"
        case .failed:
            stateStr = "failed"
        case .cancelled:
            stateStr = "cancelled"
        default:
            stateStr = "unknown"
        }
        os_log(.info, log: networkLogCtx,  "Listener state changed: %{public}0s", stateStr)
    }
    
    listener.newConnectionHandler = { (con: NWConnection) in
        os_log(.info, log: networkLogCtx, "New connection from: %{public}s", con.endpoint.debugDescription)
        con.stateUpdateHandler = { (state: NWConnection.State) in
            let stateStr: String
            switch (state) {
            case .setup:
                stateStr = "setup"
            case .waiting:
                stateStr = "waiting"
            case .preparing:
                stateStr = "preparing"
            case .ready:
                stateStr = "ready"
            case .failed:
                stateStr = "failed"
            case .cancelled:
                stateStr = "cancelled"
            default:
                stateStr = "unknown"
            }
            os_log(.info, log: networkLogCtx,  "Connection state changed: %{public}0s", stateStr)
        }
        con.start(queue: loggingQueue)
        if let receiver = LogReceiver(connection: con) {
            connections += [receiver]
        }
    }
    
    listener.start(queue: listenQueue)
    
} catch {
    os_log(.error, log: startupLogCtx, "Unable to create UDP listener on port 514")
    exit(-1)
}


//
// MARK: - Start the run-loop so we stay open
//
RunLoop.main.run();
