//
//  VusionModels.swift
//  RetailBrainSDK
//
//  Created by ajith.a.s on 16/07/26.
//

import Foundation

struct BeaconAnchor: Decodable {
    let id: String
    let type: String
    let location: AnchorLocation
}

struct AnchorLocation: Decodable {
    let aisleName: String?
    let modularName: String?
    let floorName: String?
}


struct AnchorsResponse: Decodable {
    let anchors: [BeaconAnchor]
    let beaconingEndDate: Date?
}

 struct EnvContext {
    let env: AppEnv
    let storeId: String
}


enum APIServiceError: LocalizedError {
    case missingEnvironment
    case invalidStoreId
    case invalidResponse
    case invalidData
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingEnvironment:
            return "Missing Config.env in app bundle."
        case .invalidStoreId:
            return "Invalid storeId in Config.env."
        case .invalidResponse:
            return "Invalid response from server."
        case .invalidData:
            return "Invalid data returned by server."
        case .requestFailed(let message):
            return "Request failed: \(message)"
        }
    }
}


enum BeaconingError: LocalizedError {
    case missingEnvironment
    case invalidStoreId
    case invalidRegion
    case sdkUnavailable
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingEnvironment:
            return "Missing Config.env in app bundle."
        case .invalidStoreId:
            return "Invalid storeId in Config.env."
        case .invalidRegion:
            return "Invalid region value."
        case .sdkUnavailable:
            return "VusionSDK is not available in this build."
        case .requestFailed(let message):
            return message
        }
    }
}

