//
//  RetailBrainConfig.swift
//  RetailBrainSDK
//
//  Created by ajith.a.s on 23/06/26.
//

import Foundation

public struct RetailBrainConfig {
    
    public let apiKey: String
    public let apiSecret: String
    public let mapId: String
    
    public init(
        apiKey: String,
        apiSecret: String,
        mapId: String
    ) {
        self.apiKey = apiKey
        self.apiSecret = apiSecret
        self.mapId = mapId
    }
}
