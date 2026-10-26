import AVFoundation
import VisionKit

enum CameraAccess: Equatable, Sendable {
    case authorized, denied, notDetermined, unavailable
}

protocol CameraAuthorizing: Sendable {
    @MainActor func status() -> CameraAccess
    func request() async -> Bool
}

struct LiveCameraAuthorization: CameraAuthorizing {
    @MainActor func status() -> CameraAccess {
        guard DataScannerViewController.isSupported else { return .unavailable }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .authorized
        case .notDetermined: return .notDetermined
        case .denied, .restricted: return .denied
        @unknown default: return .denied
        }
    }

    func request() async -> Bool { await AVCaptureDevice.requestAccess(for: .video) }
}
