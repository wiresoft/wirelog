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

let networkLogCtx = OSLog(subsystem: "com.wireframesoftware.wirelog", category: "Network")
let cfgFileLogCtx = OSLog(subsystem: "com.wireframesoftware.wirelog", category: "Config")
let parsingLogCtx = OSLog(subsystem: "com.wireframesoftware.wirelog", category: "Parsing")


let listenQueue = DispatchQueue.main
let loggingQueue = DispatchQueue(label: "com.wireframesoftware.wirelog.logging", qos: .background, attributes: [], autoreleaseFrequency: .workItem, target: nil)

let listener: NWListener
var connections = [LogReceiver]()


os_log(.info, log: cfgFileLogCtx, "Reading config file...")
Configuration.parse(URL(fileURLWithPath: CommandLine.arguments[1]))

os_log(.info, log: networkLogCtx, "Starting UDP listener on port 514...")
do {
    let parameters = NWParameters(dtls: nil, udp: NWProtocolUDP.Options())
    parameters.prohibitedInterfaceTypes = [.cellular]
    parameters.acceptLocalOnly = true
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
        connections += [LogReceiver(connection: con)]
    }
    
    listener.start(queue: listenQueue)
    
} catch {
    os_log(.error, log: networkLogCtx, "Unable to create UDP listener on port 514")
    exit(-1)
}

/// Start the run-loop so we stay open
RunLoop.main.run();
