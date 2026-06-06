import Foundation
import UIKit
import Photos

public final class PhotoLibraryCapability: Capability, @unchecked Sendable {
    public let name = "photoLibrary"

    public init() {}

    public func permissionStatus() async -> PermissionStatus {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .authorized, .limited: return .granted
        case .denied, .restricted:  return .denied
        case .notDetermined:        return .notDetermined
        @unknown default:           return .notDetermined
        }
    }

    public func requestPermission() async -> PermissionStatus {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        return (status == .authorized || status == .limited) ? .granted : .denied
    }

    public func invoke(method: String, params: CapabilityParams) async throws -> CapabilityResult {
        switch method {
        case "saveImage":
            guard let dataUrl = params["dataUrl"]?.stringValue else {
                throw CapabilityError.missingParam("dataUrl")
            }
            let imageData = try decodeBase64DataURL(dataUrl)
            return try await saveImageData(imageData)

        case "saveImageFromUrl":
            guard let urlString = params["url"]?.stringValue,
                  let url = URL(string: urlString) else {
                throw CapabilityError.missingParam("url")
            }
            let imageData = try await downloadImage(from: url)
            return try await saveImageData(imageData)

        default:
            throw CapabilityError.unknownMethod(method)
        }
    }

    private func saveImageData(_ data: Data) async throws -> CapabilityResult {
        guard let image = UIImage(data: data) else {
            throw CapabilityError.underlying("Could not decode image from data")
        }

        if await permissionStatus() != .granted {
            _ = await requestPermission()
        }

        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        }
        return .null
    }

    private func decodeBase64DataURL(_ dataUrl: String) throws -> Data {
        guard let comma = dataUrl.firstIndex(of: ",") else {
            throw CapabilityError.underlying("Invalid data URL format (missing comma)")
        }
        let base64 = String(dataUrl[dataUrl.index(after: comma)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = Data(base64Encoded: base64) else {
            throw CapabilityError.underlying("Invalid base64 in data URL")
        }
        return data
    }

    private func downloadImage(from url: URL) async throws -> Data {
        let (data, _) = try await URLSession.shared.data(from: url)
        return data
    }
}
