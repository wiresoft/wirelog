//
//  Wirelog_Tests.swift
//  Wirelog Tests
//
//  Created by Noah Desch on 11/22/19.
//  Copyright © 2019 Noah Desch. All rights reserved.
//

import XCTest
import Network

class Wirelog_Tests: XCTestCase {
    
    let myBundle = Bundle(for: Wirelog_Tests.self)

    override func setUp() {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testConfigParser() {
        guard let input = NSDataAsset(name: .basicConfigFile, bundle: myBundle)?.data else {
            XCTFail("Unable to load test data file")
            return
        }
        guard let configStr = String(data: input, encoding: .utf8) else {
            XCTFail("Unable to load test data file")
            return
        }
        
        // parse the config
        Configuration.parse(configStr)
        
        // check the nicknames
        XCTAssert(Configuration.nickname(for: "local.U7HD,abcdef123456") == "Alias 1")
        XCTAssert(Configuration.nickname(for: "$$$Real host name$$$") == "$$$Alias2$$$")
        
        // check the first host spec
        let pattern1 = #"<\d+>\s?.{15}\s(\w+)\s([^\s:]+)\s?:?\s?(.+)"#
        let host1 = NWEndpoint.Host.ipv4(IPv4Address("10.10.250.1")!)
        let spec1 = Configuration.logSpec(for: host1)
        XCTAssert(spec1.regex.pattern == pattern1)
        XCTAssert(spec1.captureList.count == 3)
        XCTAssert(spec1.captureList[0] == .host)
        XCTAssert(spec1.captureList[1] == .category)
        XCTAssert(spec1.captureList[2] == .message)
        
        let host2 = NWEndpoint.Host.ipv6(IPv6Address("2600:6f64:cc08:40::1")!)
        let spec2 = Configuration.logSpec(for: host2)
        XCTAssert(spec2.regex.pattern == pattern1)
        XCTAssert(spec2.captureList.count == 3)
        XCTAssert(spec2.captureList[0] == .host)
        XCTAssert(spec2.captureList[1] == .category)
        XCTAssert(spec2.captureList[2] == .message)
        
        let host3 = NWEndpoint.Host.ipv4(IPv4Address("10.10.250.2")!)
        let spec3 = Configuration.logSpec(for: host3)
        XCTAssert(spec3.regex.pattern == pattern1)
        XCTAssert(spec3.captureList.count == 3)
        XCTAssert(spec3.captureList[0] == .host)
        XCTAssert(spec3.captureList[1] == .category)
        XCTAssert(spec3.captureList[2] == .message)
        
        let host4 = NWEndpoint.Host.ipv6(IPv6Address("2600:6f64:cc08:40::2")!)
        let spec4 = Configuration.logSpec(for: host4)
        XCTAssert(spec4.regex.pattern == pattern1)
        XCTAssert(spec4.captureList.count == 3)
        XCTAssert(spec4.captureList[0] == .host)
        XCTAssert(spec4.captureList[1] == .category)
        XCTAssert(spec4.captureList[2] == .message)
        
        // check the second host spec
        let pattern2 = #"<\d+>\s?.{15}\s(\w+,\w+)[^:]*:\s([^\s:]*):\s?(.+)"#
        let host5 = NWEndpoint.Host.ipv4(IPv4Address("10.10.250.27")!)
        let spec5 = Configuration.logSpec(for: host5)
        XCTAssert(spec5.regex.pattern == pattern2)
        XCTAssert(spec5.captureList.count == 3)
        XCTAssert(spec5.captureList[0] == .host)
        XCTAssert(spec5.captureList[1] == .category)
        XCTAssert(spec5.captureList[2] == .message)
        
        let host6 = NWEndpoint.Host.ipv4(IPv4Address("10.10.250.54")!)
        let spec6 = Configuration.logSpec(for: host6)
        XCTAssert(spec6.regex.pattern == pattern2)
        XCTAssert(spec6.captureList.count == 3)
        XCTAssert(spec6.captureList[0] == .host)
        XCTAssert(spec6.captureList[1] == .category)
        XCTAssert(spec6.captureList[2] == .message)
    }
}

extension NSDataAsset.Name {
    static let basicConfigFile = NSDataAsset.Name("BasicConfig")
}
