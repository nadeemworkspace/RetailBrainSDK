//
//  RetailMapView.swift
//  RetailBrainSDK
//
//  Created by ajith.a.s on 22/06/26.
//

import Foundation
import SwiftUI
import Mappedin
import UIKit

class MapViewContainer: UIView {
    let mapView: MapView

    init(mapView: MapView) {
        self.mapView = mapView
        super.init(frame: .zero)
        backgroundColor = .clear
        setupMapView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupMapView() {
        let mirror = Mirror(reflecting: mapView)

        for child in mirror.children {
            if let uiView = child.value as? UIView {
                addSubview(uiView)
                uiView.frame = bounds
                uiView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                return
            }
        }
    }
}

struct MapViewRepresentable: UIViewRepresentable {
    let mapView: MapView

    func makeUIView(context: Context) -> MapViewContainer {
        MapViewContainer(mapView: mapView)
    }

    func updateUIView(_ uiView: MapViewContainer, context: Context) {}
}

public struct RetailMapView: View {
    @StateObject private var viewModel: RetailMapViewModel
    private let routingController: MapRoutingController

    public init(
        routingController: MapRoutingController = MapRoutingController(),
        onMapLoaded: (() -> Void)? = nil,
        onLaunch: (() -> Void)? = nil,
        mapId: String? = nil,
        isMultiFloorMode: Bool = false
    ) {
        self.routingController = routingController
        _viewModel = StateObject(
            wrappedValue: RetailMapViewModel(onMapLoaded: {
                routingController.markMapReady()
                onMapLoaded?()
                onLaunch?()
            }, mapId: mapId, isMultiFloorMode: isMultiFloorMode)
        )
    }

    public var body: some View {
        ZStack {
            MapViewRepresentable(mapView: viewModel.mapView)
                .ignoresSafeArea()

            if viewModel.isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(1.5)

                    Text("Loading Map...")
                        .font(.headline)
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.25))
            }
        }
        .onAppear {
            routingController.attach(viewModel: viewModel)
            viewModel.loadMap()
        }
    }
}
