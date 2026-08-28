import SwiftUI

struct QAAIOverrideView: View {
    let app: String; var hasActiveAI = true
    @State private var provider = "default"; @State private var model = ""; @State private var status = ""; @State private var busy = false
    private let models = ["anthropic": ["claude-haiku-4-5-20251001", "claude-sonnet-4-6", "claude-opus-4-8"], "openai": ["gpt-5.6-luna", "gpt-5.6-terra", "gpt-5.6-sol"]]
    var body: some View { VStack(alignment: .leading, spacing: 8) {
        Label("AI model override", systemImage: "brain.head.profile").font(.headline)
        Picker("Agent", selection: $provider) { Text("App Default (lowest credit)").tag("default"); Text("Claude").tag("anthropic"); Text("ChatGPT").tag("openai") }.onChange(of: provider) { _, value in model = models[value]?.first ?? "" }
        if provider != "default" { Picker("Model", selection: $model) { ForEach(models[provider] ?? [], id: \.self) { Text($0).tag($0) } } }
        Button(busy ? "Applying…" : "Apply QA override") { Task { await save() } }.disabled(busy)
        Text(status.isEmpty ? "QA only; keys stay in the Worker." : status).font(.caption).foregroundStyle(.secondary)
    }.task { await load() } }
    private func request(_ method: String, _ body: Data? = nil) async throws -> Data { var c = URLComponents(string: "https://api.sowensstudios.com/_unified/qa/ai-config")!; if method == "GET" { c.queryItems = [.init(name: "app", value: app)] }; var r = URLRequest(url: c.url!); r.httpMethod = method; r.setValue("Joo", forHTTPHeaderField: "X-QA-Passcode"); if let body { r.httpBody = body; r.setValue("application/json", forHTTPHeaderField: "Content-Type") }; let (d, p) = try await URLSession.shared.data(for: r); guard (p as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }; return d }
    @MainActor private func load() async { do { let d = try await request("GET"); if let x = try JSONSerialization.jsonObject(with: d) as? [String: Any], let o = x["override"] as? [String: String] { provider = o["provider"] ?? "default"; model = o["model"] ?? "" } } catch { status = "Could not load current override." } }
    @MainActor private func save() async { busy = true; defer { busy = false }; do { let d = try JSONSerialization.data(withJSONObject: ["app": app, "provider": provider, "model": provider == "default" ? "" : model]); _ = try await request("POST", d); status = provider == "default" ? "Restored the lowest-credit default." : "QA now uses \(model)." } catch { status = "Override failed: \(error.localizedDescription)" } }
}
