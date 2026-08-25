import Foundation
import Network
import MCP

final class FlunnerMCPHTTPListener: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.flunner.mcp.http")
    private let token: String
    private let handler: @Sendable (HTTPRequest) async -> HTTPResponse
    private var listener: NWListener?

    init(token: String, handler: @escaping @Sendable (HTTPRequest) async -> HTTPResponse) {
        self.token = token
        self.handler = handler
    }

    func start(preferredPort: UInt16 = FlunnerMCPAuth.preferredPort) throws -> UInt16 {
        var lastError: Error?
        for offset in 0..<FlunnerMCPAuth.portAttempts {
            let port = preferredPort + UInt16(offset)
            do {
                try start(on: port)
                return port
            } catch {
                lastError = error
            }
        }
        throw lastError ?? FlunnerMCPListenerError.bindFailed
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func start(on port: UInt16) throws {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host("127.0.0.1"),
            port: NWEndpoint.Port(rawValue: port)!
        )

        let listener = try NWListener(using: parameters)
        let group = DispatchGroup()
        group.enter()
        var startError: Error?

        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                group.leave()
            case let .failed(error):
                startError = error
                group.leave()
            case .cancelled:
                if startError == nil {
                    startError = FlunnerMCPListenerError.cancelled
                }
                group.leave()
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.start(queue: queue)

        let result = group.wait(timeout: .now() + 2)
        listener.stateUpdateHandler = nil
        if result == .timedOut {
            listener.cancel()
            throw FlunnerMCPListenerError.timeout
        }
        if let startError {
            listener.cancel()
            throw startError
        }
        self.listener = listener
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] content, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            if error != nil {
                connection.cancel()
                return
            }
            var data = buffer
            if let content {
                data.append(content)
            }
            if let request = HTTPRequestParser.parse(data) {
                Task {
                    let response = await self.route(request)
                    self.send(response, on: connection)
                }
                return
            }
            if isComplete || data.count > 1_000_000 {
                connection.cancel()
                return
            }
            self.receive(on: connection, buffer: data)
        }
    }

    private func route(_ request: HTTPRequest) async -> HTTPResponse {
        let path = request.path?.split(separator: "?").first.map(String.init) ?? "/"
        guard path == "/mcp" else {
            return .error(statusCode: 404, .invalidRequest("Not Found"))
        }
        guard FlunnerMCPAuth.isAuthorized(headers: request.headers, token: token) else {
            return .error(
                statusCode: 401,
                .invalidRequest("Unauthorized"),
                extraHeaders: [HTTPHeaderName.wwwAuthenticate: "Bearer"]
            )
        }
        return await handler(request)
    }

    private func send(_ response: HTTPResponse, on connection: NWConnection) {
        var headerLines = [
            "HTTP/1.1 \(response.statusCode) \(Self.statusText(response.statusCode))",
        ]
        var headers = response.headers
        if headers[HTTPHeaderName.contentType] == nil, response.bodyData != nil {
            headers[HTTPHeaderName.contentType] = "application/json"
        }
        headers["Connection"] = "close"
        let body = response.bodyData ?? Data()
        headers["Content-Length"] = "\(body.count)"
        for (key, value) in headers {
            headerLines.append("\(key): \(value)")
        }
        var payload = Data(headerLines.joined(separator: "\r\n").utf8)
        payload.append(Data("\r\n\r\n".utf8))
        payload.append(body)
        connection.send(content: payload, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private static func statusText(_ code: Int) -> String {
        switch code {
        case 200: "OK"
        case 202: "Accepted"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        default: "Error"
        }
    }
}

enum FlunnerMCPListenerError: LocalizedError {
    case bindFailed
    case timeout
    case cancelled

    var errorDescription: String? {
        switch self {
        case .bindFailed: "Could not bind the MCP server to localhost."
        case .timeout: "Timed out starting the MCP listener."
        case .cancelled: "The MCP listener was cancelled."
        }
    }
}

enum HTTPRequestParser {
    static func parse(_ data: Data) -> HTTPRequest? {
        guard let headerRange = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headerData = data[..<headerRange.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else { return nil }
        let lines = headerText.split(separator: "\r\n", omittingEmptySubsequences: false)
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count >= 2 else { return nil }

        let method = String(parts[0])
        let path = String(parts[1])
        var headers: [String: String] = [:]
        for line in lines.dropFirst() where !line.isEmpty {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<separator])
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        let contentLength = headers.first { $0.key.lowercased() == "content-length" }
            .flatMap { Int($0.value) } ?? 0
        let bodyStart = headerRange.upperBound
        let available = data.count - bodyStart
        guard available >= contentLength else { return nil }
        let body = contentLength > 0 ? Data(data[bodyStart..<(bodyStart + contentLength)]) : nil
        return HTTPRequest(method: method, headers: headers, body: body, path: path)
    }
}
