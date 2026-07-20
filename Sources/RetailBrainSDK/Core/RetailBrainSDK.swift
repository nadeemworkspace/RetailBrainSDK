//
//  RetailBrainSDK.swift
//  RetailBrainSDK
//
//  Created by ajith.a.s on 22/06/26.
//

import Foundation
import CoreLocation
import CoreBluetooth
import SwiftUI
import UIKit

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
    
    // Vusion Events
    func vusionDidInitialize()
    func vusionDidUpdateLocation(_ update: VusionLocationUpdate)
    func vusionDidFailToInitialize(_ error: Error)
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
    func vusionDidInitialize() {}
    func vusionDidUpdateLocation(_ update: VusionLocationUpdate) {}
    func vusionDidFailToInitialize(_ error: Error) {}
}

public enum RetailBrainSDKError: LocalizedError {
    case invalidConfiguration
    case notInitialized
    case noProductsProvided
    
    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "RetailBrain configuration is invalid."
        case .notInitialized:
            return "RetailBrain SDK is not initialized."
        case .noProductsProvided:
            return "No products were provided for navigation."
        }
    }
}

public enum RetailBrainPermissionType {
    case location
    case bluetooth
}

public enum RetailBrainPermissionState {
    case allGranted
    case needsRequest
    case deniedPermanently([RetailBrainPermissionType])
}

public enum RetailBrainEvent {
    case sdkInitialized
    case sdkInitializationFailed(Error)
    case mapLoadingStarted
    case mapLoaded
    case mapLoadFailed(Error)
    case indoorLocationUpdated(VusionLocationUpdate)
    case aisleUpdated(String)
    case moduleUpdated(String)
    case rssiUpdated(Int)
    case navigationStarted([String])
    case navigationUpdated([String])
    case navigationCompleted
    case navigationModeChanged(isMultiFloor: Bool)
    case floorChanged(String)
    case vusionInitialized
    case vusionInitializationFailed(Error)
    case vusionStatusUpdated(VusionStatusUpdate)
    case permissionGranted(RetailBrainPermissionType)
    case permissionDenied(type: RetailBrainPermissionType, isPermanent: Bool)
    case openSettingsRequired(RetailBrainPermissionType)
    case didTapProductPointer(StoreDetails)
    case productsUpdated
    case generalError(Error)
}

public protocol RetailBrainManagerDelegate: AnyObject {
    func retailBrainManager(_ manager: RetailBrainManager, didReceive event: RetailBrainEvent)
}

public final class RetailBrainManager {
    
    public static let shared = RetailBrainManager()
    internal static var current = RetailBrainManager.shared
    
    private weak var activeMapViewModel: RetailMapViewModel?
    private let permissionCoordinator = RetailBrainPermissionCoordinator()
    private var isInitialized = false
    private var isMapLoaded = false
    private var isMultiFloorNavigationEnabled = false
    private var lastAisleName = ""
    private var lastModuleName = ""
    private var lastVusionBlueDotKey = ""
    private var configuredProducts: [ShoppingItem] = []
    private var pendingNavigationDestinations: [String]?
    
    public init(configuration: RetailBrainConfig? = nil) {
        self.config = configuration
        permissionCoordinator.delegate = self
        VusionIntegrationManager.shared.delegate = self
        VusionIntegrationManager.shared.statusHandler = { [weak self] status in
            self?.handleVusionStatus(status)
        }
    }
    
    public private(set) var config: RetailBrainConfig?
    public weak var delegate: RetailBrainManagerDelegate?
    public weak var legacyDelegate: RetailBrainSDKDelegate?
    
    public func configure(_ config: RetailBrainConfig) {
        self.config = config
    }
    
    public func configureMap(_ config: RetailBrainConfig) {
        configure(config)
    }
    
    public func initializeSDK() {
        RetailBrainManager.current = self
        // Rebind Vusion callbacks to the active manager instance in case another
        // manager instance previously overrode the shared Vusion handlers.
        VusionIntegrationManager.shared.delegate = self
        VusionIntegrationManager.shared.statusHandler = { [weak self] status in
            self?.handleVusionStatus(status)
        }
        
        guard let config else {
            notify(.sdkInitializationFailed(RetailBrainSDKError.invalidConfiguration))
            return
        }
        guard !config.apiKey.isEmpty, !config.apiSecret.isEmpty, !config.mapId.isEmpty else {
            notify(.sdkInitializationFailed(RetailBrainSDKError.invalidConfiguration))
            return
        }
        
        isInitialized = true
        isMapLoaded = false
        lastVusionBlueDotKey = ""
        notify(.sdkInitialized)
    }
    
    // Backward-compatible entry point.
    public func initialize(config: RetailBrainConfig) {
        self.config = config
        initializeSDK()
    }
    
    public func requestRequiredPermissions(completion: @escaping (Bool) -> Void) {
        permissionCoordinator.requestPermissionsSequentially { [weak self] granted in
            if granted {
                self?.permissionCoordinator.startMonitoringRevocations()
            }
            completion(granted)
        }
    }
    
    public func currentPermissionState() -> RetailBrainPermissionState {
        permissionCoordinator.currentPermissionState()
    }
    
    public func stopPermissionMonitoring() {
        permissionCoordinator.stopMonitoringRevocations()
    }
    
    public func syncPermissionMonitoringWithCurrentState() {
        switch permissionCoordinator.currentPermissionState() {
        case .allGranted:
            permissionCoordinator.startMonitoringRevocations()
        case .needsRequest, .deniedPermanently:
            permissionCoordinator.stopMonitoringRevocations()
        }
    }
    
    public func getMapView(mapId: String? = nil, isMultiFloorMode: Bool = false) -> RetailMapView {
        isMapLoaded = false
        lastVusionBlueDotKey = ""
        isMultiFloorNavigationEnabled = isMultiFloorMode
        notify(.navigationModeChanged(isMultiFloor: isMultiFloorMode))
        return RetailMapView(
            mapId: mapId,
            isMultiFloorMode: isMultiFloorMode
        )
    }
    
    public func setProducts(_ products: [ShoppingItem]) {
        configuredProducts = products
        ShoppingItemsProvider.shared.setCustomItems(products)
    }
    
    public func loadMap() {
        notify(.mapLoadingStarted)
    }
    
    public func startNavigation(destinations: [String]) {
        guard isInitialized else {
            notify(.generalError(RetailBrainSDKError.notInitialized))
            return
        }
        guard !destinations.isEmpty else {
            notify(.generalError(RetailBrainSDKError.noProductsProvided))
            return
        }
        
        pendingNavigationDestinations = destinations
        tryStartPendingNavigationIfPossible()
    }
    
    public func startNavigation() {
        let autoDestinations = configuredProducts
            .prefix(5)
            .map { item in
                item.name == item.storeName ? item.storeName : "\(item.storeName)|\(item.name)"
            }
        
        startNavigation(destinations: autoDestinations)
    }
    
    public func startSingleFloorNavigation(destinations: [String]) {
        isMultiFloorNavigationEnabled = false
        notify(.navigationModeChanged(isMultiFloor: false))
        startNavigation(destinations: destinations)
    }
    
    public func startMultiFloorNavigation(destinations: [String]) {
        isMultiFloorNavigationEnabled = true
        notify(.navigationModeChanged(isMultiFloor: true))
        startNavigation(destinations: destinations)
    }
    
    public func changeFloor(to floorIdentifier: String) {
        notify(.floorChanged(floorIdentifier))
    }
    
    public func updateNavigation(destinations: [String]) {
        notify(.navigationUpdated(destinations))
        activeMapViewModel?.routeToItems(destinations)
    }
    
    public func stopNavigation() {
        activeMapViewModel?.clearSelections()
        pendingNavigationDestinations = nil
        notify(.navigationCompleted)
    }
    
    public func clearNavigation() {
        activeMapViewModel?.clearSelections()
        pendingNavigationDestinations = nil
        notify(.navigationCompleted)
    }
    
    public func placeUserBlueDotAtExternalID(aisle: String, module: String) {
        activeMapViewModel?.placeBlueDotAtVusionLocation(aisle: aisle, module: module)
    }
    
    internal func attachMapViewModel(_ viewModel: RetailMapViewModel) {
        activeMapViewModel = viewModel
    }
    
    internal func detachMapViewModel(_ viewModel: RetailMapViewModel) {
        guard activeMapViewModel === viewModel else { return }
        activeMapViewModel = nil
    }
    
    public func openAppSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(settingsURL)
    }
    
    internal func handleMapDidLoad() {
        isMapLoaded = true
        notify(.mapLoaded)
        tryStartPendingNavigationIfPossible()
    }
    
    internal func handleMapLoadFailed(_ error: Error) {
        notify(.mapLoadFailed(error))
    }
    
    internal func handleProductPointerTap(_ product: StoreDetails) {
        notify(.didTapProductPointer(product))
    }
    
    internal func handleProductsUpdated() {
        notify(.productsUpdated)
    }
    
    internal func handleRouteCalculationStarted() {
        notify(.navigationStarted([]))
    }
    
    private func handleVusionStatus(_ status: VusionStatusUpdate) {
        notify(.vusionStatusUpdated(status))
        switch status.status {
        case .initialized:
            notify(.vusionInitialized)
        case .error(let message):
            let error = NSError(domain: "RetailBrainSDK.Vusion", code: -1, userInfo: [NSLocalizedDescriptionKey: message])
            notify(.vusionInitializationFailed(error))
            notify(.generalError(error))
        default:
            break
        }
    }
    
    private func notify(_ event: RetailBrainEvent) {
        DispatchQueue.main.async {
            self.delegate?.retailBrainManager(self, didReceive: event)
            self.forwardToLegacyDelegate(event)
        }
    }
    
    private func tryStartPendingNavigationIfPossible() {
        guard isInitialized, isMapLoaded, let destinations = pendingNavigationDestinations, !destinations.isEmpty else {
            return
        }
        
        pendingNavigationDestinations = nil
        notify(.navigationStarted(destinations))
        activeMapViewModel?.routeToItems(destinations)
    }
    
    private func forwardToLegacyDelegate(_ event: RetailBrainEvent) {
        switch event {
        case .sdkInitialized:
            legacyDelegate?.sdkDidInitialize()
        case .sdkInitializationFailed(let error):
            legacyDelegate?.sdkDidFailToInitialize(error: error)
        case .mapLoaded:
            legacyDelegate?.mapDidLoad()
        case .mapLoadFailed(let error):
            legacyDelegate?.mapDidFailToLoad(error: error)
        case .productsUpdated:
            legacyDelegate?.addProductToMap()
        case .navigationStarted:
            legacyDelegate?.routeCalculationStarted()
        case .didTapProductPointer(let product):
            legacyDelegate?.didTapProductPointer(product)
        case .indoorLocationUpdated(let update):
            legacyDelegate?.vusionDidUpdateLocation(update)
        case .vusionInitialized:
            legacyDelegate?.vusionDidInitialize()
        case .vusionInitializationFailed(let error):
            legacyDelegate?.vusionDidFailToInitialize(error)
        case .generalError(let error):
            legacyDelegate?.vusionDidFailToInitialize(error)
        default:
            break
        }
    }
}

extension RetailBrainManager: VusionTrackingDelegate {
    public func vusionDidUpdateLocation(_ update: VusionLocationUpdate) {
        updateBlueDotFromVusionIfNeeded(aisle: update.aisleName, module: update.modularName)
        notify(.indoorLocationUpdated(update))
        
        if update.aisleName != lastAisleName {
            lastAisleName = update.aisleName
            notify(.aisleUpdated(update.aisleName))
        }
        
        if update.modularName != lastModuleName {
            lastModuleName = update.modularName
            notify(.moduleUpdated(update.modularName))
        }
        
        notify(.rssiUpdated(update.rssi))
    }
    
    public func vusionDidFailToInitialize(_ error: Error) {
        notify(.generalError(error))
    }
    
    private func updateBlueDotFromVusionIfNeeded(aisle: String, module: String) {
        let normalizedAisle = aisle.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedModule = module.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedAisle.isEmpty, !normalizedModule.isEmpty else { return }
        
        let blueDotKey = "\(normalizedAisle.lowercased())|\(normalizedModule.lowercased())"
        guard blueDotKey != lastVusionBlueDotKey else { return }
        
        lastVusionBlueDotKey = blueDotKey
        placeUserBlueDotAtExternalID(aisle: normalizedAisle, module: normalizedModule)
    }
}

extension RetailBrainManager: RetailBrainPermissionCoordinatorDelegate {
    fileprivate func permissionCoordinator(_ coordinator: RetailBrainPermissionCoordinator, didEmit event: RetailBrainEvent) {
        notify(event)
    }
}

private protocol RetailBrainPermissionCoordinatorDelegate: AnyObject {
    func permissionCoordinator(_ coordinator: RetailBrainPermissionCoordinator, didEmit event: RetailBrainEvent)
}

private final class RetailBrainPermissionCoordinator: NSObject {
    weak var delegate: RetailBrainPermissionCoordinatorDelegate?
    
    private let locationManager = CLLocationManager()
    private var centralManager: CBCentralManager?
    private var monitorTimer: Timer?
    private var locationCompletion: ((Bool) -> Void)?
    private var bluetoothCompletion: ((Bool) -> Void)?
    
    private var lastLocationStatus: CLAuthorizationStatus = .notDetermined
    private var lastBluetoothStatus: CBManagerAuthorization = .notDetermined
    
    override init() {
        super.init()
        locationManager.delegate = self
        updateStatuses()
    }
    
    func requestPermissionsSequentially(completion: @escaping (Bool) -> Void) {
        requestLocationPermissionIfNeeded { [weak self] locationGranted in
            guard let self else {
                completion(false)
                return
            }
            
            guard locationGranted else {
                completion(false)
                return
            }
            
            self.requestBluetoothPermissionIfNeeded(completion: completion)
        }
    }
    
    func currentPermissionState() -> RetailBrainPermissionState {
        let locationStatus = locationManager.authorizationStatus
        let bluetoothStatus = CBManager.authorization
        
        let isLocationGranted = locationStatus == .authorizedAlways || locationStatus == .authorizedWhenInUse
        let isBluetoothGranted = bluetoothStatus == .allowedAlways
        
        if isLocationGranted && isBluetoothGranted {
            return .allGranted
        }
        
        var permanentlyDenied: [RetailBrainPermissionType] = []
        if locationStatus == .denied || locationStatus == .restricted {
            permanentlyDenied.append(.location)
        }
        if bluetoothStatus == .denied || bluetoothStatus == .restricted {
            permanentlyDenied.append(.bluetooth)
        }
        
        if !permanentlyDenied.isEmpty {
            return .deniedPermanently(permanentlyDenied)
        }
        
        return .needsRequest
    }
    
    func startMonitoringRevocations() {
        stopMonitoringRevocations()
        updateStatuses()
        monitorTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkPermissionChanges()
        }
    }
    
    func stopMonitoringRevocations() {
        monitorTimer?.invalidate()
        monitorTimer = nil
        centralManager = nil
    }
    
    private func requestLocationPermissionIfNeeded(completion: @escaping (Bool) -> Void) {
        let currentStatus = locationManager.authorizationStatus
        if currentStatus == .authorizedAlways || currentStatus == .authorizedWhenInUse {
            delegate?.permissionCoordinator(self, didEmit: .permissionGranted(.location))
            completion(true)
            return
        }
        
        if currentStatus == .denied || currentStatus == .restricted {
            delegate?.permissionCoordinator(self, didEmit: .permissionDenied(type: .location, isPermanent: true))
            delegate?.permissionCoordinator(self, didEmit: .openSettingsRequired(.location))
            completion(false)
            return
        }
        
        locationCompletion = completion
        locationManager.requestWhenInUseAuthorization()
    }
    
    private func requestBluetoothPermissionIfNeeded(completion: @escaping (Bool) -> Void) {
        let status = CBManager.authorization
        if status == .allowedAlways {
            delegate?.permissionCoordinator(self, didEmit: .permissionGranted(.bluetooth))
            completion(true)
            return
        }
        
        if status == .denied || status == .restricted {
            delegate?.permissionCoordinator(self, didEmit: .permissionDenied(type: .bluetooth, isPermanent: true))
            delegate?.permissionCoordinator(self, didEmit: .openSettingsRequired(.bluetooth))
            completion(false)
            return
        }
        
        bluetoothCompletion = completion
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }
    
    private func updateStatuses() {
        lastLocationStatus = locationManager.authorizationStatus
        lastBluetoothStatus = CBManager.authorization
    }
    
    private func checkPermissionChanges() {
        let currentLocation = locationManager.authorizationStatus
        if currentLocation != lastLocationStatus {
            if isLocationRevoked(from: lastLocationStatus, to: currentLocation) {
                delegate?.permissionCoordinator(self, didEmit: .permissionDenied(type: .location, isPermanent: true))
                delegate?.permissionCoordinator(self, didEmit: .openSettingsRequired(.location))
            }
            lastLocationStatus = currentLocation
        }
        
        let currentBluetooth = CBManager.authorization
        if currentBluetooth != lastBluetoothStatus {
            if isBluetoothRevoked(from: lastBluetoothStatus, to: currentBluetooth) {
                delegate?.permissionCoordinator(self, didEmit: .permissionDenied(type: .bluetooth, isPermanent: true))
                delegate?.permissionCoordinator(self, didEmit: .openSettingsRequired(.bluetooth))
            }
            lastBluetoothStatus = currentBluetooth
        }
    }
    
    private func isLocationRevoked(from oldStatus: CLAuthorizationStatus, to newStatus: CLAuthorizationStatus) -> Bool {
        let wasGranted = oldStatus == .authorizedAlways || oldStatus == .authorizedWhenInUse
        let isNowDenied = newStatus == .denied || newStatus == .restricted
        return wasGranted && isNowDenied
    }
    
    private func isBluetoothRevoked(from oldStatus: CBManagerAuthorization, to newStatus: CBManagerAuthorization) -> Bool {
        let wasGranted = oldStatus == .allowedAlways
        let isNowDenied = newStatus == .denied || newStatus == .restricted
        return wasGranted && isNowDenied
    }
}

extension RetailBrainPermissionCoordinator: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        guard status != .notDetermined else { return }
        
        if status == .authorizedAlways || status == .authorizedWhenInUse {
            delegate?.permissionCoordinator(self, didEmit: .permissionGranted(.location))
            locationCompletion?(true)
        } else {
            delegate?.permissionCoordinator(self, didEmit: .permissionDenied(type: .location, isPermanent: true))
            delegate?.permissionCoordinator(self, didEmit: .openSettingsRequired(.location))
            locationCompletion?(false)
        }
        locationCompletion = nil
    }
}

extension RetailBrainPermissionCoordinator: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let status = CBManager.authorization
        guard status != .notDetermined || central.state == .unsupported else { return }
        
        if status == .allowedAlways {
            delegate?.permissionCoordinator(self, didEmit: .permissionGranted(.bluetooth))
            bluetoothCompletion?(true)
        } else {
            delegate?.permissionCoordinator(self, didEmit: .permissionDenied(type: .bluetooth, isPermanent: true))
            delegate?.permissionCoordinator(self, didEmit: .openSettingsRequired(.bluetooth))
            bluetoothCompletion?(false)
        }
        
        bluetoothCompletion = nil
    }
}
