//
//  ShoppingItemsProvider.swift
//  RetailBrainSDK
//
//  Created by ajith.a.s on 24/06/26.
//

import Foundation

public class ShoppingItemsProvider {
    public static var shared = ShoppingItemsProvider()

    public var customItems: [ShoppingItem] = []

    public func setCustomItems(_ items: [ShoppingItem]) {
        self.customItems = items
        RetailBrainManager.shared.delegate?.addProductToMap()
    }

    public func getItems() -> [ShoppingItem] {
        return customItems
    }
}
