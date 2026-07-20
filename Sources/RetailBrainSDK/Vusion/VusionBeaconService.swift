//
//  VusionBeaconService.swift
//  RetailBrainSDK
//
//  Created by ajith.a.s on 16/07/26.
//


import Foundation
import Combine
import OSLog
import VusionSDK


final class BeaconingService: NSObject, ObservableObject, IEdgeSenseDeviceLight {
    static let shared = BeaconingService()
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TestSDKiOSBeaconing", category: "BeaconingService")
    
    @Published private(set) var isInitialized: Bool = false
    @Published private(set) var lastDeviceId: String = ""
    @Published private(set) var lastRssi: Int = 0
    @Published private(set) var lastAisleName: String = ""
    @Published private(set) var lastAisleDeviceId: String = ""
    @Published private(set) var lastAisleRssi: Int = 0
    @Published private(set) var lastModularName: String = ""
    @Published private(set) var lastModularDeviceId: String = ""
    @Published private(set) var lastModularRssi: Int = 0
    @Published private(set) var lastModularAisleName: String = ""
    @Published private(set) var logs: [String] = []
    
    private var geolocationing: GeoLocationingDevice?
    private(set) var anchors: [BeaconAnchor] = []
    private var anchorsById: [String: BeaconAnchor] = [:]
    private(set) var beaconingEndDate: Date?
    var items: [BeaconNeighbour] = []
    private var simulationTask: Task<Void, Never>?
    
    func initializeSDK() throws {
        if geolocationing != nil {
            isInitialized = true
            Self.logger.info("SDK already initialized")
            return
        }

        guard let env = AppEnv.current else {
            Self.logger.error("Missing SDK Configuration")
            throw BeaconingError.missingEnvironment
        }

        let storeId = env.storeId.trimmingCharacters(in: .whitespacesAndNewlines)
        let regionRaw = env.region.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !storeId.isEmpty else {
            Self.logger.error("Invalid storeId in SDK Configuration")
            throw BeaconingError.invalidStoreId
        }

        guard let region = GeoLocationingRegion.fromValue(regionRaw) else {
            Self.logger.error("Invalid region in SDK Configuration: \(regionRaw, privacy: .public)")
            throw BeaconingError.invalidRegion
        }

        var geolocProperties = GeolocationingProperties()
        
        geolocProperties.setRegion(region)
        geolocProperties.setStoreId(storeId)

        geolocationing = GeoLocationingDevice(callback: self, geolocProperties: geolocProperties)
        
        guard let geolocationing else {
            throw BeaconingError.sdkUnavailable
        }
        geolocationing.locateMe(beacons: items)
        isInitialized = true
        Self.logger.info("SDK initialized with storeId=\(storeId, privacy: .public) and region=\(regionRaw, privacy: .public)")
    }

    func startBeaconing() async throws {
        let response = try await APIService.shared.fetchAnchors()

        anchors = response.anchors
        let geoAnchors = anchors.map { anchor in
            GeoLocationingAnchor(
                id: anchor.id.trimmingCharacters(in: .whitespacesAndNewlines),
                type: anchor.type,
                aisleName: anchor.location.aisleName,
                modularName: anchor.location.modularName,
                floorName: anchor.location.floorName
            )
        }
        guard let geolocationing else {
            throw BeaconingError.sdkUnavailable
        }
        _ = try geolocationing.locateMe(anchors: geoAnchors)
    }
    

    func stopBeaconing() throws {
        guard let geolocationing else {
            throw BeaconingError.sdkUnavailable
        }
        geolocationing.stopLocationing()
        Self.logger.info("Service stopped !")
      //  stopSimulation()
    }
    
    @objc
    public func deviceRssiReceived(deviceId: String, rssi: Int) {
        Self.logger.info("Received: \(deviceId), Irssi: \(rssi)")
        let normalizedId = deviceId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let matchingAnchor = anchorsById[normalizedId]
        Task { @MainActor in
            logs.append("Device \(deviceId) - RSSI \(rssi)")
            lastDeviceId = deviceId
            lastRssi = rssi
            /* if let anchor = matchingAnchor {
                updateLocation(from: anchor, deviceId: deviceId, rssi: rssi)
            } else {
                Self.logger.info("No anchor match for deviceId=\(deviceId, privacy: .public)")
            } */
        }
    }

    @MainActor
    private func updateLocation(from anchor: BeaconAnchor, deviceId: String, rssi: Int) {
        let type = anchor.type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let aisleName = anchor.location.aisleName ?? ""
        let modularName = anchor.location.modularName ?? ""

        if type.contains("aisle") || (!aisleName.isEmpty && !type.contains("modular")) {
            lastAisleName = aisleName
            lastAisleDeviceId = deviceId
            lastAisleRssi = rssi
        }

        if type.contains("modular") || !modularName.isEmpty {
            lastModularName = modularName
            lastModularDeviceId = deviceId
            lastModularRssi = rssi
            lastModularAisleName = aisleName
        }
    }
    
    @objc public func nearestModularUpdated(deviceId: String, aisleName: String?, modularName: String?, rssi: Int) {
        // Android implementation is intentionally no-op.
        Task { @MainActor in
            lastModularName = modularName ?? ""
            lastModularDeviceId = deviceId
            lastModularRssi = rssi
            lastModularAisleName = aisleName ?? ""
            lastAisleName = aisleName ?? ""
        }
    }
}
