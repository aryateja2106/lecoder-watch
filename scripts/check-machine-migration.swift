import Foundation

// Standalone check for the Machine UUID migration (Shared/Models.swift).
// Mirrors the tolerant decoder: old persisted JSON has no `id` key and MUST decode with a
// fresh UUID rather than throwing (a throw would drop the whole saved list on upgrade).
// Run: swift scripts/check-machine-migration.swift

struct Machine: Codable, Identifiable, Hashable {
    var id = UUID()
    var host: String
    var ip: String
    var port: Int
    var token: String
    var bridgeURL: String?
    var vncURL: String?
    var vncCredentialId: UUID?

    init(id: UUID = UUID(), host: String, ip: String, port: Int, token: String,
         bridgeURL: String? = nil, vncURL: String? = nil, vncCredentialId: UUID? = nil) {
        self.id = id; self.host = host; self.ip = ip; self.port = port
        self.token = token; self.bridgeURL = bridgeURL; self.vncURL = vncURL
        self.vncCredentialId = vncCredentialId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        host = try c.decode(String.self, forKey: .host)
        ip = try c.decode(String.self, forKey: .ip)
        port = try c.decode(Int.self, forKey: .port)
        token = try c.decode(String.self, forKey: .token)
        bridgeURL = try c.decodeIfPresent(String.self, forKey: .bridgeURL)
        vncURL = try c.decodeIfPresent(String.self, forKey: .vncURL)
        vncCredentialId = try c.decodeIfPresent(UUID.self, forKey: .vncCredentialId)
    }
}

// 1. Legacy JSON (pre-migration: no `id`) must decode, not throw.
let legacy = #"[{"host":"my-mac","ip":"100.100.100.100","port":8899,"token":""}]"#.data(using: .utf8)!
let decoded = try JSONDecoder().decode([Machine].self, from: legacy)
assert(decoded.count == 1, "legacy decode dropped machines")
assert(decoded[0].host == "my-mac", "legacy host wrong")
assert(decoded[0].port == 8899, "legacy port wrong")

// 2. Each legacy machine gets a distinct stable id (so two unnamed adds never collide).
let twoLegacy = #"[{"host":"a","ip":"","port":1,"token":""},{"host":"b","ip":"","port":1,"token":""}]"#.data(using: .utf8)!
let two = try JSONDecoder().decode([Machine].self, from: twoLegacy)
assert(two[0].id != two[1].id, "ids collided")

// 3. New encode→decode round-trips the id.
let m = Machine(host: "pi", ip: "100.1.1.1", port: 8899, token: "t")
let round = try JSONDecoder().decode(Machine.self, from: JSONEncoder().encode(m))
assert(round.id == m.id, "id did not round-trip")
assert(round.host == "pi" && round.token == "t", "fields did not round-trip")

print("OK check-machine-migration: legacy decode + distinct ids + round-trip all pass")
