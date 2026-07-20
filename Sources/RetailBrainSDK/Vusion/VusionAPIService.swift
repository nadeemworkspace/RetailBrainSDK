
import Foundation

// MARK: - SDK Configuration

/// Static configuration for Vusion SDK integration
/// In the future, these values will be passed from the application layer.
/// For now, they are defined as static values within the SDK.
struct SDKConfiguration {
   
    static let baseUrl = URL(string: "https://api-eu.vusion.io")!
    static let storeId = "accenture_lab.bangalore"
    static let apiKey = "4828c140cb1148af826fae64ff07e91d"
    static let region = "eu"
    
    // MARK: - Update Configuration
    /// For future use: update these values when the app provides configuration
    static func updateConfiguration(baseUrl: URL? = nil, storeId: String? = nil, apiKey: String? = nil, region: String? = nil) {
        // Implementation can be added when app-side configuration is available
        if let baseUrl = baseUrl {
            print("[SDKConfiguration] Updated baseUrl to \(baseUrl)")
        }
        if let storeId = storeId {
            print("[SDKConfiguration] Updated storeId to \(storeId)")
        }
        if let apiKey = apiKey {
            print("[SDKConfiguration] Updated apiKey")
        }
        if let region = region {
            print("[SDKConfiguration] Updated region to \(region)")
        }
    }
}

// MARK: - Environment Structure (for API Service compatibility)

struct AppEnv {
    let baseUrl: URL
    let storeId: String
    let apiKey: String
    let region: String

    static let current: AppEnv? = AppEnv.loadStaticConfiguration()

    private static func loadStaticConfiguration() -> AppEnv? {
        return AppEnv(
            baseUrl: SDKConfiguration.baseUrl,
            storeId: SDKConfiguration.storeId,
            apiKey: SDKConfiguration.apiKey,
            region: SDKConfiguration.region
        )
    }
}

final class APIService {
    static let shared = APIService()
    private static let iso8601WithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let iso8601NoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
    
    private init() {
    }
    
    func fetchAnchors() async throws -> AnchorsResponse {
        let context = try loadEnvironment()
        let url = context.env.baseUrl.appendingPathComponent("vusion-geolocation/v1/stores/\(context.storeId)/beacon/anchors")
        let data = try await sendRequest(
            url: url,
            method: "POST",
            apiKey: context.env.apiKey,
            accept: "application/json",
            body: nil,
            contentType: nil
        )
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = APIService.iso8601WithFractional.date(from: value) {
                return date
            }
            if let date = APIService.iso8601NoFractional.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(value)")
        }
        return try decoder.decode(AnchorsResponse.self, from: data)
    }
    private func sendRequest(
        url: URL,
        method: String,
        apiKey: String,
        accept: String,
        body: Data?,
        contentType: String?
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(apiKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        request.setValue("testSDK", forHTTPHeaderField: "swVlinkVersion")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIServiceError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            if body.isEmpty {
                throw APIServiceError.requestFailed("HTTP \(http.statusCode).")
            }
            throw APIServiceError.requestFailed("HTTP \(http.statusCode). Response: \(body)")
        }
        return data
    }
    private func loadEnvironment() throws -> EnvContext {
        guard let env = AppEnv.current else {
            throw APIServiceError.missingEnvironment
        }
        let storeId = env.storeId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !storeId.isEmpty else {
            throw APIServiceError.invalidStoreId
        }
        return EnvContext(env: env, storeId: storeId)
    }
}

