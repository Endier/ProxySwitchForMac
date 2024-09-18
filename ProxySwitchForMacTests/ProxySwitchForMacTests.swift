//
//  ProxySwitchForMacTests.swift
//  ProxySwitchForMacTests
//
//  Created by Cody on 2024/6/26.
//

import Testing
@testable import ProxySwitchForMac

struct ProxySwitchForMacTests {

    @Test func testExample() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }
    
    @Test func testGetSystemNetworkServiceNames() async throws {
        let serviceNames = getSystemNetworkServiceNames()
        print(serviceNames)
    }
    
    @Test func testStringToHashMap() async throws {
        let result = stringToHashMap(string: "Server: ")
        #expect(result == ["Server": ""])
        
        let result2 = stringToHashMap(string: "Enabled: No")
        #expect(result2 == ["Enabled": "No"])
    }
}
