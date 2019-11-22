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
import Parser

fileprivate func keywordCharacters(_ char: Character) -> Bool {
    return char.isLetter && char.isUppercase
}

fileprivate struct StringNode: SyntaxNode {
    var onSuccess: ((SyntaxNode) -> Void)?
    var text: Substring
    
    var child: SyntaxNode? { fatalError() }
    subscript(index: Int) -> SyntaxNode? { fatalError() }
    
    mutating func parse(from text: inout Substring) -> Bool {
        text.dropWhitespace()
        guard text.hasPrefix("\"") else { return false }
        var tmp = text.dropFirst()
        let contents = tmp.consume(while: {$0 != "\""})
        if tmp.hasPrefix("\"") {
            text = tmp.dropFirst()
            self.text = contents
            return true
        }
        self.text = ""
        return false
    }
    
    var debugDescription: String {
        return "\"\(self.text)\""
    }
    
    init() {
        self.onSuccess = nil
        self.text = ""
    }
}

fileprivate struct IPAddrLiteralNode<Address>: SyntaxNode
    where Address: IPAddress
{
    var onSuccess: ((SyntaxNode) -> Void)?
    var text: Substring
    var child: SyntaxNode? { fatalError() }
    subscript(index: Int) -> SyntaxNode? { fatalError() }
        
    var address: Address?
    
    mutating func parse(from text: inout Substring) -> Bool {
        text.dropWhitespace()
        var tmp = text
        
        let _ = tmp.consume(while: {$0.isHexDigit || $0 == "." || $0 == ":"})
        guard tmp.first?.isWhitespace ?? true else { return false }
        let capture = text.base[text.startIndex...tmp.startIndex]
        
        if let value = Address(String(capture)) {
            self.address = value
            self.text = capture
            text = tmp.dropFirst()
            return true
        }
        self.address = nil
        return false
    }
    
    var debugDescription: String {
        return String(describing: self.text)
    }
    
    init() {
        self.onSuccess = nil
        self.address = nil
        self.text = ""
    }
}

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
    
    /// Nicknames for re-naming hosts
    static private var hostNicknames = [String: String]()
    
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
    
    /// Retrieves the user-specified name for the given logging host name
    /// User can give nicknames to "rename" logging hosts in the log, in case the host name provided by the device is inconvenient.
    ///
    /// - Parameter hostName: Logging host name provided by the log message
    /// - Returns: Name user has chosen for this logging host, or the input string if no nickname was given
    static func nickname(for hostName: String) -> String {
        return hostNicknames[hostName] ?? hostName
    }
    
    
    /// Parse config from file
    ///
    /// - Parameter file: URL of the config file to read
    static func parse(_ file: URL) {
        guard let configString = try? String(contentsOf: file) else {
            os_log(.error, log: cfgFileLogCtx, "Unable to read config file: %{public}", file.absoluteString)
            exit(-2)
        }
        
        let nicknameLine = Nodes([
            StringNode(),
            StringNode(),
            ], onSuccess: { node in
                guard let lvalue = node[0] else { return }
                guard let rvalue = node[1] else { return }
                self.assign(nickname: String(rvalue.text), to: String(lvalue.text))
        })
        
        let nicknameBlock = Nodes([
            Keyword("NICKNAMES", charCheck: keywordCharacters),
            Char("{"),
            Repeating(nicknameLine, separatedBy: nil),
            Char("}"),
        ])
        
        let formatBlock = Nodes([
            Keyword("FORMAT", charCheck: keywordCharacters),
            Char("{"),
            Nodes([
                Identifier(chars: { !$0.isWhitespace }),
                Repeating(Options([
                    Keyword("timestamp", charCheck: keywordCharacters),
                    Keyword("host", charCheck: keywordCharacters),
                    Keyword("category", charCheck: keywordCharacters),
                    Keyword("message", charCheck: keywordCharacters),
                ]), separatedBy: nil)
            ]),
            Char("}"),
            Repeating(Options([
                Char("*"),
                IPAddrLiteralNode<IPv4Address>(),
                IPAddrLiteralNode<IPv6Address>(),
            ]), separatedBy: nil)
            ], onSuccess: { node in
                guard let node = node as? Nodes else { return }
                guard let fmtNodes = node.nodes[2] as? Nodes else { return }
                guard let hostNodes = node.nodes[4] as? Repeating else { return }
                self.assign(format: fmtNodes, to: hostNodes)
        })
        
        var confFileSyntax = Repeating(Options([
            nicknameBlock,
            formatBlock
        ]), separatedBy: nil)
        
        var confSubstr = configString[...]
        if !confFileSyntax.parse(from: &confSubstr) {
            os_log(.info, log: cfgFileLogCtx, "Error parsing config file")
        }
        confSubstr.dropWhitespace()
        if confSubstr.count > 0 {
            os_log(.error, log: cfgFileLogCtx, "Syntax error in config file starting from:\n%{public}s", String(confSubstr))
        }
    }
    
    /// Assigns the given nickname to the logging host name
    /// - Parameters:
    ///   - nickname: Nickname (name to appear in the log)
    ///   - host: Actual host name as it appears in log messages
    private static func assign(nickname: String, to host: String) {
        hostNicknames[host] = nickname
    }
    
    /// Parses the host IP addresses following a log spec and assignes the given spec to those hosts
    /// - Parameters:
    ///   - spec: The preceeding log spec
    ///   - hostBlock: The block of text containing the host IP addresses
    private static func assign(format: Nodes, to hosts: Repeating) {
        guard let regexNode = format.nodes[0] as? NonEmptyLineNode else { fatalError("Unexpected node type") }
        guard let repeatingCaptures = format.nodes[1] as? Repeating else { fatalError("Unexpected node type") }
        let regexPattern = String(regexNode.value)
        
        do {
            let tmpRegex = try NSRegularExpression(pattern: regexPattern, options: [])
        } catch {
            fatalError("Unable to parse regex: \"\(regexPattern)\"")
        }
        
        for node in format.nodes.dropFirst() {
            guard let node = node as?
        }
        
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
