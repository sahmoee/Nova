//
//  AISearchSettingsView.swift
//  FrameTV
//
//  Lets the user point FrameTV at their own Cloudflare Worker for Claude-powered
//  search. FrameTV never stores an API key — the Worker the user deploys holds the
//  key server-side. This screen only stores the Worker's URL.
//

import SwiftUI

struct AISearchSettingsView: View {
    @State private var workerURL = AISearchService.workerURLString
    @State private var showWorkerCode = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                Text("AI Search")
                    .font(Theme.Font.screenTitle())
                    .screenTitleStyle()
                    .foregroundStyle(Theme.Colors.textPrimary)

                Text("Search for movies and shows using natural language, powered by Claude. For your security, FrameTV doesn't hold any AI keys. Instead, it calls a small Cloudflare Worker that you deploy and that keeps your key private on the server.")
                    .font(.appFont(19))
                    .foregroundStyle(Theme.Colors.textSecondary)

                Text("Worker URL")
                    .font(.appFont(17, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                TextField("https://your-worker.workers.dev", text: $workerURL)
                    .textFieldStyle(.plain)
                    #if os(iOS)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    #endif
                    .padding(Theme.Spacing.md)
                    .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .onChange(of: workerURL) { _, newValue in
                        AISearchService.workerURLString = newValue
                    }

                Label(AISearchService.isConfigured ? "AI search is ready" : "Not configured yet",
                      systemImage: AISearchService.isConfigured ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .font(.appFont(17))
                    .foregroundStyle(AISearchService.isConfigured ? Theme.Colors.success : Theme.Colors.textTertiary)

                Button {
                    showWorkerCode.toggle()
                } label: {
                    Label(showWorkerCode ? "Hide Worker setup" : "How to deploy the Worker",
                          systemImage: "chevron.right.circle")
                        .font(.appFont(18, weight: .semibold))
                        .foregroundStyle(Theme.Colors.accent)
                }
                .frameRowStyle()

                if showWorkerCode { workerInstructions }
            }
            .padding(.horizontal, Theme.Spacing.edge)
            .padding(.bottom, Theme.Spacing.xl)
            .frame(maxWidth: Theme.contentMaxWidth(1000), alignment: .leading)
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .dismissKeyboardOnTap()
    }

    private var workerInstructions: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            instruction(1, "Create a free Cloudflare account and a new Worker.")
            instruction(2, "Add a secret named ANTHROPIC_API_KEY with your Anthropic API key (Workers ▸ Settings ▸ Variables).")
            instruction(3, "Paste the Worker code below, deploy, and copy its URL into the field above.")

            Text("Worker code")
                .font(.appFont(16, weight: .semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
            ScrollView(.horizontal, showsIndicators: true) {
                Text(workerSource)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(Theme.Spacing.md)
            }
            .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))

            Text("Your key lives only in your Worker's secrets and is never sent to or stored by FrameTV.")
                .font(.appFont(14))
                .foregroundStyle(Theme.Colors.textTertiary)
        }
    }

    private func instruction(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Text("\(n)")
                .font(.appFont(15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Theme.Colors.accent, in: Circle())
            Text(text)
                .font(.appFont(17))
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    // The Worker source the user deploys. Kept as a plain string for copy/paste.
    private var workerSource: String {
        """
        export default {
          async fetch(request, env) {
            if (request.method !== "POST") {
              return new Response("POST only", { status: 405 });
            }
            const { query } = await request.json();
            const r = await fetch("https://api.anthropic.com/v1/messages", {
              method: "POST",
              headers: {
                "content-type": "application/json",
                "x-api-key": env.ANTHROPIC_API_KEY,
                "anthropic-version": "2023-06-01"
              },
              body: JSON.stringify({
                model: "claude-sonnet-4-6",
                max_tokens: 512,
                messages: [{
                  role: "user",
                  content: "Suggest up to 12 movies or TV shows for this request. " +
                    "Reply ONLY with a JSON array of title strings, no other text. " +
                    "Request: " + query
                }]
              })
            });
            const data = await r.json();
            let text = (data.content && data.content[0] && data.content[0].text) || "[]";
            let titles = [];
            try { titles = JSON.parse(text); } catch (e) { titles = []; }
            return new Response(JSON.stringify({ titles }), {
              headers: { "content-type": "application/json" }
            });
          }
        };
        """
    }
}
