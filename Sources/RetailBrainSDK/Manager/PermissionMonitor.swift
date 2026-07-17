//
//  PermissionMonitor.swift
//  RetailBrainSDK
//
//  Created by ajith.a.s on 01/07/26.
//

import Foundation
import CoreLocation
import CoreBluetooth

public protocol PermissionMonitorDelegate: AnyObject {
    func permissionMonitorDidDetectPermissionChange(_ monitor: PermissionMonitor, revokedPermission: RevokedPermission)
}

public enum RevokedPermission {
    case location
    case bluetooth
}

public class PermissionMonitor: NSObject, CLLocationManagerDelegate, CBCentralManagerDelegate {
    public weak var delegate: PermissionMonitorDelegate?
    
    private let locationManager = CLLocationManager()
    private var centralManager: CBCentralManager?
    private var monitoringTimer: Timer?
    private var lastLocationStatus: CLAuthorizationStatus = .notDetermined
    private var lastBluetoothStatus: CBManagerAuthorization = .notDetermined
    private var isMonitoring = false
    
    override public init() {
        super.init()
        locationManager.delegate = self
        updateCurrentStatus()
    }
    
    public func startMonitoring() {
        guard !isMonitoring else { return }
        
        isMonitoring = true
        updateCurrentStatus()
        
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkPermissionChanges()
        }
    }
    
    public func stopMonitoring() {
        isMonitoring = false
        monitoringTimer?.invalidate()
        monitoringTimer = nil
        centralManager = nil
    }
    
    public func updateCurrentStatus() {
        lastLocationStatus = locationManager.authorizationStatus
        lastBluetoothStatus = CBManager.authorization
        
        if centralManager == nil {
            centralManager = CBCentralManager(delegate: self, queue: .main)
        }
    }
    
    private func checkPermissionChanges() {
        let currentLocationStatus = locationManager.authorizationStatus
        let currentBluetoothStatus = CBManager.authorization
        
        if currentLocationStatus != lastLocationStatus {
            if isPermissionRevoked(from: lastLocationStatus, to: currentLocationStatus) {
                delegate?.permissionMonitorDidDetectPermissionChange(self, revokedPermission: .location)
                lastLocationStatus = currentLocationStatus
                return
            }
            lastLocationStatus = currentLocationStatus
        }
        
        if currentBluetoothStatus != lastBluetoothStatus {
            if isPermissionRevoked(from: lastBluetoothStatus, to: currentBluetoothStatus) {
                delegate?.permissionMonitorDidDetectPermissionChange(self, revokedPermission: .bluetooth)
                lastBluetoothStatus = currentBluetoothStatus
                return
            }
            lastBluetoothStatus = currentBluetoothStatus
        }
    }
    
    private func isPermissionRevoked(from oldStatus: CLAuthorizationStatus, to newStatus: CLAuthorizationStatus) -> Bool {
        let wasGranted = oldStatus == .authorizedAlways || oldStatus == .authorizedWhenInUse
        let isNowDenied = newStatus == .denied || newStatus == .restricted
        return wasGranted && isNowDenied
    }
    
    private func isPermissionRevoked(from oldStatus: CBManagerAuthorization, to newStatus: CBManagerAuthorization) -> Bool {
        let wasGranted = oldStatus == .allowedAlways
        let isNowDenied = newStatus == .denied || newStatus == .restricted
        return wasGranted && isNowDenied
    }
    
    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        checkPermissionChanges()
    }
    
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        checkPermissionChanges()
    }
}
