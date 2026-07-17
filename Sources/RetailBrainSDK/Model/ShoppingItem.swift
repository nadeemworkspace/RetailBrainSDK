//
//  ShoppingItem.swift
//  RetailBrainSDK
//
//  Created by ajith.a.s on 24/06/26.
//

import Foundation

public struct ShoppingItem: Identifiable, Hashable {
    public let id: UUID
    public let name: String
    public let storeName: String
    public let description: String?

    public init(
        id: UUID = UUID(),
        name: String,
        storeName: String,
        description: String? = nil
    ) {
        self.id = id
        self.name = name
        self.storeName = storeName
        self.description = description
    }
}
