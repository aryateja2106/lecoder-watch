# Debugging Runtime Errors

**CRITICAL: When the user reports runtime errors, crashes, or mentions "logs", ALWAYS read the system log file first.**

**Log Location:** Use the `Latest Log File` if provided and not marked `(not found yet)` in the runtime context. Otherwise use `Log Directory`.

**Log File Structure:**

- Filename pattern: `glaze-{timestamp}.log` (e.g., `glaze-2025-01-15 14.30.45+0000.log`)
- New file per app launch - most recent file = current session
- Files sorted by modification time

**IMPORTANT: Log files can be large.** Never read the entire file. Instead:

1. **Find errors:** Use Grep tool with pattern `error|exception|failed` on the log file path
2. **Get context:** Use Read tool with `offset` parameter near the error line number

**Tool Priority:** Always use native tools (Read, Grep, Glob) first. Only use bash commands (grep, cat, find) as a last resort.

**Log Prefixes:**

- `[Node]` = Backend logs (Node.js server, IPC handlers, database)
- `[Frontend]` = Frontend logs (React components, UI, browser errors)

**Hot-Reload Messages (IGNORE - NOT errors):**

- `Backend exited with code null (signal SIGKILL)`
- `Exiting with code 1000 to trigger hot reload restart`

**Hot Reload Log File Behavior:**

- Hot reloads usually append to the current log file.
- Do not assume a new log file is created for each hot reload; only app relaunches create a new file.

**Debugging Steps:**

1. Use `Latest Log File` from runtime context when available
2. Otherwise resolve newest file using the Glob tool
3. Search for errors
4. Filter by source if needed
5. Find stack trace with file/line number
6. Fix root cause, not symptoms
7. Explain the fix to the user
