// Copyright 2026 Link Dupont
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import CoreLocation
import MapKit

/// Provides on-demand location descriptions for prompt context.
///
/// Uses `CLLocationManager.requestLocation()` for a single fix and
/// `MKReverseGeocodingRequest` to produce a human-readable place name
/// (e.g. "Durham, North Carolina, United States"). Results are cached
/// for five minutes to avoid redundant lookups.
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    private var cachedDescription: String?
    private var cacheTimestamp: Date?
    private let cacheDuration: TimeInterval = 300

    private var locationContinuation: CheckedContinuation<CLLocation?, Never>?

    /// The current authorization status reported by Core Location.
    var authorizationStatus: CLAuthorizationStatus { manager.authorizationStatus }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    /// Triggers the macOS location permission prompt (if needed) and
    /// pre-warms the cache so the location is ready for the next message.
    ///
    /// On macOS, `requestWhenInUseAuthorization()` alone does not show a
    /// dialog. The system prompts automatically when `requestLocation()` is
    /// called with undetermined status, so we call through to
    /// `currentLocationDescription()` which does exactly that.
    func requestPermissionAndPrefetch() {
        Task {
            _ = await currentLocationDescription()
        }
    }

    /// Returns a human-readable location string, or `nil` if unavailable.
    func currentLocationDescription() async -> String? {
        if let cached = cachedDescription,
           let timestamp = cacheTimestamp,
           Date().timeIntervalSince(timestamp) < cacheDuration {
            return cached
        }

        guard let location = await requestSingleLocation() else { return nil }
        guard let request = MKReverseGeocodingRequest(location: location) else { return nil }

        let locationString: String? = try? await withCheckedThrowingContinuation { continuation in
            request.getMapItems { items, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let result = items?.first?.addressRepresentations?.cityWithContext(.full)
                continuation.resume(returning: result)
            }
        }

        guard let description = locationString, !description.isEmpty else { return nil }
        cachedDescription = description
        cacheTimestamp = Date()
        return description
    }

    // MARK: - Private

    private func requestSingleLocation() async -> CLLocation? {
        guard CLLocationManager.locationServicesEnabled() else { return nil }

        let status = manager.authorizationStatus
        guard status != .denied, status != .restricted else { return nil }

        return await withCheckedContinuation { continuation in
            locationContinuation = continuation
            manager.requestLocation()
        }
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        MainActor.assumeIsolated {
            locationContinuation?.resume(returning: locations.last)
            locationContinuation = nil
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        MainActor.assumeIsolated {
            locationContinuation?.resume(returning: nil)
            locationContinuation = nil
        }
    }
}
