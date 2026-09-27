// scripts/check-launchable.swift — verify DoctorReport.launchable logic.

import Foundation

@main
struct CheckLaunchable {
    static func main() {
        let decode: (String) -> DoctorReport = { json in
            let data = json.data(using: .utf8)!
            return try! JSONDecoder().decode(DoctorReport.self, from: data)
        }

        // Test 1: agents [claude, agy] -> ["claude", "agy", "shell"]
        let json1 = """
        {
            "ok": true, "host": "h", "platform": "p", "version": "v", "bind": "b",
            "checks": {},
            "agents": [
                {"name": "claude", "path": "/bin/claude"},
                {"name": "agy", "path": "/bin/agy"}
            ]
        }
        """
        assert(decode(json1).launchable == ["claude", "agy", "shell"], "Failed json1")

        // Test 2: agents [] -> ["shell"]
        let json2 = """
        {
            "ok": true, "host": "h", "platform": "p", "version": "v", "bind": "b",
            "checks": {},
            "agents": []
        }
        """
        assert(decode(json2).launchable == ["shell"], "Failed json2")

        // Test 3: no agents key -> legacy fallback ["shell", "claude", "codex", "pi", "agy"]
        let json3 = """
        {
            "ok": true, "host": "h", "platform": "p", "version": "v", "bind": "b",
            "checks": {}
        }
        """
        assert(decode(json3).launchable == ["shell", "claude", "codex", "pi", "agy"], "Failed json3")

        // Test 4: duplicates collapse
        let json4 = """
        {
            "ok": true, "host": "h", "platform": "p", "version": "v", "bind": "b",
            "checks": {},
            "agents": [
                {"name": "claude", "path": "/bin/claude"},
                {"name": "claude", "path": "/bin/claude2"}
            ]
        }
        """
        assert(decode(json4).launchable == ["claude", "shell"], "Failed json4")

        print("check-launchable: OK")
    }
}
