// QAContextCapture.swift
// ─────────────────────────────────────────────────────────────────────────────
// Shared QACore — snapshot of app state at the moment a ticket is raised.
//
// `QAContextCapture.current()` is nonisolated and safe to call from any
// actor context. It reads only from nonisolated sources:
//   • QA.config          — build info
//   • QARuntimeMonitor   — memory / thermal / disk / hitch (nonisolated)
//   • QARecorder.shared  — breadcrumbs / processes / violations (nonisolated)
//   • QAIdentityStore    — tester identity (nonisolated)
// ─────────────────────────────────────────────────────────────────────────────

import Foundation

nonisolated enum QAContextCapture {

    /// Build a fully-populated QATicketContext from live app state.
    /// All underlying stores expose nonisolated accessors, so this is safe
    /// to call from any Task or background context.
    static func current(
        screen: String? = nil,
        touchTrail: String? = nil
    ) -> QATicketContext {
        let runtime  = QARuntimeMonitor.shared
        let recorder = QARecorder.shared

        var ctx = QATicketContext()

        // Identity (build + device)
        ctx.identity = QAIdentityStore.shared.identity

        // Build info
        ctx.appVersion = QA.config.buildVersion
        ctx.build      = QA.config.buildNumber

        // Screen — caller can pass explicitly; falls back to recorder's current screen
        ctx.screen = screen ?? recorder.currentScreen

        // Breadcrumb trail
        ctx.breadcrumbs = recorder.breadcrumbs

        // Process state
        ctx.runningProcesses = recorder.runningProcesses
        ctx.stalledProcesses = recorder.stalledProcesses

        // Recent failures and open invariant violations
        ctx.recentFailures  = recorder.recentFailures
        ctx.openViolations  = recorder.openViolations

        // Runtime metrics
        ctx.memoryMB       = runtime.memoryMB
        ctx.thermal        = runtime.thermalState
        ctx.lowPower       = runtime.isLowPower
        ctx.online         = QA.config.isOnline()
        ctx.freeDiskMB     = runtime.freeDiskMB
        ctx.worstHitchMs   = runtime.worstHitchMs

        // Device / OS (from identity or fallback)
        if let id = ctx.identity {
            ctx.device = id.modelName
            ctx.os     = id.osVersion
        } else {
            ctx.device = UIDevice.current.model
            ctx.os     = UIDevice.current.systemVersion
        }

        // Session duration from recorder
        ctx.sessionDuration = recorder.sessionDurationString

        // Tap count on the current screen
        ctx.tapsOnScreen = recorder.tapsOnCurrentScreen

        // Touch trail
        ctx.touchTrail = touchTrail ?? recorder.touchTrailSummary

        // Rendering environment snapshot
        ctx.environment = runtime.environmentSnapshot

        return ctx
    }
}
