//
//  RetailMapVM.swift
//  RetailBrainSDK
//
//  Created by ajith.a.s on 23/06/26.
//

import Foundation
import Mappedin
import SwiftUI
import Combine

final class RetailMapViewModel: ObservableObject {

    @Published var mapView = MapView()
    @Published var isLoading = true
    @Published var selectedStore: StoreDetails?

    private let onMapLoaded: (() -> Void)?
    private var customMapId: String?
    private let isMultiFloorMode: Bool
    private var isMapRendered = false
    private var selectedProductForBlueDot: String?

    init(onMapLoaded: (() -> Void)? = nil, mapId: String? = nil, isMultiFloorMode: Bool = false) {
        self.onMapLoaded = onMapLoaded
        self.customMapId = mapId
        self.isMultiFloorMode = isMultiFloorMode
    }

    private lazy var navigationManager = NavigationManager(mapView: mapView) { [weak self] storeDetails in
        DispatchQueue.main.async {
            self?.selectedStore = storeDetails
            if let storeDetails {
                RetailBrainManager.shared.delegate?.didTapProductPointer(storeDetails)
            }
        }
    }

    func loadMap() {
        guard let config = RetailBrainManager.shared.config else {
            print("RetailBrain Config Missing")
            RetailBrainManager.shared.delegate?.mapDidFailToLoad(error: RetailBrainSDKError.invalidConfiguration)
            isLoading = false
            return
        }

        let mapIdToLoad = customMapId ?? config.mapId
        
        let options = GetMapDataWithCredentialsOptions(
            key: config.apiKey,
            secret: config.apiSecret,
            mapId: mapIdToLoad
        )

        mapView.getMapData(options: options) { [weak self] result in
            guard let self else { return }

            switch result {
            case .success:
                let multiFloorOptions: MultiFloorViewOptions? = isMultiFloorMode
                    ? MultiFloorViewOptions(
                        enabled: true,
                        floorGap: nil,
                        floorGapMultiplier: nil,
                        floorGapFallback: nil,
                        updateCameraElevationOnFloorChange: true,
                        footprintColor: nil,
                        footprintOpacity: nil,
                        footprintOutline: nil,
                        spacesOpenToBelowEnabled: nil,
                        spacesOpenToBelowVisualEffectEnabled: nil,
                        spacesOpenToBelowVisualEffectDarkenAmount: nil,
                        spacesOpenToBelowVisualEffectDarkenUseDepth: nil,
                        spacesOpenToBelowVisualEffectDesaturateAmount: nil,
                        spacesOpenToBelowVisualEffectDesaturateUseDepth: nil,
                        spacesOpenToBelowVisualEffectWashOutAmount: nil,
                        spacesOpenToBelowVisualEffectWashOutUseDepth: nil
                    )
                    : nil

                let showOptions = Show3DMapOptions(
                    bearing: nil,
                    debug: nil,
                    flipImagesToFaceCamera: nil,
                    initialFloor: nil,
                    injectStyles: nil,
                    multiFloorView: multiFloorOptions,
                    outdoorView: nil,
                    pitch: nil,
                    preloadFloors: nil,
                    screenOffsets: nil,
                    shadingAndOutlines: nil,
                    style: nil,
                    wallTopColor: nil,
                    zoomLevel: nil
                )

                self.mapView.show3dMap(options: showOptions) { renderResult in
                    switch renderResult {
                    case .success:
                        print("Map Loaded Successfully")

                        self.isMapRendered = true
                        self.placeBlueDotIfReady()
                        RetailBrainManager.shared.delegate?.mapDidLoad()
                        self.onMapLoaded?()
                        self.isLoading = false
                    case .failure(let error):
                        print("Map rendering failed")
                        print(error)
                        RetailBrainManager.shared.delegate?.mapDidFailToLoad(error: error)
                        self.isLoading = false
                    }
                }

            case .failure(let error):
                print("Map Loading Failed")
                print(error)
                RetailBrainManager.shared.delegate?.mapDidFailToLoad(error: error)
                self.isLoading = false
            }
        }
    }

    func clearSelections() {
        navigationManager.clearRoutes()
    }

    public func routeToItems(_ itemNames: [String]) {
        guard !itemNames.isEmpty else {
            print("No items provided for routing")
            return
        }

        // Keep this static-product flow replaceable for future Vusion coordinates.
        selectedProductForBlueDot = itemNames.first

        RetailBrainManager.shared.delegate?.routeCalculationStarted()
        navigationManager.prepareToDrawRoute(destinationNames: itemNames)
        placeBlueDotIfReady()
    }

    private func placeBlueDotIfReady() {
        guard isMapRendered, let productName = selectedProductForBlueDot else { return }
        navigationManager.placeUserBlueDotAtStaticItem(named: productName)
    }

    deinit {
        mapView.destroy()
    }
}
