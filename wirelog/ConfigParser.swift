//
//  ConfigParser.swift
//  wirelogd
//
//  Created by Noah Desch on 9/2/19.
//  Copyright © 2019 Noah Desch. All rights reserved.
//

import Foundation
import os
import Network


/// Class for reading and retrieving log configurations
class Configuration {
    
    /// Describes the log target of an individual regex subexpression match
    ///
    /// - timestamp: Subexpression matches device timestamp
    /// - host: Subexpression matches device host name
    /// - category: Subexpression matches log category
    /// - message: Subexpression matches log message
    enum Target {
        case timestamp
        case host
        case category
        case message
        
        init?(from string: String) {
            switch string {
            case "timestamp":
                self = .timestamp
            case "host":
                self = .host
            case "category":
                self = .category
            case "message":
                self = .message
            default:
                return nil
            }
        }
    }
    
    /// Describes how to parse different fields from a syslog string using a regular expression and a list of targets for the regex sub-expression captures
    struct Spec {
        let regex: NSRegularExpression
        var captureList: [Target]
        
        init?<T: StringProtocol>(from str: T) {
            var tmpRegex: NSRegularExpression? = nil
            var tmpCaptureList = [Target]()
            let lines = str.split(separator: "\n")
            
            for line in lines {
                let line = line.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                if line.count > 0 {
                    if tmpRegex == nil {
                        do {
                            tmpRegex = try NSRegularExpression(pattern: line, options: [])
                        } catch {
                            fatalError("Unable to parse regex: \"\(line)\"")
                        }
                    } else {
                        if let target = Target(from: line) {
                            tmpCaptureList += [target]
                        } else {
                            fatalError("Invalid log target: \"\(line)\"")
                        }
                    }
                }
            }
            
            self.regex = tmpRegex!
            self.captureList = tmpCaptureList
        }
        
        init(regex: NSRegularExpression, captureList: [Target]) {
            self.regex = regex
            self.captureList = captureList
        }
    }
    
    /// Log Specs for IPv4 hosts
    static private var ipv4HostSpecs = [IPv4Address: Spec]()
    
    /// Log Specs for IPv6 hosts
    static private var ipv6HostSpecs = [IPv6Address: Spec]()
    
    /// Log Specs for named hosts
    static private var namedHostSpecs = [String: Spec]()
    
    /// Default log Spec for unspecified hosts
    static private(set) var defaultSpec = Spec(
        regex: try! NSRegularExpression(pattern: #"<\d+>\s*(.+)"#, options: []),
        captureList: [.message]
    )
    
    
    /// Retrieve log Spec for given host address
    ///
    /// - Parameter addr: the address (IPv4 or IPv6) of the host
    /// - Returns: The log spec for formatting logs from this host, or the default spec if host address not found
    static func logSpec(for host: NWEndpoint.Host) -> Spec {
        switch (host) {
        case .ipv4(let addr):
            return ipv4HostSpecs[addr] ?? defaultSpec
        case .ipv6(let addr):
            return ipv6HostSpecs[addr] ?? defaultSpec
        case .name(let name, _):
            return namedHostSpecs[name] ?? defaultSpec
        @unknown default:
            os_log(.error, log: cfgFileLogCtx, "Unknown host type: %{public}s), using default log spec", host.debugDescription)
            return defaultSpec
        }
    }
    
    
    /// Parse config from file
    ///
    /// - Parameter file: URL of the config file to read
    static func parse(_ file: URL) {
        guard let str = try? String(contentsOf: file) else {
            os_log(.error, log: cfgFileLogCtx, "Unable to read config file: %{public}", file.absoluteString)
            exit(-2)
        }
        
        var searchPos = str.startIndex
        while(true) {
            // find the next log spec in between curly braces {...}
            guard let specStart = str[searchPos...].firstIndex(of: "{") else { break }
            guard let specEnd = str[specStart...].firstIndex(of: "}") else {
                os_log(.error, log: cfgFileLogCtx, "Unmatched \"{\" in config file: %{public}", file.absoluteString)
                exit(-3)
            }
            
            // parse the log spec
            guard let logSpec = Spec(from: str[str.index(after: specStart)..<specEnd]) else {
                os_log(.error, log: cfgFileLogCtx, "Malformed log spec in config file: %{public}", file.absoluteString)
                exit(-4)
            }
            
            // assign the log spec to the IP addresses on following lines
            let hostEndPos = str[specEnd...].firstIndex(of: "{") ?? str.endIndex
            
            assign(spec: logSpec, toHosts: str[specEnd...hostEndPos])
            searchPos = hostEndPos
        }
    }
    
    private static func assign(spec: Spec, toHosts hostBlock: Substring) {
        let lines = hostBlock.split(separator: "\n")
        
        for line in lines {
            let line = line.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            if line.count > 0 {
                if let addr = IPv4Address(line) {
                    ipv4HostSpecs[addr] = spec
                    os_log(.info, log: cfgFileLogCtx, "Assigned log spec for host: %{public}s", addr.debugDescription)
                } else if let addr = IPv6Address(line) {
                    ipv6HostSpecs[addr] = spec
                    os_log(.info, log: cfgFileLogCtx, "Assigned log spec for host: %{public}s", addr.debugDescription)
                } else if line == "*" {
                    defaultSpec = spec
                    os_log(.info, log: cfgFileLogCtx, "Assigned default log spec")
                } else if line.count > 1 {
                    namedHostSpecs[line] = spec
                    os_log(.info, log: cfgFileLogCtx, "Assigned log spec for host: %{public}s", line)
                }
            }
        }
    }
}
