//
//  SMBCheckerView.swift
//  FrameTV
//
//  A guided SMB diagnostic. Runs a sequence of checks against a saved share and
//  shows exactly which step fails, so the common "STATUS_LOGON_FAILURE" (a Mac-side
//  config issue, not an app bug) is understandable and actionable rather than just
//  a dead end. Steps: host reachable, connect, credentials accepted, share found,
//  folder readable, streaming ready.
//

import SwiftUI

struct SMBCheckerView: View {
    let share: SMBShare
    @EnvironmentObject private var env: AppEnvironment

    @State private var steps: [CheckStep] = CheckStep.initial
    @State private var running = false
    @State private var advice: String?

    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    header

                    VStack(spacing: Theme.Spacing.sm) {
                        ForEach(steps) { step in
                            stepRow(step)
                        }
                    }

                    if let advice {
                        adviceBox(advice)
                    }

                    Button {
                        Task { await runChecks() }
                    } label: {
                        HStack {
                            Image(systemName: running ? "hourglass" : "stethoscope")
                            Text(running ? "Checking…" : "Run Diagnostic")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.Colors.accent)
                    .disabled(running)
                }
                .padding(Theme.Spacing.edge)
                .frame(maxWidth: Theme.contentMaxWidth(800), alignment: .leading)
            }
        }
        .navigationTitle("SMB Diagnostic")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(share.displayName)
                .font(Theme.Font.screenTitle())
                .screenTitleStyle()
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("\(share.host) · \(share.shareName)")
                .font(.appFont(18))
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    private func stepRow(_ step: CheckStep) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: step.state.systemImage)
                .foregroundStyle(step.state.color)
                .font(.appFont(24))
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(step.title)
                    .font(.appFont(19, weight: .medium))
                    .foregroundStyle(Theme.Colors.textPrimary)
                if let note = step.note {
                    Text(note)
                        .font(.appFont(15))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            }
            Spacer()
            if step.state == .running {
                ProgressView().tint(Theme.Colors.accent)
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private func adviceBox(_ text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Image(systemName: "lightbulb.fill")
                .foregroundStyle(.yellow)
            Text(text)
                .font(.appFont(16))
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(Theme.Spacing.md)
        .background(Color.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    // MARK: - Running the checks

    @MainActor
    private func runChecks() async {
        running = true
        advice = nil
        steps = CheckStep.initial

        // Step 1: host present and not loopback.
        setState(.host, .running)
        let host = share.host.trimmingCharacters(in: .whitespaces)
        if host.isEmpty {
            fail(.host, "No host set.", "Add the computer's network name (e.g. mycomputer.local) or its LAN IP.")
            running = false; return
        }
        if host == "127.0.0.1" || host.lowercased() == "localhost" {
            fail(.host, "Host points to this device.", "Use the computer's network name or LAN IP, not localhost.")
            running = false; return
        }
        setState(.host, .passed, note: host)

        // Steps 2-5: drive the real SMB provider and map failures to steps.
        // listShares exercises reachability, connect, and credentials in one call;
        // listDirectory exercises share-found and folder-readable.
        setState(.connect, .running)
        do {
            let shares = try await env.smb.listShares(
                host: share.host,
                username: share.username,
                keychainAccount: share.keychainAccount
            )
            setState(.connect, .passed)
            setState(.credentials, .passed, note: "Signed in as \(share.username)")

            // Share found?
            setState(.shareFound, .running)
            if shares.contains(where: { $0.caseInsensitiveCompare(share.shareName) == .orderedSame }) || shares.isEmpty {
                setState(.shareFound, .passed, note: share.shareName)
            } else {
                let list = shares.prefix(5).joined(separator: ", ")
                fail(.shareFound, "Share not in the list.", "Available shares: \(list). Check the exact share name (case-sensitive on some servers).")
                running = false; return
            }

            // Folder readable?
            setState(.folder, .running)
            let path = share.path ?? ""
            _ = try await env.smb.listDirectory(path)
            setState(.folder, .passed, note: path.isEmpty ? "Share root" : path)

            // Streaming ready (provider is up; we reached a readable directory).
            setState(.streaming, .passed)
        } catch let error as SMBError {
            mapError(error)
            running = false
            return
        } catch {
            fail(currentRunningStep ?? .connect, error.localizedDescription, nil)
            running = false
            return
        }

        running = false
    }

    /// Maps an SMBError to the appropriate failing step plus targeted advice.
    @MainActor
    private func mapError(_ error: SMBError) {
        switch error {
        case .hostUnreachable, .loopbackHost:
            fail(.connect, error.errorDescription, "Make sure the computer is on, awake, and on the same network, and that file sharing is enabled.")
        case .authenticationFailed:
            fail(.credentials, "Sign-in rejected (often STATUS_LOGON_FAILURE).",
                 "On a Mac: System Settings ▸ General ▸ Sharing ▸ File Sharing must be ON, your account listed under Users, and SMB enabled for it (click the (i), check the box, re-enter the password). Use your short user name and that account's login password.")
        case .passwordMissing:
            fail(.credentials, "Saved password couldn't be read.", "Remove and re-add the share so the password is stored again.")
        case .pathNotFound:
            fail(.folder, "Folder not found.", "Check the path within the share, or leave it blank to use the share root.")
        case .streamingUnavailable:
            fail(.streaming, "Streaming unavailable for that file.", nil)
        case .notConnected:
            fail(.connect, "Couldn't connect.", nil)
        case .underlying(let e):
            fail(currentRunningStep ?? .connect, e.localizedDescription, nil)
        }
    }

    // MARK: - Step state helpers

    private var currentRunningStep: CheckStep.Kind? {
        steps.first(where: { $0.state == .running })?.kind
    }

    @MainActor
    private func setState(_ kind: CheckStep.Kind, _ state: CheckStep.State, note: String? = nil) {
        guard let i = steps.firstIndex(where: { $0.kind == kind }) else { return }
        steps[i].state = state
        if let note { steps[i].note = note }
    }

    @MainActor
    private func fail(_ kind: CheckStep.Kind, _ note: String?, _ adviceText: String?) {
        setState(kind, .failed, note: note)
        // Mark any not-yet-run steps as skipped.
        for i in steps.indices where steps[i].state == .pending || steps[i].state == .running {
            if steps[i].kind != kind { steps[i].state = .skipped }
        }
        advice = adviceText
    }
}

// MARK: - Model

struct CheckStep: Identifiable {
    enum Kind: CaseIterable { case host, connect, credentials, shareFound, folder, streaming }
    enum State {
        case pending, running, passed, failed, skipped

        var systemImage: String {
            switch self {
            case .pending:  return "circle"
            case .running:  return "circle.dotted"
            case .passed:   return "checkmark.circle.fill"
            case .failed:   return "xmark.circle.fill"
            case .skipped:  return "minus.circle"
            }
        }
        var color: Color {
            switch self {
            case .pending:  return Theme.Colors.textTertiary
            case .running:  return Theme.Colors.accent
            case .passed:   return Theme.Colors.success
            case .failed:   return Theme.Colors.error
            case .skipped:  return Theme.Colors.textTertiary
            }
        }
    }

    let id = UUID()
    let kind: Kind
    let title: String
    var state: State = .pending
    var note: String? = nil

    static var initial: [CheckStep] {
        [
            CheckStep(kind: .host,        title: "Host address valid"),
            CheckStep(kind: .connect,     title: "Can connect to server"),
            CheckStep(kind: .credentials, title: "Credentials accepted"),
            CheckStep(kind: .shareFound,  title: "Share found"),
            CheckStep(kind: .folder,      title: "Folder readable"),
            CheckStep(kind: .streaming,   title: "Streaming server ready")
        ]
    }
}
