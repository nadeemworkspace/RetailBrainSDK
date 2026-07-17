//
//  RetailBrainSDK.swift
//  RetailBrainSDK
//
//  Created by ajith.a.s on 22/06/26.
//

import Foundation

public protocol RetailBrainSDKDelegate: AnyObject {
    func sdkDidInitialize()
    func sdkDidFailToInitialize(error: Error)

    // Map Events
    func mapDidLoad()
    func mapDidFailToLoad(error: Error)

    // Add Product
    func addProductToMap()

    // Item Selection
    func didSelectItem(_ item: StoreItem)
    func didDeselectItem(_ item: StoreItem)

    // Route Events
    func routeCalculationStarted()

    // Marker Events
    func didTapProductPointer(_ product: StoreDetails)
}

public extension RetailBrainSDKDelegate {
    func sdkDidInitialize() {}
    func sdkDidFailToInitialize(error: Error) {}
    func mapDidLoad() {}
    func mapDidFailToLoad(error: Error) {}
    func addProductToMap() {}
    func didSelectItem(_ item: StoreItem) {}
    func didDeselectItem(_ item: StoreItem) {}
    func routeCalculationStarted() {}
    func didTapProductPointer(_ product: StoreDetails) {}
}

public enum RetailBrainSDKError: LocalizedError {
    case invalidConfiguration

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "RetailBrain configuration is invalid."
        }
    }
}

public final class RetailBrainManager {

    public static let shared = RetailBrainManager()

    private init() {}

    public private(set) var config: RetailBrainConfig?
    public weak var delegate: RetailBrainSDKDelegate?

    public func initialize(

        config: RetailBrainConfig

    ) {
        guard !config.apiKey.isEmpty, !config.apiSecret.isEmpty, !config.mapId.isEmpty else {
            let error = RetailBrainSDKError.invalidConfiguration
            delegate?.sdkDidFailToInitialize(error: error)
            print("SDK initialization failed: \(error.localizedDescription)")
            return
        }

        self.config = config
        delegate?.sdkDidInitialize()
        print("Map ID: \(config.mapId)")
        print("Live update")
    }
}
