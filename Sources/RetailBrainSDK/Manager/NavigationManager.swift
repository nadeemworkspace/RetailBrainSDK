//
//  NavigationManager.swift
//  RetailBrainSDK
//
//  Created by ajith.a.s on 24/06/26.
//

import Foundation
import Mappedin
import UIKit

public typealias StoreSelectCallback = (StoreDetails?) -> Void

// MARK: - Camera Constants

private let CAMERA_ZOOM: Double = 19.0
private let CAMERA_PITCH: Double = 0.0
private let MULTI_FLOOR_CAMERA_PITCH: Double = 45.0
private let DEFAULT_BEARING: Double = 0.0
private let BEARING_OFFSET: Double = -33.0
private let STORE_MARKER_TAP_MAX_DISTANCE_SQUARED: Double = 1e-8
private let STATIC_BLUE_DOT_COLOR = "#1871fb"
private let BLUE_DOT_ANCHOR_SPACE_LIMIT = 30
private let BLUE_DOT_MIN_DISTANCE_FROM_DESTINATION_SQUARED: Double = 4e-10
private let BLUE_DOT_DEFAULT_BACKSTEP = 1
private let BLUE_DOT_POI_BACKSTEP = 2

// MARK: - Data Models

private struct RouteDestination {
    let id: String
    let name: String
    let targets: [NavigationTarget]
    let floorIds: Set<String>
}

private struct StoreMarkerDetails {
    let details: StoreDetails
    let coordinate: Coordinate
}

// MARK: - Navigation Manager

public class NavigationManager {
    
    private let mapView: MapView
    private var storeSelectCallback: StoreSelectCallback?
    private var storeMarkerDetails: [StoreMarkerDetails] = []
    
    private var pendingDestinationNames: [String]? = nil
    private var awaitingUserStartLocation: Bool = false
    private var selectedStartCoordinate: Coordinate?
    private var routeRequestID = 0
    
    private var availableFloors: [Floor] = []
    private var currentActiveFloors: Set<String> = []
    private var isMultiFloorRouteActive = false
    
    public init(mapView: MapView, storeSelectCallback: @escaping StoreSelectCallback) {
        self.mapView = mapView
        self.storeSelectCallback = storeSelectCallback
        registerMarkerTapHandler()
    }

    // MARK: - Public API
    
    public func prepareToDrawRoute(destinationNames: [String]) {
        guard !destinationNames.isEmpty else { return }
        routeRequestID += 1
        pendingDestinationNames = destinationNames
        awaitingUserStartLocation = true
        selectedStartCoordinate = nil
        isMultiFloorRouteActive = false
        currentActiveFloors = []
        mapView.navigation.clear()
        mapView.paths.removeAll()
        mapView.markers.removeAll()
        storeMarkerDetails = []
    }
    
    public func clearRoutes() {
        routeRequestID += 1
        mapView.navigation.clear()
        mapView.paths.removeAll()
        mapView.markers.removeAll()
        storeMarkerDetails = []
        pendingDestinationNames = nil
        awaitingUserStartLocation = false
        selectedStartCoordinate = nil
        isMultiFloorRouteActive = false
        currentActiveFloors = []
    }
    
    public func placeUserBlueDotAtStaticItem(named itemName: String = "Milk") {
        resolveBlueDotCoordinate(forStaticItem: itemName) { [weak self] coordinate in
            guard let self, let coordinate else { return }
            self.renderUserBlueDot(at: coordinate)
        }
    }

    // Parallel flow: resolves target using Vusion aisle+module External ID.
    public func placeUserBlueDotAtExternalID(aisle: String, module: String) {
        resolveBlueDotCoordinate(forVusionAisle: aisle, module: module) { [weak self] coordinate in
            guard let self, let coordinate else { return }
            self.renderUserBlueDot(at: coordinate)
        }
    }
    
    // MARK: - User Interaction
    
    private func registerMarkerTapHandler() {
        mapView.on(Events.click) { [weak self] clickPayload in
            guard let self, let clickPayload else { return }
            
            let tappedMarkers = clickPayload.markers ?? []
            
            // Only treat a tap as route-start selection while explicitly waiting for start input.
            if self.awaitingUserStartLocation,
               let destinations = self.pendingDestinationNames {
                let coordinate = clickPayload.coordinate
                self.awaitingUserStartLocation = false
                self.startRouteFromTappedCoordinate(coordinate, destinationNames: destinations)
                return
            }
            
            // During an active route, reroute only when tapping open map space.
            // Marker taps (for example floor transition arrows) should keep current route flow.
            if let destinations = self.pendingDestinationNames,
               tappedMarkers.isEmpty {
                self.startRouteFromTappedCoordinate(clickPayload.coordinate, destinationNames: destinations)
                return
            }
            
            guard !tappedMarkers.isEmpty else {
                self.storeSelectCallback?(nil)
                return
            }
            
            let coordinate = clickPayload.coordinate
            
            if let markerDetails = self.nearestStoreMarker(
                to: coordinate,
                maxDistanceSquared: STORE_MARKER_TAP_MAX_DISTANCE_SQUARED
            ) {
                self.storeSelectCallback?(markerDetails.details)
                return
            }
            
            self.storeSelectCallback?(nil)
        }
    }
    
    // MARK: - Route Lifecycle
    
    private func startRouteFromTappedCoordinate(_ coordinate: Coordinate, destinationNames: [String]) {
        routeRequestID += 1
        selectedStartCoordinate = coordinate
        mapView.navigation.clear()
        mapView.paths.removeAll()
        mapView.markers.removeAll()
        storeMarkerDetails = []
        addMarkerForUserLoc(
            title: "",
            subtitle: nil,
            color: "#1871fb",
            target: coordinate,
            compact: true
        )
        drawNearestSpaceRoute(fromCoordinate: coordinate, destinationNames: destinationNames, requestID: routeRequestID)
    }
    
    // MARK: - Marker Rendering
    
    private func addMarkerForUserLoc(
        title: String,
        subtitle: String?,
        color: String,
        target: Coordinate,
        compact: Bool = false
    ) {
        let markerHtml = MarkerHTMLGenerator.startMarkerHTML(
            title: title,
            subtitle: subtitle,
            color: color,
            compact: compact
        )
        
        mapView.markers.add(
            target: target,
            html: markerHtml,
            options: AddMarkerOptions(
                interactive: .False,
                rank: .tier(.alwaysVisible)
            )
        ) { _ in }
    }
    
    // MARK: - Multi-Floor State
    
    private func loadFloors(requestID: Int, completion: @escaping () -> Void) {
        mapView.mapData.getByType(.floor) { [weak self] (floorsResult: Result<[Floor], Error>) in
            guard let self, requestID == self.routeRequestID else { return }
            
            if case .success(let floors) = floorsResult {
                self.availableFloors = floors
            } else {
                self.availableFloors = []
            }
            
            completion()
        }
    }
    
    // MARK: - Route Candidate Loading
    
    private func drawNearestSpaceRoute(
        fromCoordinate coordinate: Coordinate,
        destinationNames: [String],
        requestID: Int
    ) {
        loadFloors(requestID: requestID) { [weak self] in
            guard let self, requestID == self.routeRequestID else { return }
            self.fetchRouteCandidates(requestID: requestID) { [weak self] result in
                guard let self, requestID == self.routeRequestID else { return }
                
                switch result {
                case .success(let candidates):
                    self.initializeOptimalRouting(
                        fromCoordinate: coordinate,
                        destinationNames: destinationNames,
                        allDestinations: self.groupedDestinations(candidates),
                        requestID: requestID
                    )
                case .failure:
                    self.restartStartSelectionAfterInvalidRoute(
                        reason: "Failed to load map entities"
                    )
                }
            }
        }
    }
    
    private func fetchRouteCandidates(
        requestID: Int,
        completion: @escaping (Result<[RouteDestination], Error>) -> Void
    ) {
        fetchSpaceCandidates(requestID: requestID) { [weak self] spaceResult in
            guard let self, requestID == self.routeRequestID else { return }
            
            switch spaceResult {
            case .success(let spaceCandidates):
                self.fetchMapObjectCandidates(requestID: requestID) { [weak self] objectCandidates in
                    guard let self, requestID == self.routeRequestID else { return }
                    
                    self.fetchDoorCandidates(requestID: requestID) { [weak self] doorCandidates in
                        guard let self, requestID == self.routeRequestID else { return }
                        
                        self.fetchPointOfInterestCandidates(requestID: requestID) { [weak self] poiCandidates in
                            guard let self, requestID == self.routeRequestID else { return }
                            
                            let candidates =
                            spaceCandidates +
                            objectCandidates +
                            doorCandidates +
                            poiCandidates
                            completion(.success(candidates))
                        }
                    }
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    private func fetchSpaceCandidates(
        requestID: Int,
        completion: @escaping (Result<[RouteDestination], Error>) -> Void
    ) {
        mapView.mapData.getByType(.space) { [weak self] (result: Result<[Space], Error>) in
            guard let self, requestID == self.routeRequestID else { return }
            
            switch result {
            case .success(let spaces):
                completion(.success(self.routeDestinations(from: spaces)))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    private func fetchMapObjectCandidates(
        requestID: Int,
        completion: @escaping ([RouteDestination]) -> Void
    ) {
        mapView.mapData.getByType(.mapObject) { [weak self] (result: Result<[MapObject], Error>) in
            guard let self, requestID == self.routeRequestID else { return }
            
            if case .success(let objects) = result {
                completion(self.routeDestinations(from: objects))
                return
            }
            
            completion([])
        }
    }
    
    private func fetchDoorCandidates(
        requestID: Int,
        completion: @escaping ([RouteDestination]) -> Void
    ) {
        mapView.mapData.getByType(.door) { [weak self] (result: Result<[Door], Error>) in
            guard let self, requestID == self.routeRequestID else { return }
            
            if case .success(let doors) = result {
                completion(self.routeDestinations(from: doors))
                return
            }
            
            completion([])
        }
    }
    
    private func fetchPointOfInterestCandidates(
        requestID: Int,
        completion: @escaping ([RouteDestination]) -> Void
    ) {
        mapView.mapData.getByType(.pointOfInterest) { [weak self] (result: Result<[PointOfInterest], Error>) in
            guard let self, requestID == self.routeRequestID else { return }
            
            if case .success(let pointsOfInterest) = result {
                completion(self.routeDestinations(from: pointsOfInterest))
                return
            }
            
            completion([])
        }
    }
    
    private func routeDestinations(from spaces: [Space]) -> [RouteDestination] {
        spaces.map {
            RouteDestination(
                id: $0.id,
                name: $0.name,
                targets: [.space($0)],
                floorIds: [$0.floor]
            )
        }
    }
    
    private func routeDestinations(from mapObjects: [MapObject]) -> [RouteDestination] {
        mapObjects.map {
            RouteDestination(
                id: $0.id,
                name: $0.name,
                targets: [.mapObject($0)],
                floorIds: [$0.floor]
            )
        }
    }
    
    private func routeDestinations(from doors: [Door]) -> [RouteDestination] {
        doors.map {
            RouteDestination(
                id: $0.id,
                name: $0.name,
                targets: [.door($0)],
                floorIds: [$0.floor]
            )
        }
    }
    
    private func routeDestinations(from pointsOfInterest: [PointOfInterest]) -> [RouteDestination] {
        pointsOfInterest.map {
            var floorIds: Set<String> = [$0.floor]
            if let coordinateFloorId = $0.coordinate.floorId {
                floorIds.insert(coordinateFloorId)
            }
            
            return RouteDestination(
                id: $0.id,
                name: $0.name,
                targets: [.coordinate($0.coordinate)],
                floorIds: floorIds
            )
        }
    }
    
    // MARK: - Destination Resolution
    
    private func groupedDestinations(_ destinations: [RouteDestination]) -> [RouteDestination] {
        let grouped = Dictionary(grouping: destinations) { normalizedRouteName($0.name) }
        
        return grouped.values.compactMap { matches in
            guard let first = matches.first else { return nil }
            return RouteDestination(
                id: matches.map { $0.id }.joined(separator: ","),
                name: first.name,
                targets: matches.flatMap { $0.targets },
                floorIds: Set(matches.flatMap { $0.floorIds })
            )
        }
    }
    
    // MARK: - Route Ordering
    
    private func initializeOptimalRouting(
        fromCoordinate coordinate: Coordinate,
        destinationNames: [String],
        allDestinations: [RouteDestination],
        requestID: Int
    ) {
        guard !allDestinations.isEmpty else {
            return
        }
        
        var destinations: [RouteDestination] = []
        
        for name in destinationNames {
            if let destination = findDestination(named: name, in: allDestinations),
               !destinations.contains(where: { $0.id == destination.id }) {
                destinations.append(destination)
            }
        }
        
        guard !destinations.isEmpty else {
            return
        }
        
        let destinationFloorIds = Set(destinations.flatMap { $0.floorIds })
        let resolvedFloorIds = resolvedRouteFloorIds(
            destinationFloorIds: destinationFloorIds,
            startCoordinate: coordinate
        )
        
        isMultiFloorRouteActive = resolvedFloorIds.count > 1
        currentActiveFloors = isMultiFloorRouteActive ? resolvedFloorIds : []
        
        selectedStartCoordinate = coordinate
        determineOptimalOrder(
            startCoordinate: coordinate,
            destinations: destinations,
            requestID: requestID
        )
    }
    
    // MARK: - Destination Lookup
    
    private func findDestination(named name: String, in destinations: [RouteDestination]) -> RouteDestination? {
        let aliases = name
            .split(separator: "|")
            .map { normalizedRouteName(String($0)) }
            .filter { !$0.isEmpty }
        
        for alias in aliases {
            if let exactMatch = destinations.first(where: { normalizedRouteName($0.name) == alias }) {
                return exactMatch
            }
        }
        
        for alias in aliases {
            if let partialMatch = destinations.first(where: { destination in
                let destinationName = normalizedRouteName(destination.name)
                return destinationName.contains(alias) || alias.contains(destinationName)
            }) {
                return partialMatch
            }
        }
        
        return nil
    }
    
    // MARK: - Optimal Route Order (Greedy Nearest-Neighbor)
    
    private func determineOptimalOrder(
        startCoordinate: Coordinate,
        destinations: [RouteDestination],
        requestID: Int
    ) {
        buildOptimalOrder(
            currentTargets: [.coordinate(startCoordinate)],
            startCoordinate: startCoordinate,
            remainingDestinations: destinations,
            orderedDestinations: [],
            requestID: requestID
        )
    }
    
    // MARK: - Optimal Route Order (Greedy Nearest-Neighbor)
    
    private func buildOptimalOrder(
        currentTargets: [NavigationTarget],
        startCoordinate: Coordinate,
        remainingDestinations: [RouteDestination],
        orderedDestinations: [RouteDestination],
        requestID: Int
    ) {
        guard !remainingDestinations.isEmpty else {
            drawMultiDestinationRoute(
                startCoordinate: startCoordinate,
                destinations: orderedDestinations,
                requestID: requestID
            )
            return
        }
        
        var candidateDirections: [(destination: RouteDestination, directions: Directions, distance: Double)] = []
        var pendingDirectionsCount = remainingDestinations.count
        
        for destination in remainingDestinations {
            mapView.mapData.getDirections(
                from: currentTargets,
                to: destination.targets
            ) { [weak self] result in
                guard let self, requestID == self.routeRequestID else { return }
                
                if case .success(let directions?) = result {
                    let distance = self.totalDistance(for: directions)
                    candidateDirections.append((destination: destination, directions: directions, distance: distance))
                }
                
                pendingDirectionsCount -= 1
                
                guard pendingDirectionsCount == 0 else { return }
                guard let nearest = candidateDirections.min(by: { $0.distance < $1.distance }) else {
                    self.drawMultiDestinationRoute(
                        startCoordinate: startCoordinate,
                        destinations: orderedDestinations,
                        requestID: requestID
                    )
                    return
                }
                
                let remaining = remainingDestinations.filter { $0.name != nearest.destination.name }
                self.buildOptimalOrder(
                    currentTargets: nearest.destination.targets,
                    startCoordinate: startCoordinate,
                    remainingDestinations: remaining,
                    orderedDestinations: orderedDestinations + [nearest.destination],
                    requestID: requestID
                )
            }
        }
    }
    
    // MARK: - Route Drawing
    
    private func drawMultiDestinationRoute(
        startCoordinate: Coordinate,
        destinations: [RouteDestination],
        requestID: Int
    ) {
        guard requestID == routeRequestID else { return }
        guard !destinations.isEmpty else {
            restartStartSelectionAfterInvalidRoute(reason: "No valid destinations to route")
            return
        }
        
        let multiDestinationTargets = destinations.flatMap { destination in
            destination.targets.map { MultiDestinationTarget.single($0) }
        }
        
        mapView.mapData.getDirectionsMultiDestination(
            from: .coordinate(startCoordinate),
            to: multiDestinationTargets
        ) { [weak self] result in
            guard let self, requestID == self.routeRequestID else { return }
            
            switch result {
            case .success(let allDirections):
                guard let allDirections = allDirections, !allDirections.isEmpty else {
                    self.restartStartSelectionAfterInvalidRoute(reason: "No directions returned from multi-destination query")
                    return
                }
                
                self.renderMultiDestinationRoute(
                    allDirections: allDirections,
                    destinations: destinations,
                    startCoordinate: startCoordinate,
                    requestID: requestID
                )
            case .failure(_):
                self.restartStartSelectionAfterInvalidRoute(reason: "Multi-destination route failed")
            }
        }
    }
    
    // MARK: - Route Drawing
    
    private func renderMultiDestinationRoute(
        allDirections: [Directions],
        destinations: [RouteDestination],
        startCoordinate: Coordinate,
        requestID: Int
    ) {
        guard requestID == routeRequestID else { return }
        
        mapView.navigation.clear()
        mapView.paths.removeAll()
        mapView.markers.removeAll()
        storeMarkerDetails = []
        
        addRouteMarkers(for: allDirections, destinations: destinations, startCoordinate: startCoordinate)
        
        updateRouteFloorContext(
            allDirections: allDirections,
            destinations: destinations,
            startCoordinate: startCoordinate
        )
        
        if let firstLeg = allDirections.first {
            positionCamera(from: startCoordinate, firstLeg: firstLeg)
        }
        
        let navigationOptions = NavigationOptions(
            animatePathDrawing: true,
            createMarkers: NavigationOptions.CreateMarkers.withDefaults(
                connection: true,
                departure: false,
                destination: false
            ),
            inactivePathOptions: AddPathOptions(
                accentColor: "#e2e8f0",
                color: "#93c5fd",
                displayArrowsOnPath: false
            ),
            markerOptions: nil,
            pathOptions: AddPathOptions(
                accentColor: "white",
                color: "#4b90e2",
                displayArrowsOnPath: true
            ),
            setMapOnConnectionClick: true,
            setMapToDeparture: true
        )
        
        mapView.navigation.draw(directions: allDirections, options: navigationOptions) { [weak self] result in
            guard let self, requestID == self.routeRequestID else { return }
            
            switch result {
            case .success:
                self.syncActiveFloorsWithCurrentMapFloorIfNeeded()
            case .failure:
                self.restartStartSelectionAfterInvalidRoute(reason: "Failed to draw route")
            }
        }
    }
    
    // MARK: - Route Recovery
    
    private func restartStartSelectionAfterInvalidRoute(reason: String) {
        guard let destinations = pendingDestinationNames, !destinations.isEmpty else { return }
        
        mapView.navigation.clear()
        mapView.paths.removeAll()
        mapView.markers.removeAll()
        storeMarkerDetails = []
        selectedStartCoordinate = nil
        awaitingUserStartLocation = true
        isMultiFloorRouteActive = false
        currentActiveFloors = []
        print(reason)
    }
    
    // MARK: - Marker Rendering
    
    private func addRouteMarkers(
        for allDirections: [Directions],
        destinations: [RouteDestination],
        startCoordinate: Coordinate
    ) {
        storeMarkerDetails = []
        
        addMarkerForUserLoc(
            title: "",
            subtitle: nil,
            color: "#1871fb",
            target: startCoordinate,
            compact: true
        )
        
        for (index, directions) in allDirections.enumerated() {
            guard let lastCoordinate = directions.coordinates.last else { continue }
            
            if lastCoordinate.latitude == startCoordinate.latitude && lastCoordinate.longitude == startCoordinate.longitude {
                continue
            }
            
            guard index < destinations.count else { continue }
            let destination = destinations[index]
            
            storeMarkerDetails.append(
                StoreMarkerDetails(
                    details: StoreDetails(
                        name: destination.name,
                        imageName: "",
                        locationName: destination.name,
                        spaceId: destination.id,
                        coordinates: (lastCoordinate.latitude, lastCoordinate.longitude)
                    ),
                    coordinate: lastCoordinate
                )
            )
            
            let html = MarkerHTMLGenerator.customDestinationMarkerHTML(imageSrc: "", destinationId: destination.id)
            
            mapView.markers.add(
                target: lastCoordinate,
                html: html,
                options: AddMarkerOptions(
                    interactive: .True,
                    rank: .tier(.alwaysVisible)
                )
            ) { _ in }
        }
    }
    
    // MARK: - Marker Selection
    
    private func nearestStoreMarker(to coordinate: Coordinate, maxDistanceSquared: Double) -> StoreMarkerDetails? {
        guard let nearest = storeMarkerDetails.min(by: { first, second in
            distanceSquared(from: coordinate, to: first.coordinate) < distanceSquared(from: coordinate, to: second.coordinate)
        }) else {
            return nil
        }
        
        guard distanceSquared(from: coordinate, to: nearest.coordinate) <= maxDistanceSquared else {
            return nil
        }
        
        return nearest
    }
    
    private func distanceSquared(from first: Coordinate, to second: Coordinate) -> Double {
        let latitudeDifference = first.latitude - second.latitude
        let longitudeDifference = first.longitude - second.longitude
        return latitudeDifference * latitudeDifference + longitudeDifference * longitudeDifference
    }
    
    // MARK: - Camera
    
    private func positionCamera(from: Coordinate, firstLeg: Directions) {
        guard let toCoordinate = firstLeg.coordinates.last else {
            positionCameraDefault(from: from)
            return
        }
        
        let bearing = calculateBearing(from: from, to: toCoordinate)
        
        let cameraTarget = CameraTarget(
            bearing: bearing,
            center: from,
            pitch: isMultiFloorRouteActive ? MULTI_FLOOR_CAMERA_PITCH : CAMERA_PITCH,
            zoomLevel: CAMERA_ZOOM
        )
        
        mapView.camera.set(target: cameraTarget) { _ in }
    }
    
    private func positionCameraDefault(from: Coordinate) {
        let cameraTarget = CameraTarget(
            bearing: DEFAULT_BEARING,
            center: from,
            pitch: isMultiFloorRouteActive ? MULTI_FLOOR_CAMERA_PITCH : CAMERA_PITCH,
            zoomLevel: CAMERA_ZOOM
        )
        
        mapView.camera.set(target: cameraTarget) { _ in }
    }
    
    private func calculateBearing(from: Coordinate, to: Coordinate) -> Double {
        let angleDegrees = (180.0 / .pi) * atan2(
            to.longitude - from.longitude,
            to.latitude - from.latitude
        )
        let bearing = (angleDegrees + BEARING_OFFSET).truncatingRemainder(dividingBy: 360.0)
        return bearing >= 0 ? bearing : bearing + 360.0
    }
    
    // MARK: - Route Math
    
    private func totalDistance(for directions: Directions) -> Double {
        directions.instructions.reduce(0) { total, instruction in
            total + instruction.distance
        }
    }
    
    private func resolvedRouteFloorIds(destinationFloorIds: Set<String>, startCoordinate: Coordinate) -> Set<String> {
        var floorIds = destinationFloorIds
        if let startFloorId = startCoordinate.floorId {
            floorIds.insert(startFloorId)
        }
        return floorIds
    }
    
    private func updateRouteFloorContext(
        allDirections: [Directions],
        destinations: [RouteDestination],
        startCoordinate: Coordinate
    ) {
        let directionFloorIds = Set(allDirections.flatMap { direction in
            direction.coordinates.compactMap(\.floorId)
        })
        let destinationFloorIds = Set(destinations.flatMap { $0.floorIds })
        
        var routeFloorIds = directionFloorIds.union(destinationFloorIds)
        if let startFloorId = startCoordinate.floorId {
            routeFloorIds.insert(startFloorId)
        }
        
        guard routeFloorIds.count > 1 else {
            isMultiFloorRouteActive = false
            currentActiveFloors = []
            return
        }
        
        isMultiFloorRouteActive = true
        currentActiveFloors = routeFloorIds
        
        let preferredFloorId = startCoordinate.floorId
        ?? allDirections.first?.coordinates.first?.floorId
        ?? allDirections.first?.coordinates.last?.floorId
        
        applyMultiFloorVisibility(
            activeFloorIds: routeFloorIds,
            focusFloorId: preferredFloorId,
            shouldSetFloor: true
        )
    }
    
    private func syncActiveFloorsWithCurrentMapFloorIfNeeded() {
        guard isMultiFloorRouteActive, !currentActiveFloors.isEmpty else { return }
        
        mapView.currentFloor { [weak self] result in
            guard let self else { return }
            if case .success(let floor?) = result {
                self.applyMultiFloorVisibility(
                    activeFloorIds: self.currentActiveFloors,
                    focusFloorId: floor.id,
                    shouldSetFloor: false
                )
            }
        }
    }
    
    private func applyMultiFloorVisibility(
        activeFloorIds: Set<String>,
        focusFloorId: String?,
        shouldSetFloor: Bool
    ) {
        guard !availableFloors.isEmpty else { return }
        
        for floor in availableFloors {
            let isVisible = activeFloorIds.contains(floor.id)
            mapView.updateState(
                floor: floor,
                state: floorVisibilityState(isVisible: isVisible)
            ) { _ in
                // TODO: Handle the updateState completion callback if any post-update logic is required in the future.
            }
        }
        
        if shouldSetFloor,
           let focusFloorId,
           activeFloorIds.contains(focusFloorId) {
            mapView.setFloor(floorId: focusFloorId) { _ in
                // TODO: Handle the setFloor completion callback if any update logic is required in the future.
            }
        }
    }
    
    private func floorVisibilityState(isVisible: Bool) -> FloorUpdateState {
        FloorUpdateState(
            type: nil,
            altitude: nil,
            visible: isVisible,
            areas: nil,
            footprint: nil,
            geometry: nil,
            images: nil,
            labels: nil,
            markers: nil,
            occlusion: nil,
            paths: nil
        )
    }
    
    // MARK: - String Normalization
    
    private func normalizedRouteName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    // MARK: - Blue Dot Entry
    private func resolveBlueDotCoordinate(
        forStaticItem itemName: String,
        completion: @escaping (Coordinate?) -> Void
    ) {
        // 1) Resolve selected item -> destination target(s), then place on a walkable path point.
        let aliases = staticItemAliases(for: itemName)

        fetchBlueDotCandidates { [weak self] candidates in
            guard let self else {
                completion(nil)
                return
            }

            let lookupName = aliases.joined(separator: "|")
            let groupedCandidates = self.groupedDestinations(candidates)

            guard let destination = self.findDestination(named: lookupName, in: groupedCandidates),
                  self.productCoordinate(for: destination) != nil || !destination.targets.isEmpty else {
                completion(nil)
                return
            }

            self.resolveAccessiblePathCoordinate(for: destination, completion: completion)
        }
    }

    // Same blue-dot flow as static item path; only destination lookup changes to External ID.
    private func resolveBlueDotCoordinate(
        forVusionAisle aisle: String,
        module: String,
        completion: @escaping (Coordinate?) -> Void
    ) {
        let externalID = ExternalIDBlueDotResolver.buildExternalID(aisle: aisle, module: module)
        guard !externalID.isEmpty else {
            completion(nil)
            return
        }

        mapView.mapData.getByType(.space) { [weak self] (result: Result<[Space], Error>) in
            guard let self else {
                completion(nil)
                return
            }

            guard case .success(let spaces) = result,
                  let resolvedSpace = ExternalIDBlueDotResolver.resolveSpace(by: externalID, in: spaces) else {
                completion(nil)
                return
            }

            let destination = RouteDestination(
                id: resolvedSpace.id,
                name: resolvedSpace.name,
                targets: [.space(resolvedSpace)],
                floorIds: [resolvedSpace.floor]
            )

            self.resolveAccessiblePathCoordinate(for: destination, completion: completion)
        }
    }

    // MARK: - Blue Dot Marker Rendering
    private func renderUserBlueDot(at coordinate: Coordinate) {
        DispatchQueue.main.async {
            self.addMarkerForUserLoc(
                title: "",
                subtitle: nil,
                color: STATIC_BLUE_DOT_COLOR,
                target: coordinate,
                compact: true
            )
        }
    }

    // MARK: - Blue Dot Item Alias Mapping
    private func staticItemAliases(for itemName: String) -> [String] {
        var aliases = [itemName]

        if let matchingItem = ShoppingItemsProvider.shared
            .getItems()
            .first(where: { normalizedRouteName($0.name) == normalizedRouteName(itemName) }) {
            aliases.append(matchingItem.storeName)
        }

        var seen = Set<String>()
        return aliases.filter {
            let normalized = normalizedRouteName($0)
            guard !normalized.isEmpty, !seen.contains(normalized) else { return false }
            seen.insert(normalized)
            return true
        }
    }

    // MARK: - Blue Dot Destination Candidate Fetch
    private func fetchBlueDotCandidates(completion: @escaping ([RouteDestination]) -> Void) {
        mapView.mapData.getByType(.space) { [weak self] (spaceResult: Result<[Space], Error>) in
            guard let self else {
                completion([])
                return
            }

            let spaceCandidates: [RouteDestination]
            if case .success(let spaces) = spaceResult {
                spaceCandidates = self.routeDestinations(from: spaces)
            } else {
                spaceCandidates = []
            }

            self.mapView.mapData.getByType(.mapObject) { [weak self] (objectResult: Result<[MapObject], Error>) in
                guard let self else {
                    completion([])
                    return
                }

                let objectCandidates: [RouteDestination]
                if case .success(let objects) = objectResult {
                    objectCandidates = self.routeDestinations(from: objects)
                } else {
                    objectCandidates = []
                }

                self.mapView.mapData.getByType(.door) { [weak self] (doorResult: Result<[Door], Error>) in
                    guard let self else {
                        completion([])
                        return
                    }

                    let doorCandidates: [RouteDestination]
                    if case .success(let doors) = doorResult {
                        doorCandidates = self.routeDestinations(from: doors)
                    } else {
                        doorCandidates = []
                    }

                    self.mapView.mapData.getByType(.pointOfInterest) { [weak self] (poiResult: Result<[PointOfInterest], Error>) in
                        guard let self else {
                            completion([])
                            return
                        }

                        let poiCandidates: [RouteDestination]
                        if case .success(let pointsOfInterest) = poiResult {
                            poiCandidates = self.routeDestinations(from: pointsOfInterest)
                        } else {
                            poiCandidates = []
                        }

                        completion(spaceCandidates + objectCandidates + doorCandidates + poiCandidates)
                    }
                }
            }
        }
    }

    // MARK: - Blue Dot Destination Coordinate Extraction
    private func productCoordinate(for destination: RouteDestination) -> Coordinate? {
        for target in prioritizedTargets(for: destination) {
            if let coordinate = coordinate(for: target) {
                return coordinate
            }
        }

        for target in destination.targets {
            if let coordinate = coordinate(for: target) {
                return coordinate
            }
        }
        return nil
    }

    // MARK: - Blue Dot Target Prioritization
    private func prioritizedTargets(for destination: RouteDestination) -> [NavigationTarget] {
        let nonSpaceTargets = destination.targets.filter {
            if case .space = $0 { return false }
            return true
        }
        return nonSpaceTargets.isEmpty ? destination.targets : nonSpaceTargets
    }

    // MARK: - Blue Dot NavigationTarget -> Coordinate
    private func coordinate(for target: NavigationTarget) -> Coordinate? {
        switch target {
        case .coordinate(let coordinate):
            return coordinate
        case .space(let space):
            return spaceCenterCoordinate(for: space)
        case .mapObject(let mapObject):
            return firstCoordinate(in: mapObject, preferredLabels: ["center", "coordinate"], maxDepth: 4)
        case .door(let door):
            return firstCoordinate(in: door, preferredLabels: ["center", "coordinate"], maxDepth: 4)
        default:
            return nil
        }
    }

    // MARK: - Blue Dot Path Resolution
    private func resolveAccessiblePathCoordinate(
        for destination: RouteDestination,
        completion: @escaping (Coordinate?) -> Void
    ) {
        // 2) Fast path: ask Mappedin for nearest spaces around destination coordinate.
        guard let destinationCoordinate = productCoordinate(for: destination) else {
            completion(nil)
            return
        }

        fetchNearestAnchorSpaces(
            from: destinationCoordinate,
            destinationFloorIds: destination.floorIds
        ) { [weak self] nearestAnchors in
            guard let self else {
                completion(nil)
                return
            }

            let destinationTargets = self.prioritizedTargets(for: destination)

            if !nearestAnchors.isEmpty {
                self.computeBestDirections(from: nearestAnchors, to: destinationTargets) { [weak self] bestDirections in
                    guard let self else {
                        completion(nil)
                        return
                    }

                    if let bestDirections {
                        // 3) Keep existing placement rule so dot lands on path/space based on target type.
                        completion(self.pathCoordinateForBlueDot(directions: bestDirections, destination: destination))
                    } else {
                        self.resolveAccessiblePathCoordinateWithAllSpaces(
                            for: destination,
                            destinationTargets: destinationTargets,
                            completion: completion
                        )
                    }
                }
                return
            }

            self.resolveAccessiblePathCoordinateWithAllSpaces(
                for: destination,
                destinationTargets: destinationTargets,
                completion: completion
            )
        }
    }

    // MARK: - Blue Dot Full-Space Fallback Resolution
    private func resolveAccessiblePathCoordinateWithAllSpaces(
        for destination: RouteDestination,
        destinationTargets: [NavigationTarget],
        completion: @escaping (Coordinate?) -> Void
    ) {
        // Fallback: previous full-space approach retained for resilience.
        mapView.mapData.getByType(.space) { [weak self] (result: Result<[Space], Error>) in
            guard let self else {
                completion(nil)
                return
            }

            guard case .success(let spaces) = result else {
                completion(self.productCoordinate(for: destination))
                return
            }

            let anchors = self.anchorSpaces(for: destination, from: spaces)
            guard !anchors.isEmpty else {
                completion(self.productCoordinate(for: destination))
                return
            }

            self.computeBestDirections(from: anchors, to: destinationTargets) { [weak self] bestDirections in
                guard let self else {
                    completion(nil)
                    return
                }

                if let bestDirections {
                    completion(self.pathCoordinateForBlueDot(directions: bestDirections, destination: destination))
                } else {
                    self.resolveFallbackPathCoordinate(
                        for: destination,
                        anchors: anchors,
                        spaces: spaces,
                        completion: completion
                    )
                }
            }
        }
    }

    // MARK: - Blue Dot Nearest Space Query
    private func fetchNearestAnchorSpaces(
        from coordinate: Coordinate,
        destinationFloorIds: Set<String>,
        completion: @escaping ([Space]) -> Void
    ) {
        // Nearest API result shape may vary by SDK version; reflection keeps this robust.
        mapView.mapData.query.nearest(
            origin: coordinate,
            include: [.space],
            options: nil
        ) { result in
            guard case .success(let nearestResults?) = result, !nearestResults.isEmpty else {
                completion([])
                return
            }

            let spaces = self.extractSpaces(fromNearestResults: nearestResults)
            guard !spaces.isEmpty else {
                completion([])
                return
            }

            let floorFiltered: [Space]
            if destinationFloorIds.isEmpty {
                floorFiltered = spaces
            } else {
                floorFiltered = spaces.filter { destinationFloorIds.contains($0.floor) }
            }

            completion(Array(floorFiltered.prefix(BLUE_DOT_ANCHOR_SPACE_LIMIT)))
        }
    }

    // MARK: - Blue Dot Nearest Query Parsing
    private func extractSpaces(fromNearestResults nearestResults: [FindNearestResult]) -> [Space] {
        var seen = Set<String>()
        var spaces: [Space] = []

        for result in nearestResults {
            if let space = firstSpace(in: result, maxDepth: 4), !seen.contains(space.id) {
                seen.insert(space.id)
                spaces.append(space)
            }
        }

        return spaces
    }

    // MARK: - Blue Dot Reflection Helpers
    private func firstSpace(in value: Any, maxDepth: Int) -> Space? {
        guard maxDepth >= 0 else { return nil }

        if let space = value as? Space {
            return space
        }

        let mirror = Mirror(reflecting: value)
        guard !mirror.children.isEmpty else { return nil }

        for child in mirror.children {
            if let space = firstSpace(in: child.value, maxDepth: maxDepth - 1) {
                return space
            }
        }

        return nil
    }

    // MARK: - Blue Dot Route Fallback
    private func resolveFallbackPathCoordinate(
        for destination: RouteDestination,
        anchors: [Space],
        spaces: [Space],
        completion: @escaping (Coordinate?) -> Void
    ) {
        guard let destinationSpace = destinationSpace(for: destination, within: spaces), !anchors.isEmpty else {
            completion(productCoordinate(for: destination))
            return
        }

        computeBestDirections(from: anchors, to: [.space(destinationSpace)]) { [weak self] bestDirections in
            guard let self else {
                completion(nil)
                return
            }

            if let bestDirections {
                completion(self.pathCoordinateForBlueDot(directions: bestDirections, destination: destination))
            } else {
                completion(self.productCoordinate(for: destination))
            }
        }
    }

    // MARK: - Blue Dot Destination Space Resolution
    private func destinationSpace(for destination: RouteDestination, within spaces: [Space]) -> Space? {
        for target in destination.targets {
            if case .space(let spaceTarget) = target {
                return spaceTarget
            }
        }

        guard let destinationCoordinate = productCoordinate(for: destination) else { return nil }

        let floorFilteredSpaces: [Space]
        if destination.floorIds.isEmpty {
            floorFilteredSpaces = spaces
        } else {
            floorFilteredSpaces = spaces.filter { destination.floorIds.contains($0.floor) }
        }

        return floorFilteredSpaces
            .compactMap { space -> (space: Space, center: Coordinate)? in
                guard let center = spaceCenterCoordinate(for: space) else { return nil }
                return (space: space, center: center)
            }
            .min { first, second in
                distanceSquared(from: destinationCoordinate, to: first.center) < distanceSquared(from: destinationCoordinate, to: second.center)
            }?
            .space
    }

    // MARK: - Blue Dot Anchor Selection
    private func anchorSpaces(for destination: RouteDestination, from spaces: [Space]) -> [Space] {
        let floorFilteredSpaces: [Space]
        if destination.floorIds.isEmpty {
            floorFilteredSpaces = spaces
        } else {
            floorFilteredSpaces = spaces.filter { destination.floorIds.contains($0.floor) }
        }

        guard let destinationCoordinate = productCoordinate(for: destination) else {
            return Array(floorFilteredSpaces.prefix(BLUE_DOT_ANCHOR_SPACE_LIMIT))
        }

        let sorted = floorFilteredSpaces.sorted { lhs, rhs in
            let lhsDistance = spaceCenterCoordinate(for: lhs).map { distanceSquared(from: destinationCoordinate, to: $0) } ?? Double.greatestFiniteMagnitude
            let rhsDistance = spaceCenterCoordinate(for: rhs).map { distanceSquared(from: destinationCoordinate, to: $0) } ?? Double.greatestFiniteMagnitude
            return lhsDistance < rhsDistance
        }

        return Array(sorted.prefix(BLUE_DOT_ANCHOR_SPACE_LIMIT))
    }

    // MARK: - Blue Dot Direction Selection
    private func computeBestDirections(
        from anchors: [Space],
        to targets: [NavigationTarget],
        completion: @escaping (Directions?) -> Void
    ) {
        guard !anchors.isEmpty else {
            completion(nil)
            return
        }

        var pending = anchors.count
        var bestDirections: Directions?
        var bestDistance = Double.greatestFiniteMagnitude

        for anchor in anchors {
            mapView.mapData.getDirections(
                from: [.space(anchor)],
                to: targets
            ) { [weak self] directionResult in
                guard let self else {
                    pending -= 1
                    if pending == 0 { completion(bestDirections) }
                    return
                }

                if case .success(let directions?) = directionResult,
                   !directions.coordinates.isEmpty {
                    let distance = self.totalDistance(for: directions)
                    if distance < bestDistance {
                        bestDistance = distance
                        bestDirections = directions
                    }
                }

                pending -= 1
                if pending == 0 {
                    completion(bestDirections)
                }
            }
        }
    }

    // MARK: - Blue Dot Coordinate Selection Rules
    private func pathCoordinateForBlueDot(directions: Directions, destination: RouteDestination) -> Coordinate? {
        guard !directions.coordinates.isEmpty else { return nil }

        if shouldPlaceBlueDotInsideDestinationSpace(for: destination) {
            return directions.coordinates.last
        }

        var index = max(0, directions.coordinates.count - 1 - endpointBackstep(for: destination))

        guard let destinationCoordinate = productCoordinate(for: destination) else {
            return directions.coordinates[index]
        }

        while index > 0,
              distanceSquared(from: directions.coordinates[index], to: destinationCoordinate) < BLUE_DOT_MIN_DISTANCE_FROM_DESTINATION_SQUARED {
            index -= 1
        }

        return directions.coordinates[index]
    }

    // MARK: - Blue Dot Coordinate Selection Rules
    private func endpointBackstep(for destination: RouteDestination) -> Int {
        let hasCoordinateTarget = destination.targets.contains {
            if case .coordinate = $0 { return true }
            return false
        }
        return hasCoordinateTarget ? BLUE_DOT_POI_BACKSTEP : BLUE_DOT_DEFAULT_BACKSTEP
    }

    // MARK: - Blue Dot Coordinate Selection Rules
    private func shouldPlaceBlueDotInsideDestinationSpace(for destination: RouteDestination) -> Bool {
        let hasSpaceTarget = destination.targets.contains {
            if case .space = $0 { return true }
            return false
        }
        let hasCoordinateTarget = destination.targets.contains {
            if case .coordinate = $0 { return true }
            return false
        }
        return hasSpaceTarget && !hasCoordinateTarget
    }

    // MARK: - Blue Dot Coordinate Geometry Helpers
    private func nearestSpaceCenterCoordinate(
        in spaces: [Space],
        from referenceCoordinate: Coordinate?
    ) -> Coordinate? {
        let centers = spaces.compactMap { space in
            spaceCenterCoordinate(for: space)
        }

        guard !centers.isEmpty else { return nil }
        guard let referenceCoordinate else { return centers.first }

        return centers.min { first, second in
            distanceSquared(from: referenceCoordinate, to: first) < distanceSquared(from: referenceCoordinate, to: second)
        }
    }

    // MARK: - Blue Dot Coordinate Geometry Helpers
    private func spaceCenterCoordinate(for space: Space) -> Coordinate? {
        firstCoordinate(in: space, preferredLabels: ["center", "coordinate"], maxDepth: 4)
    }

    // MARK: - Blue Dot Coordinate Geometry Helpers
    private func firstCoordinate(
        in value: Any,
        preferredLabels: [String],
        maxDepth: Int
    ) -> Coordinate? {
        guard maxDepth >= 0 else { return nil }

        if let coordinate = value as? Coordinate {
            return coordinate
        }

        let mirror = Mirror(reflecting: value)
        guard !mirror.children.isEmpty else { return nil }

        let prioritizedChildren = mirror.children.sorted { lhs, rhs in
            priority(for: lhs.label, preferredLabels: preferredLabels) < priority(for: rhs.label, preferredLabels: preferredLabels)
        }

        for child in prioritizedChildren {
            if let coordinate = firstCoordinate(
                in: child.value,
                preferredLabels: preferredLabels,
                maxDepth: maxDepth - 1
            ) {
                return coordinate
            }
        }

        return nil
    }

    // MARK: - Blue Dot Coordinate Geometry Helpers
    private func priority(for label: String?, preferredLabels: [String]) -> Int {
        guard let label else { return Int.max }
        if let index = preferredLabels.firstIndex(where: { $0.caseInsensitiveCompare(label) == .orderedSame }) {
            return index
        }
        return Int.max - 1
    }

    // MARK: - Blue Dot Matching Helpers
    private func matchesAnyAlias(_ value: String, aliases: [String]) -> Bool {
        let normalizedValue = normalizedRouteName(value)
        return aliases.contains { alias in
            let normalizedAlias = normalizedRouteName(alias)
            guard !normalizedAlias.isEmpty else { return false }
            return normalizedValue == normalizedAlias
                || normalizedValue.contains(normalizedAlias)
                || normalizedAlias.contains(normalizedValue)
        }
    }
}
