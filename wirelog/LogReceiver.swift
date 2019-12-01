//
//  logDataHandler.swift
//  wirelogd
//
//  Created by Noah Desch on 9/2/19.
//  Copyright © 2019 Noah Desch. All rights reserved.
//

import Foundation
import os
import Network

let networkLogCtx = OSLog(subsystem: "com.wireframesoftware.wirelog", category: "Network")
let parsingLogCtx = OSLog(subsystem: "com.wireframesoftware.wirelog", category: "Parsing")

class LogReceiver {
    
    /// The formatter for this connection
    let formatter: Configuration.Spec
    
    /// The connection object for this log receiver
    let connection: NWConnection
    
    /// If the log format doesn't define a host field, use this instead
    let defaultHost: String
    
    /// Creates a new log receiver for a specific connection.
    ///
    /// - precondition: The connection is already started
    ///
    /// - Parameters:
    ///   - connection: The connection from which to receive data
    init?(connection: NWConnection) {
        self.connection = connection
        
        switch (connection.endpoint) {
        case .hostPort(host: let host, port: _):
            self.formatter = Configuration.logSpec(for: host)
            switch (host) {
            case .ipv4(let addr):
                self.defaultHost = "local.address(\(addr.debugDescription))"
            case .ipv6(let addr):
                self.defaultHost = "local.address(\(addr.debugDescription))"
            case .name(let name, _):
                self.defaultHost = name
            @unknown default:
                self.defaultHost = "<unknown>"
                os_log(.error, log: networkLogCtx, "Unknown host type: %{public}s), using default log spec", connection.endpoint.debugDescription)
            }
        default:
            os_log(.fault, log: networkLogCtx, "Non-network host: %{public}s), ignoring", connection.endpoint.debugDescription)
            return nil
        }
        
        self.recieve()
    }
    
    /// Asynchronously wait for log data to be recevied and parse the data (returns immediately)
    private func recieve() {
        self.connection.receiveMessage { [weak self] (data: Data?, ctx: NWConnection.ContentContext?, isComplete: Bool, error: NWError?) in
            if let data = data {
                self?.networkLog(data)
            }
            self?.recieve()
        }
    }
    
    /// Parse and log the recevied data
    ///
    /// - Parameter data: Raw UDP data recevied from logging host
    private func networkLog(_ data: Data) {
        guard let str = String(bytes: data, encoding: .utf8) else { return }
        
        let searchRange = NSRange(str.startIndex..., in: str)
        if let result = self.formatter.regex.firstMatch(in: str, options: [], range: searchRange) {
            
            // parsed log fields
            var host = self.defaultHost
            var category = ""
            var timestamp: String? = nil
            var msg: String? = nil
            
            // loop through sub expressions and assign to log fields based on Configuration Spec
            for (matchIndex, target) in zip(1..., self.formatter.captureList) {
                let field = str[Range(result.range(at: matchIndex), in: str)!]
                switch (target) {
                case .category:
                    category = String(field)
                case .host:
                    host = "local." + String(field)
                case .timestamp:
                    timestamp = String(field)
                case .message:
                    msg = String(field)
                }
            }
            
            // Log the message if it exists
            if let msg = msg {
                let hostCtx = OSLog(subsystem: host, category: category)
                if let timestamp = timestamp {
                    os_log(.default, log: hostCtx, "[%{public}s] %{public}s", timestamp, String(msg))
                } else {
                    os_log(.default, log: hostCtx, "%{public}s", String(msg))
                }
            }
        } else {
            os_log(.error, log: parsingLogCtx, "Unmatched msg from [%{public}s]: %{public}s", self.connection.endpoint.debugDescription, str)
        }
    }
}

