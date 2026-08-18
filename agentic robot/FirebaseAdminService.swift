import Foundation
import FirebaseAuth

enum FirebaseAdminServiceError: LocalizedError {
    case notSignedIn
    case missingToken
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Your admin session has expired. Please sign in again."
        case .missingToken:
            return "Could not verify your admin session. Please try again."
        case .invalidResponse:
            return "Firebase returned an unexpected response. Please try again."
        case .server(let message):
            return message
        }
    }
}

struct FirebaseAdminService {
    private static let deleteUserEndpoint = URL(
        string: "https://us-central1-agentic-robot-c574c.cloudfunctions.net/deleteUser"
    )!

    static func deleteUser(
        uid: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let currentUser = Auth.auth().currentUser else {
            completion(.failure(FirebaseAdminServiceError.notSignedIn))
            return
        }

        currentUser.getIDTokenForcingRefresh(true) { token, tokenError in
            if let tokenError {
                completion(.failure(tokenError))
                return
            }

            guard let token, !token.isEmpty else {
                completion(.failure(FirebaseAdminServiceError.missingToken))
                return
            }

            var request = URLRequest(url: deleteUserEndpoint)
            request.httpMethod = "POST"
            request.timeoutInterval = 30
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: ["uid": uid])
            } catch {
                completion(.failure(error))
                return
            }

            URLSession.shared.dataTask(with: request) { data, response, requestError in
                if let requestError {
                    completion(.failure(requestError))
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse else {
                    completion(.failure(FirebaseAdminServiceError.invalidResponse))
                    return
                }

                guard (200...299).contains(httpResponse.statusCode) else {
                    let message = serverMessage(from: data)
                        ?? "Could not delete this account. Please try again."
                    completion(.failure(FirebaseAdminServiceError.server(message)))
                    return
                }

                completion(.success(()))
            }.resume()
        }
    }

    private static func serverMessage(from data: Data?) -> String? {
        guard let data,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object["error"] as? String
    }
}
