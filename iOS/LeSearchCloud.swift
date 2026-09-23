// LeSearchCloud.swift — send feedback and manage the optional LeSearch AI account with Supabase over URLSession.
import Foundation
import UIKit

struct CloudSession: Codable {
    let accessToken: String
    let refreshToken: String
    let userID: String
    let email: String
}

struct FeedbackReport {
    let kind: String
    let title: String
    let body: String
    let contactEmail: String?
    let bundle: String?
    let attachment: (data: Data, ext: String, mime: String)?
}

struct CloudError: Error, LocalizedError {
    let reason: String
    var errorDescription: String? { reason }
}

enum LeSearchCloud {
    static let SUPABASE_URL = "https://zmisjteztezaqfflwbgf.supabase.co"
    static let SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InptaXNqdGV6dGV6YXFmZmx3YmdmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODM3NDQ2MzMsImV4cCI6MjA5OTMyMDYzM30.9I0_eaLYkvISZX6pkrWDeZywBHortnzQoz35omgk_6I"

    private static let sessionKey = "cloud.session"
    private static let urlSession = URLSession.shared

    static func currentSession() -> CloudSession? {
        guard let data = SecureStore.load(sessionKey) else { return nil }
        return try? JSONDecoder().decode(CloudSession.self, from: data)
    }

    @discardableResult
    static func signUp(email: String, password: String) async throws -> CloudSession {
        try await authenticate(path: "/auth/v1/signup", email: email, password: password)
    }

    @discardableResult
    static func signIn(email: String, password: String) async throws -> CloudSession {
        try await authenticate(path: "/auth/v1/token?grant_type=password", email: email, password: password)
    }

    static func signOut() async {
        if let session = currentSession(),
           var request = try? request(path: "/auth/v1/logout", method: "POST") {
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
            _ = try? await urlSession.data(for: request)
        }
        SecureStore.delete(sessionKey)
    }

    /// The live session, refreshed when its access token is about to expire. A refresh
    /// the server refuses (revoked, expired) signs the phone out rather than failing the
    /// call that asked: a report can always go out anonymously.
    @discardableResult
    static func refreshIfNeeded() async throws -> CloudSession? {
        guard let session = currentSession() else { return nil }
        guard accessTokenExpiresSoon(session.accessToken) else { return session }
        do { return try await refresh(session) }
        catch {
            SecureStore.delete(sessionKey)
            NotificationCenter.default.post(name: .cloudSessionChanged, object: nil)
            return nil
        }
    }

    static func sendFeedback(_ report: FeedbackReport) async throws -> UUID {
        let title = report.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...200).contains(title.count) else {
            throw CloudError(reason: "Add a title of 200 characters or fewer.")
        }
        guard report.body.count <= 20_000 else {
            throw CloudError(reason: "The report note must be 20,000 characters or fewer.")
        }
        guard ["bug", "idea", "other"].contains(report.kind) else {
            throw CloudError(reason: "Choose a valid report kind.")
        }

        let id = UUID()
        let idString = id.uuidString.lowercased()
        var attachmentName: String?
        if let attachment = report.attachment {
            guard attachment.data.count <= 50 * 1_024 * 1_024 else {
                throw CloudError(reason: "Attachments must be 50 MB or smaller.")
            }
            let allowed = ["png": "image/png", "jpg": "image/jpeg", "mov": "video/quicktime", "mp4": "video/mp4"]
            guard allowed[attachment.ext] == attachment.mime else {
                throw CloudError(reason: "That attachment type is not supported.")
            }
            attachmentName = "\(idString).\(attachment.ext)"
            try await upload(attachment.data, named: attachmentName!, mime: attachment.mime)
        }

        let session = try await refreshIfNeeded()
        let systemVersion = await MainActor.run { UIDevice.current.systemVersion }
        var body: [String: Any] = [
            "id": idString,
            "kind": report.kind,
            "title": title,
            "body": report.body,
            "app_version": BuildInfo.version,
            "app_build": BuildInfo.build,
            "device": deviceIdentifier,
            "os": "iOS \(systemVersion)",
            "source": "app",
        ]
        if let email = report.contactEmail?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty { body["contact_email"] = email }
        if let userID = session?.userID { body["user_id"] = userID }
        if let attachmentName { body["attachment"] = attachmentName }
        if let bundle = report.bundle { body["bundle"] = bundle }

        var request = try request(path: "/rest/v1/feedback", method: "POST", json: body)
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        let (data, response) = try await authorized(request)
        guard response.statusCode == 201 else { throw serverError(data: data, status: response.statusCode) }
        return id
    }

    private static func authenticate(path: String, email: String, password: String) async throws -> CloudSession {
        let body = ["email": email.trimmingCharacters(in: .whitespacesAndNewlines), "password": password]
        let request = try request(path: path, method: "POST", json: body)
        let (data, response) = try await data(for: request)
        guard response.statusCode == 200 else { throw serverError(data: data, status: response.statusCode) }
        return try saveAuth(data)
    }

    private static func refresh(_ session: CloudSession) async throws -> CloudSession {
        let request = try request(path: "/auth/v1/token?grant_type=refresh_token", method: "POST", json: ["refresh_token": session.refreshToken])
        let (data, response) = try await data(for: request)
        guard response.statusCode == 200 else { throw serverError(data: data, status: response.statusCode) }
        return try saveAuth(data)
    }

    private static func saveAuth(_ data: Data) throws -> CloudSession {
        struct AuthResponse: Decodable {
            struct User: Decodable { let id: String; let email: String? }
            let accessToken: String
            let refreshToken: String
            let user: User
            enum CodingKeys: String, CodingKey {
                case accessToken = "access_token", refreshToken = "refresh_token", user
            }
        }
        do {
            let auth = try JSONDecoder().decode(AuthResponse.self, from: data)
            let session = CloudSession(accessToken: auth.accessToken, refreshToken: auth.refreshToken,
                                       userID: auth.user.id, email: auth.user.email ?? "")
            guard let encoded = try? JSONEncoder().encode(session), SecureStore.save(encoded, for: sessionKey) else {
                throw CloudError(reason: "The account signed in, but its session could not be saved securely.")
            }
            return session
        } catch let error as CloudError { throw error }
        catch { throw CloudError(reason: "LeSearch AI returned an unreadable account response.") }
    }

    private static func upload(_ data: Data, named name: String, mime: String) async throws {
        var request = try request(path: "/storage/v1/object/feedback-attachments/\(name)", method: "POST")
        request.setValue(mime, forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        let (responseData, response) = try await authorized(request)
        guard response.statusCode == 200 else { throw serverError(data: responseData, status: response.statusCode) }
    }

    private static func authorized(_ original: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var request = original
        let token = try await refreshIfNeeded()?.accessToken ?? SUPABASE_ANON_KEY
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        var (data, response) = try await data(for: request)
        if response.statusCode == 401, let session = currentSession() {
            let fresh = try await refresh(session)
            request.setValue("Bearer \(fresh.accessToken)", forHTTPHeaderField: "Authorization")
            (data, response) = try await self.data(for: request)
        }
        return (data, response)
    }

    private static func serverError(data: Data, status: Int) -> CloudError {
        let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let message = payload?["message"] as? String ?? payload?["msg"] as? String ?? payload?["error_description"] as? String
        return CloudError(reason: message ?? "LeSearch AI returned an error (\(status)).")
    }

    private static func request(path: String, method: String, json: Any? = nil) throws -> URLRequest {
        guard let url = URL(string: SUPABASE_URL + path) else { throw CloudError(reason: "The LeSearch AI service address is invalid.") }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(SUPABASE_ANON_KEY, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let json {
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
        }
        return request
    }

    private static func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw CloudError(reason: "LeSearch AI returned an invalid response.") }
            return (data, response)
        } catch let error as CloudError { throw error }
        catch { throw CloudError(reason: "Couldn't reach LeSearch AI. \(error.localizedDescription)") }
    }

    private static func accessTokenExpiresSoon(_ token: String) -> Bool {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return true }
        var value = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        value += String(repeating: "=", count: (4 - value.count % 4) % 4)
        guard let data = Data(base64Encoded: value),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = payload["exp"] as? Double else { return true }
        return exp <= Date().timeIntervalSince1970 + 60
    }

    private static var deviceIdentifier: String {
        var system = utsname()
        uname(&system)
        return withUnsafeBytes(of: &system.machine) { bytes in
            String(bytes: bytes.prefix { $0 != 0 }, encoding: .utf8) ?? "unknown"
        }
    }
}
