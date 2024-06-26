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
    
    func testGetSystemNetworkServiceNames() throws {
        let serviceNames = getSystemNetworkServiceNames()
        print(serviceNames)
    }
}
