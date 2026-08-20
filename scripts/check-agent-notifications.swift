import Foundation
import UserNotifications

// These buttons type into a live terminal session on someone's machine. The mapping
// from "which button" to "what gets typed" is the whole safety surface, and it is
// shared between two apps that must agree with meshd's payload.
@main
struct CheckAgentNotifications {
    static func main() {
        // Continue is Enter — accept whatever the agent has highlighted. It must never
        // become a literal "y" or "1", which would be answering an unseen question.
        let cont = AgentNotification.command(for: "AGENT_CONTINUE", typed: nil)
        assert(cont?.key == "enter" && cont?.text == nil, "Continue must send Enter and nothing else")

        let stop = AgentNotification.command(for: "AGENT_STOP", typed: nil)
        assert(stop?.key == "ctrl-c" && stop?.text == nil)

        // Reply sends exactly what was dictated.
        let reply = AgentNotification.command(for: "AGENT_REPLY", typed: "use the other branch")
        assert(reply?.text == "use the other branch" && reply?.key == nil)

        // An empty or whitespace reply is a dismissal, not an empty line typed into a
        // session. Same for the default tap and the dismiss action.
        assert(AgentNotification.command(for: "AGENT_REPLY", typed: "") == nil)
        assert(AgentNotification.command(for: "AGENT_REPLY", typed: "   \n") == nil)
        assert(AgentNotification.command(for: "AGENT_REPLY", typed: nil) == nil)
        assert(AgentNotification.command(for: UNNotificationDefaultActionIdentifier, typed: nil) == nil)
        assert(AgentNotification.command(for: UNNotificationDismissActionIdentifier, typed: nil) == nil)
        assert(AgentNotification.command(for: "SOMETHING_ELSE", typed: "hi") == nil)

        // Routing needs both halves: a session name is not unique across machines, so
        // a payload missing the host must not fall back to "some machine with that
        // session" — that is how Enter lands on the wrong box.
        assert(AgentNotification.target(from: ["host": "studio", "session": "api"]) != nil)
        assert(AgentNotification.target(from: ["session": "api"]) == nil)
        assert(AgentNotification.target(from: ["host": "studio"]) == nil)
        assert(AgentNotification.target(from: ["host": "", "session": "api"]) == nil)
        assert(AgentNotification.target(from: ["host": "studio", "session": ""]) == nil)
        assert(AgentNotification.target(from: [:]) == nil)

        // The category has to carry all three buttons, and Reply has to be the text one
        // or dictation never appears on the wrist.
        guard let category = AgentNotification.categories.first(where: { $0.identifier == AgentNotification.attentionCategory }) else {
            fatalError("the attention category is missing")
        }
        let ids = Set(category.actions.map(\.identifier))
        assert(ids == Set(AgentNotification.Action.allCases.map(\.rawValue)), "every action must be on the category")
        assert(category.actions.contains { $0 is UNTextInputNotificationAction && $0.identifier == "AGENT_REPLY" },
               "Reply must be a text-input action")

        print("check-agent-notifications: OK")
    }
}
