import XCTest
@testable import Flunner

final class AgentMCPConfigWriterTests: XCTestCase {
    private var tempHome: URL!

    override func setUpWithError() throws {
        tempHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("flunner-agent-mcp-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempHome, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tempHome.appendingPathComponent(".cursor"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tempHome.appendingPathComponent(".codex"), withIntermediateDirectories: true)
        try "{}".write(to: tempHome.appendingPathComponent(".claude.json"), atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempHome)
    }

    func testJSONMergePreservesExistingServers() throws {
        let configURL = tempHome.appendingPathComponent(".cursor/mcp.json")
        let existing = """
        {
          "mcpServers": {
            "other": { "url": "https://example.com/mcp" }
          }
        }
        """
        try existing.write(to: configURL, atomically: true, encoding: .utf8)

        let writer = AgentMCPConfigWriter(homeDirectory: tempHome)
        let result = writer.sync(
            target: .cursor,
            url: "http://127.0.0.1:47321/mcp",
            token: "abc123"
        )
        XCTAssertTrue(result.success, result.message)

        let data = try Data(contentsOf: configURL)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let servers = try XCTUnwrap(json["mcpServers"] as? [String: Any])
        XCTAssertNotNil(servers["other"])
        let flunner = try XCTUnwrap(servers["flunner"] as? [String: Any])
        XCTAssertEqual(flunner["url"] as? String, "http://127.0.0.1:47321/mcp")
        let headers = try XCTUnwrap(flunner["headers"] as? [String: Any])
        XCTAssertEqual(headers["Authorization"] as? String, "Bearer abc123")
    }

    func testCodexMergeReplacesFlunnerSection() throws {
        let configURL = tempHome.appendingPathComponent(".codex/config.toml")
        let existing = """
        [features]
        apps = false

        [mcp_servers.flunner]
        url = "http://127.0.0.1:1111/mcp"
        http_headers = { Authorization = "Bearer old" }
        enabled = true

        [mcp_servers.other]
        command = "echo"
        """
        try existing.write(to: configURL, atomically: true, encoding: .utf8)

        let writer = AgentMCPConfigWriter(homeDirectory: tempHome)
        let result = writer.sync(
            target: .codex,
            url: "http://127.0.0.1:47321/mcp",
            token: "new-token"
        )
        XCTAssertTrue(result.success, result.message)

        let contents = try String(contentsOf: configURL, encoding: .utf8)
        XCTAssertTrue(contents.contains("http://127.0.0.1:47321/mcp"))
        XCTAssertTrue(contents.contains("Bearer new-token"))
        XCTAssertTrue(contents.contains("[mcp_servers.other]"))
        XCTAssertEqual(contents.components(separatedBy: "[mcp_servers.flunner]").count - 1, 1)
    }

    func testInspectReportsConnectedAndOutdated() {
        let writer = AgentMCPConfigWriter(homeDirectory: tempHome)
        _ = writer.sync(
            target: .cursor,
            url: "http://127.0.0.1:47321/mcp",
            token: "token-a"
        )

        let connected = writer.inspect(
            target: .cursor,
            url: "http://127.0.0.1:47321/mcp",
            token: "token-a"
        )
        XCTAssertEqual(connected.status, .connected)

        let outdated = writer.inspect(
            target: .cursor,
            url: "http://127.0.0.1:47321/mcp",
            token: "token-b"
        )
        XCTAssertEqual(outdated.status, .outdated)
    }

    func testAutoSyncEnabledByDefaultWhenFlunnerEntryExists() {
        let key = AgentMCPPreferences.autoSyncAgentsKey
        let previous = UserDefaults.standard.object(forKey: key)
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        UserDefaults.standard.removeObject(forKey: key)

        let writer = AgentMCPConfigWriter(homeDirectory: tempHome)
        XCTAssertFalse(AgentMCPPreferences.isAutoSyncEnabled(for: .cursor, using: writer))

        _ = writer.sync(
            target: .cursor,
            url: "http://127.0.0.1:47321/mcp",
            token: "token-a"
        )
        XCTAssertTrue(AgentMCPPreferences.isAutoSyncEnabled(for: .cursor, using: writer))
    }
}
