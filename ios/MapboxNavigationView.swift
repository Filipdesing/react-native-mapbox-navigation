
import MapboxCoreNavigation
import MapboxNavigation
import MapboxDirections

extension UIView {
    var parentViewController: UIViewController? {
        var parentResponder: UIResponder? = self
        while parentResponder != nil {
            parentResponder = parentResponder!.next
            if let viewController = parentResponder as? UIViewController {
                return viewController
            }
        }
        return nil
    }
}

public protocol MapboxCarPlayDelegate {
    func connect(with navigationView: MapboxNavigationView)
    func disconnect()
}

public protocol MapboxCarPlayNavigationDelegate {
    func startNavigation(with navigationView: MapboxNavigationView)
    func endNavigation()
}

public class MapboxNavigationView: UIView, NavigationViewControllerDelegate {
    public weak var navViewController: NavigationViewController?
    public var indexedRouteResponse: IndexedRouteResponse?
    
    var embedded: Bool
    var embedding: Bool

    @objc public var startOrigin: NSArray = [] {
        didSet { setNeedsLayout() }
    }
    
    var waypoints: [Waypoint] = [] {
        didSet { setNeedsLayout() }
    }
    
    func setWaypoints(waypoints: [MapboxWaypoint]) {
      self.waypoints = waypoints.enumerated().map { (index, waypointData) in
          let name = waypointData.name as? String ?? "\(index)"
          let waypoint = Waypoint(coordinate: waypointData.coordinate, name: name)
          waypoint.separatesLegs = waypointData.separatesLegs
          return waypoint
      }
    }
    
    @objc var destination: NSArray = [] {
        didSet { setNeedsLayout() }
    }
    
    @objc var shouldSimulateRoute: Bool = false
    @objc var showsEndOfRouteFeedback: Bool = false
    @objc var showCancelButton: Bool = false
    @objc var hideStatusView: Bool = false
    @objc var mute: Bool = false
    @objc var distanceUnit: NSString = "imperial"
    @objc var language: NSString = "us"
    @objc var destinationTitle: NSString = "Destination"
    @objc var travelMode: NSString = "driving-traffic"
    /// JSON string of a Mapbox Directions API v5 response. When set, the SDK
    /// skips its own Directions request and navigates the supplied route.
    /// Required for truck routing — pass a HERE-planned route converted to the
    /// Mapbox Directions format. While this is set, the SDK's internal
    /// rerouter is suppressed (see `shouldRerouteFrom`). Mid-trip reroutes
    /// arrive as a new customRoute string — we tear down and re-embed.
    @objc var customRoute: NSString? {
        didSet {
            if oldValue == customRoute { return }
            if embedded {
                // Brute-force swap: tear down + re-embed. Less smooth than
                // navigationService.router.updateRoute(...), but reliable
                // without an active iOS test rig. Candidate for polish.
                navViewController?.willMove(toParent: nil)
                navViewController?.view.removeFromSuperview()
                navViewController?.removeFromParent()
                navViewController = nil
                embedded = false
            }
            setNeedsLayout()
        }
    }

    @objc var onLocationChange: RCTDirectEventBlock?
    @objc var onRouteProgressChange: RCTDirectEventBlock?
    @objc var onError: RCTDirectEventBlock?
    @objc var onCancelNavigation: RCTDirectEventBlock?
    @objc var onArrive: RCTDirectEventBlock?
    @objc var vehicleMaxHeight: NSNumber?
    @objc var vehicleMaxWidth: NSNumber?

    override init(frame: CGRect) {
        self.embedded = false
        self.embedding = false
        super.init(frame: frame)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func layoutSubviews() {
        super.layoutSubviews()

        if (navViewController == nil && !embedding && !embedded) {
            embed()
        } else {
            navViewController?.view.frame = bounds
        }
    }

    public override func removeFromSuperview() {
        super.removeFromSuperview()
        // cleanup and teardown any existing resources
        self.navViewController?.removeFromParent()
        
        // MARK: End CarPlay Navigation
        if let carPlayNavigation = UIApplication.shared.delegate as? MapboxCarPlayNavigationDelegate {
            carPlayNavigation.endNavigation()
        }
        NotificationCenter.default.removeObserver(self, name: .navigationSettingsDidChange, object: nil)
    }

    private func embed() {
        guard startOrigin.count == 2 && destination.count == 2 else { return }

        embedding = true

        let originWaypoint = Waypoint(coordinate: CLLocationCoordinate2D(latitude: startOrigin[1] as! CLLocationDegrees, longitude: startOrigin[0] as! CLLocationDegrees))
        var waypointsArray = [originWaypoint]

        // Add Waypoints
        waypointsArray.append(contentsOf: waypoints)

        let destinationWaypoint = Waypoint(coordinate: CLLocationCoordinate2D(latitude: destination[1] as! CLLocationDegrees, longitude: destination[0] as! CLLocationDegrees), name: destinationTitle as String)
        waypointsArray.append(destinationWaypoint)

        let profile: MBDirectionsProfileIdentifier

        switch travelMode {
            case "cycling":
                profile = .cycling
            case "walking":
                profile = .walking
            case "driving-traffic":
                profile = .automobileAvoidingTraffic
            default:
                profile = .automobile
        }

        let options = NavigationRouteOptions(waypoints: waypointsArray, profileIdentifier: profile)

        let locale = self.language.replacingOccurrences(of: "-", with: "_")
        options.locale = Locale(identifier: locale)
        options.distanceMeasurementSystem =  distanceUnit == "imperial" ? .imperial : .metric

        // Branch: if the JS layer supplied a pre-computed route (truck-aware,
        // built externally via HERE Routing), decode and use it directly.
        // Otherwise fall through to Directions.shared.calculateRoutes.
        if let json = customRoute as String?, !json.isEmpty {
            do {
                guard let data = json.data(using: .utf8) else {
                    throw NSError(domain: "MapboxNav", code: 1, userInfo: [NSLocalizedDescriptionKey: "customRoute is not valid UTF-8"])
                }
                let decoder = JSONDecoder()
                decoder.userInfo[.options] = options
                let routeResponse = try decoder.decode(RouteResponse.self, from: data)
                let indexed = IndexedRouteResponse(routeResponse: routeResponse, routeIndex: 0)
                self.startNavigation(with: indexed)
                return
            } catch {
                onError?(["message": "Failed to parse customRoute: \(error.localizedDescription)"])
                embedding = false
                return
            }
        }

        Directions.shared.calculateRoutes(options: options) { [weak self] result in
            guard let strongSelf = self else { return }

            switch result {
            case .failure(let error):
                strongSelf.onError!(["message": error.localizedDescription])
                strongSelf.embedding = false
            case .success(let response):
                strongSelf.startNavigation(with: response)
            }
        }
    }

    /// Spin up the NavigationViewController for a ready-to-go route response.
    /// Used both by the standard Directions flow and by the customRoute path.
    private func startNavigation(with response: IndexedRouteResponse) {
        guard let parentVC = parentViewController else {
            embedding = false
            return
        }

        indexedRouteResponse = response
        let navigationOptions = NavigationOptions(simulationMode: shouldSimulateRoute ? .always : .never)
        let vc = NavigationViewController(for: response, navigationOptions: navigationOptions)

        vc.showsEndOfRouteFeedback = showsEndOfRouteFeedback
        StatusView.appearance().isHidden = hideStatusView

        NavigationSettings.shared.voiceMuted = mute
        NavigationSettings.shared.distanceUnit = distanceUnit == "imperial" ? .mile : .kilometer

        vc.delegate = self

        parentVC.addChild(vc)
        addSubview(vc.view)
        vc.view.frame = bounds
        vc.didMove(toParent: parentVC)
        navViewController = vc

        embedding = false
        embedded = true

        if let carPlayNavigation = UIApplication.shared.delegate as? MapboxCarPlayNavigationDelegate {
            carPlayNavigation.startNavigation(with: self)
        }
    }

    public func navigationViewController(_ navigationViewController: NavigationViewController, didUpdate progress: RouteProgress, with location: CLLocation, rawLocation: CLLocation) {
        onLocationChange?([
            "longitude": location.coordinate.longitude,
            "latitude": location.coordinate.latitude,
            "heading": 0,
            "accuracy": location.horizontalAccuracy.magnitude
        ])
        onRouteProgressChange?([
            "distanceTraveled": progress.distanceTraveled,
            "durationRemaining": progress.durationRemaining,
            "fractionTraveled": progress.fractionTraveled,
            "distanceRemaining": progress.distanceRemaining
        ])
    }

    public func navigationViewControllerDidDismiss(_ navigationViewController: NavigationViewController, byCanceling canceled: Bool) {
        if (!canceled) {
            return;
        }
        onCancelNavigation?(["message": "Navigation Cancel"]);
    }

    public func navigationViewController(_ navigationViewController: NavigationViewController, didArriveAt waypoint: Waypoint) -> Bool {
        onArrive?([
          "name": waypoint.name ?? waypoint.description,
          "longitude": waypoint.coordinate.latitude,
          "latitude": waypoint.coordinate.longitude,
        ])
        return true;
    }

    /// Suppress Mapbox's built-in rerouter whenever we're driving a custom
    /// (externally-planned) route. Otherwise the SDK would silently fall back
    /// to its car-only Directions API and could route a truck onto an unsafe
    /// road. Reroutes are handled by the app: it asks the backend for a new
    /// HERE truck-aware route and pushes a fresh customRoute string.
    public func navigationViewController(_ navigationViewController: NavigationViewController, shouldRerouteFrom location: CLLocation) -> Bool {
        if let json = customRoute as String?, !json.isEmpty {
            return false
        }
        return true
    }
}
