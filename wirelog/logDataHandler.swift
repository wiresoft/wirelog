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

class LogReceiver {
    
    let formatter: NSRegularExpression
    
    let connection: NWConnection
    
    /// Creates a new log receiver for a specific connection.
    ///
    /// - precondition: The connection is already started
    ///
    /// - Parameters:
    ///   - connection: The connection from which to receive data
    ///   - log: The log object for categorizing output
    init(connection: NWConnection) {
        self.connection = connection
        
        // for debugging only:
        do {
            self.formatter = try NSRegularExpression(pattern: #"<(\d+)>\s?(.{15})\s(\w+)\s([^\s:]+)\s?:?\s?(.+)"#, options: [])
        } catch {
            os_log(.error, log: cfgFileLogCtx, "Unable to compile regex")
            exit(-1)
        }
        //////////////////////
        
        self.recieve()
    }
    
    private func recieve() {
        self.connection.receiveMessage { [weak self] (data: Data?, ctx: NWConnection.ContentContext?, isComplete: Bool, error: NWError?) in
            if let data = data {
                self?.networkLog(data)
            }
            self?.recieve()
        }
    }
    
    func networkLog(_ data: Data) {
        guard let str = String(bytes: data, encoding: .utf8) else { return }
        
        let searchRange = NSRange(str.startIndex..., in: str)
        if let result = self.formatter.firstMatch(in: str, options: [], range: searchRange) {
            //let pri = str[Range(result.range(at: 1), in: str)!]
            //let timestamp = str[Range(result.range(at: 2), in: str)!]
            let host = str[Range(result.range(at: 3), in: str)!]
            let app = str[Range(result.range(at: 4), in: str)!]
            let msg = str[Range(result.range(at: 5), in: str)!]
            
            let hostCtx = OSLog(subsystem: "local." + String(host), category: String(app))
            os_log(.default, log: hostCtx, "%{public}s", String(msg))
            
        } else {
            os_log(.error, log: parsingLogCtx, "Unmatched msg: %{public}s", str)
        }
    }
}

