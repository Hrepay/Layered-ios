import Foundation
import CoreLocation

/// 현재 위치 1회 조회 헬퍼. 권한이 없으면 요청하고, 거부되면 nil 반환 (throw 안 함).
/// 장소 검색의 "내 주변" 필터 전용 — 지속 추적은 하지 않는다.
@MainActor
final class CurrentLocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocationCoordinate2D?, Never>?
    private var authContinuation: CheckedContinuation<Bool, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// 권한 확인/요청 후 현재 좌표를 1회 반환. 실패·거부 시 nil.
    func requestCurrentLocation() async -> CLLocationCoordinate2D? {
        let status = manager.authorizationStatus
        switch status {
        case .notDetermined:
            let granted = await withCheckedContinuation { continuation in
                authContinuation = continuation
                manager.requestWhenInUseAuthorization()
            }
            guard granted else { return nil }
        case .denied, .restricted:
            return nil
        default:
            break
        }
        return await withCheckedContinuation { continuation in
            locationContinuation = continuation
            manager.requestLocation()
        }
    }

    var isDenied: Bool {
        let status = manager.authorizationStatus
        return status == .denied || status == .restricted
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        guard status != .notDetermined else { return }
        let granted = status == .authorizedWhenInUse || status == .authorizedAlways
        Task { @MainActor in
            authContinuation?.resume(returning: granted)
            authContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let coordinate = locations.first?.coordinate
        Task { @MainActor in
            locationContinuation?.resume(returning: coordinate)
            locationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            locationContinuation?.resume(returning: nil)
            locationContinuation = nil
        }
    }
}
