//
//  NovaWorkerConfiguration.swift
//  Nova
//
//  Shared identity and URL construction for Nova's Cloudflare Worker.
//  Nova ships with the unified production endpoint and still permits an
//  explicit self-hosted override.
//

import Foundation

enum NovaWorkerConfiguration {
    static let serviceName = "nova-ai-worker"
    static let anthropicSecretName = "ANTHROPIC_API_KEY"
    static let sharedTokenSecretName = "NOVA_SHARED_TOKEN"
    static let defaultBaseURL = "https://api.sowensstudios.com/nova"
    static let exampleBaseURL = defaultBaseURL

    /// Appends a canonical Worker route while preserving a base path used by a
    /// custom domain or reverse proxy (for example, `/nova`).
    static func endpoint(base: URL, path: String) -> URL {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty else { return base }
        if base.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == trimmed {
            return base
        }
        return base.appendingPathComponent(trimmed)
    }

    static func healthEndpoint(base: URL) -> URL {
        endpoint(base: base, path: NovaIdentifiers.WorkerPath.health)
    }
}
