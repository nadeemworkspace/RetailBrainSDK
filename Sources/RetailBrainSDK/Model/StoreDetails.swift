//
//  StoreDetails.swift
//  RetailBrainSDK
//
//  Created by ajith.a.s on 24/06/26.
//

import Foundation

public struct StoreDetails: Identifiable {
    public let id = UUID()
    public let name: String
    public let imageName: String
    public let locationName: String
    public let spaceId: String?
    public let coordinates: (Double, Double)?
    
    public init(from storeItem: StoreItem, coordinates: (Double, Double)? = nil) {
        self.name = storeItem.name
        self.imageName = storeItem.imageName
        self.locationName = storeItem.locationName
        self.spaceId = storeItem.spaceId
        self.coordinates = coordinates
    }
    
    public init(name: String, imageName: String, locationName: String, spaceId: String? = nil, coordinates: (Double, Double)? = nil) {
        self.name = name
        self.imageName = imageName
        self.locationName = locationName
        self.spaceId = spaceId
        self.coordinates = coordinates
    }
}
