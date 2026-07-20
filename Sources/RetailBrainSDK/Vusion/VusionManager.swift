//
//  VusionManager.swift
//  RetailBrainSDK
//
//  Created by ajith.a.s on 16/07/26.
//


import Foundation
import Combine
import OSLog

/// Represents different Vusion status events
public struct VusionStatusUpdate {
    public enum Status {
        case initializing
        case initialized
        case trackingLocationUpdates
        case error(String)
    }
    
    public let status: Status
    public let timestamp: Date
    
    public init(status: Status) {
        self.status = status
        self.timestamp = Date()
    }
}

/// A single, coherent Vusion location update — aisle, modular, device, and
/// RSSI as they were reported together by BeaconingService's
/// nearestModularUpdated(...) callback.
public struct VusionLocationUpdate {
    public let aisleName: String
    public let modularName: String
    public let deviceId: String
    public let rssi: Int
}

/// Client apps integrating RetailBrain SDK implement this to receive
/// continuous Vusion location updates once the map is ready.
public protocol VusionTrackingDelegate: AnyObject {
    func vusionDidUpdateLocation(_ update: VusionLocationUpdate)
    func vusionDidFailToInitialize(_ error: Error)
}

/// Owns the "start Vusion after the map loads" lifecycle so RetailBrain's
/// map-loading code only needs a single call site.
public final class VusionIntegrationManager: VusionTrackingDelegate {
    
    public static let shared = VusionIntegrationManager()
    
    public weak var delegate: VusionTrackingDelegate?
    public var statusHandler: ((VusionStatusUpdate) -> Void)?
    
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "RetailBrainSDK",
        category: "VusionIntegrationManager"
    )
    
    private var cancellables = Set<AnyCancellable>()
    private var hasInitialized = false
    
    private init() {
        // Set self as the VusionTrackingDelegate to forward events to RetailBrainManager
        // This allows us to receive Vusion updates and forward them to the app delegate
    }
    
    /// Call exactly once, right after Mappedin's show3dMap succeeds.
    /// Safe to call multiple times — only the first call does anything.
    public func startAfterMapLoad() {
        guard !hasInitialized else {
            Self.logger.info("Vusion already initialized — skipping")
            return
        }
        hasInitialized = true
        
        let initializingStatus = VusionStatusUpdate(status: .initializing)
        statusHandler?(initializingStatus)
        
        do {
            // Same call the sample makes from its "Initialize SDK" button.
            try BeaconingService.shared.initializeSDK()
            
            let initializedStatus = VusionStatusUpdate(status: .initialized)
            statusHandler?(initializedStatus)
        } catch {
            Self.logger.error("Vusion initializeSDK failed: \(error.localizedDescription, privacy: .public)")
            delegate?.vusionDidFailToInitialize(error)
            let errorStatus = VusionStatusUpdate(status: .error(error.localizedDescription))
            statusHandler?(errorStatus)
            hasInitialized = false // allow a retry on the next map load attempt
            return
        }
        
        subscribeToLocationUpdates()
        
        Task {
            do {
                // Same call the sample makes from its "Start" button:
                // fetches anchors, then calls the SDK's locateMe(anchors:).
                try await BeaconingService.shared.startBeaconing()
                Self.logger.info("Vusion beaconing started")
                
                let trackingStatus = VusionStatusUpdate(status: .trackingLocationUpdates)
                self.statusHandler?(trackingStatus)
            } catch {
                await MainActor.run {
                    Self.logger.error("Vusion startBeaconing failed: \(error.localizedDescription, privacy: .public)")
                    self.delegate?.vusionDidFailToInitialize(error)
                    let errorStatus = VusionStatusUpdate(status: .error(error.localizedDescription))
                    self.statusHandler?(errorStatus)
                }
            }
        }
    }
    
    /// Optional — call if RetailBrain's map/view is torn down and tracking
    /// should stop with it.
    public func stopTracking() {
        try? BeaconingService.shared.stopBeaconing()
        cancellables.removeAll()
        hasInitialized = false
    }
    
    private func subscribeToLocationUpdates() {
        // These four fields are set together, atomically, inside
        // BeaconingService.nearestModularUpdated(...) — combining them here
        // (rather than observing lastDeviceId/lastRssi separately) guarantees
        // aisle/modular/device/rssi always belong to the same update.
        Publishers.CombineLatest4(
            BeaconingService.shared.$lastAisleName,
            BeaconingService.shared.$lastModularName,
            BeaconingService.shared.$lastModularDeviceId,
            BeaconingService.shared.$lastModularRssi
        )
        .dropFirst() // skip the initial empty/zero defaults
        .receive(on: DispatchQueue.main)
        .sink { [weak self] aisleName, modularName, deviceId, rssi in
            let update = VusionLocationUpdate(
                aisleName: aisleName,
                modularName: modularName,
                deviceId: deviceId,
                rssi: rssi
            )
            
            self?.delegate?.vusionDidUpdateLocation(update)
        }
        .store(in: &cancellables)
    }
    
    // MARK: - VusionTrackingDelegate Implementation
    
    public func vusionDidUpdateLocation(_ update: VusionLocationUpdate) {
        delegate?.vusionDidUpdateLocation(update)
    }
    
    public func vusionDidFailToInitialize(_ error: Error) {
        delegate?.vusionDidFailToInitialize(error)
    }
}
