//
//  NovaWorkerConfiguration.swift
//  Nova
//
//  Shared identity and URL construction for Nova's self-hosted Cloudflare Worker.
//  The Worker URL remains user-controlled; Nova never silently redirects requests
//  to a developer-owned service.
//

import Foundation

enum NovaWorkerConfiguration {
    static let serviceName = "nova-ai-worker"
    static let anthropicSecretName = "ANTHROPIC_API_KEY"
    static let sharedTokenSecretName = "NOVA_SHARED_TOKEN"
    static let exampleBaseURL = "https://nova-ai-worker.your-subdomain.workers.dev"

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
