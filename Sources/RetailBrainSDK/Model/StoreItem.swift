//
//  StoreItem.swift
//  RetailBrainSDK
//
//  Created by ajith.a.s on 24/06/26.
//

import Foundation

public struct StoreItem: Identifiable, Hashable {
    public let id = UUID()
    public let name: String
    public let imageName: String
    public let locationName: String
    public let spaceId: String?
    
    public init(name: String, imageName: String, locationName: String, spaceId: String? = nil) {
        self.name = name
        self.imageName = imageName
        self.locationName = locationName
        self.spaceId = spaceId
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(locationName)
    }
    
    public static func == (lhs: StoreItem, rhs: StoreItem) -> Bool {
        lhs.locationName == rhs.locationName
    }
}
