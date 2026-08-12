# Unified QA agent instructions

Before planning, editing, building, testing, or reviewing this repository:

1. Run `python3 "../Reports/sync_qa_reports.py"` from this repository root.
2. Read `README-FIRST.md`, `../Reports/AI-INBOX.md`, and `AGENT-HANDOFF.md` completely.
3. Open every unresolved ticket for this app. Blockers and critical tickets precede feature work unless the user says otherwise.
4. Record the active ticket numbers and plan in `AGENT-HANDOFF.md` before editing.

Every newly discovered ticket is active work. Trace or reproduce it, implement the smallest complete fix, add regression coverage, and build for a generic physical device. When a fix ships, update the ticket through the QA system to status `fixed` and provide a concrete `resolution` (“What was fixed”). Do not mark it `verified`: the tester must use Verify Fix on device. If it still fails, Refile preserves the ticket history and captures fresh evidence.

Never edit generated `ticket.json` files to manufacture status. Run report sync again before handoff and repeat if new tickets arrived. These instructions apply to Codex, ChatGPT, Claude, and every other coding agent.
