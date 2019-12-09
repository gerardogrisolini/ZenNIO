import XCTest
import Logging
import NIO
import NIOHTTP1
import ZenNIOSSL
@testable import ZenNIO

final class ZenNIOTests: XCTestCase {
    
    func testRouter() {
        let router = Router()
        
        // GET static uri
        router.get("/hello")  { _, _ in }
        
        var request = HttpRequest(head: HTTPRequestHead(version: HTTPVersion(major: 2, minor: 0), method: .GET, uri: "/hello"), body: [])
        guard let route = router.getRoute(request: &request) else {
            XCTFail("route not found")
            return
        }
        XCTAssertTrue(route.params.count == 0)
        
        
        // GET string parameter
        router.get("/hello/:name/number/:number") { _, _ in }
        
        request = HttpRequest(head: HTTPRequestHead(version: HTTPVersion(major: 2, minor: 0), method: .GET, uri: "/hello/guest/number/11"), body: [])
        guard router.getRoute(request: &request) != nil else {
            XCTFail("route not found")
            return
        }
        let name: String? = request.getParam("name")
        XCTAssertTrue(name != nil && name! == "guest")
        let number: Int? = request.getParam("number")
        XCTAssertTrue(number != nil && number! == 11)

        
        // POST json body data
        router.post("/api/client") { _, _ in }
        
        let client = Client(id: 1, name: "Guest", email: "guest@domain.com")
        let body = try! JSONEncoder().encode(client)
        request = HttpRequest(head: HTTPRequestHead(version: HTTPVersion(major: 2, minor: 0), method: .POST, uri: "/api/client"), body: [UInt8](body))
        guard router.getRoute(request: &request) != nil else {
            XCTFail("route not found")
            return
        }
        XCTAssertNoThrow(try JSONDecoder().decode(Client.self, from: Data(request.body)))
    }
    
    func testHttpRequest() {
        var request = HttpRequest(head: HTTPRequestHead(version: HTTPVersion(major: 2, minor: 0), method: .GET, uri: "/api/client?id=1"), body: [])
        request.parseRequest()
        
        let id: Int? = request.getParam("id")
        XCTAssertTrue(id != nil)

        
        // multipart
        let path = URL(fileURLWithPath: "/var/log")
        let urls = try! FileManager.default.contentsOfDirectory(at: path, includingPropertiesForKeys: [URLResourceKey.isRegularFileKey], options: [])
        var filesOnly = urls.filter { !$0.hasDirectoryPath }
        if filesOnly.count > 5 {
            filesOnly = filesOnly.dropLast(filesOnly.count - 5)
        }
        
        let boundary = Uploader.generateBoundaryString()
        let data = try! Uploader.createBody(with: [ "note" : "Test note" ], filePathKey: "files", paths: filesOnly, boundary: boundary)
        var head = HTTPRequestHead(version: HTTPVersion(major: 2, minor: 0), method: .POST, uri: "/api/upload")
        head.headers.add(name: "Content-Type", value: "multipart/form-data;boundary=" + boundary)
        request = HttpRequest(head: head, body: [UInt8](data))
        request.parseRequest()
        
        guard let fileNames: String = request.getParam("files"),
            let note: String = request.getParam("note") else {
                XCTFail("parameter files or note")
                return
        }
        
        for fileName in fileNames.split(separator: ",", omittingEmptySubsequences: true) {
            if let file: Data = request.getParam(fileName.description) {
                print(fileName)
                XCTAssertTrue(file.count >= 0)
            }
        }
        XCTAssertTrue(note == "Test note")
    }
    
    func testHttpResponse() {
        let response = HttpResponse(body: ByteBufferAllocator().buffer(capacity: 0))
        let client = Client(id: 1, name: "Guest", email: "guest@domain.com")
        XCTAssertNoThrow(try response.send(json: client))
        XCTAssertTrue(response.body.readableBytes > 0)
        
        response.success(.accepted)
        XCTAssertTrue(response.status == .accepted)
        
        response.failure(.badRequest("test"))
        XCTAssertTrue(response.status == .badRequest)
    }
    
    func testHttpSession() {
        ZenIoC.shared.register { Router() as Router }
        let request = HttpRequest(head: HTTPRequestHead(version: HTTPVersion(major: 2, minor: 0), method: .GET, uri: "/"), body: [])
        let response = HttpResponse(body: ByteBufferAllocator().buffer(capacity: 0))
        let serverHandler = ServerHandler(fileIO: nil, errorHandler: nil)
        XCTAssertTrue(serverHandler.processSession(request, response, false))
        XCTAssertTrue(response.headers.contains(name: HttpHeader.setCookie.rawValue))
    }
    
    func testRequest() {
        let router = Router()
        let server = ZenNIO(router: router)
        router.get("/api/client/:id") { req, res in
            res.success()
        }
        
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
            var request = HttpRequest(head: HTTPRequestHead(version: HTTPVersion(major: 2, minor: 0), method: .GET, uri: "/api/client/1"), body: [])
            guard let route = router.getRoute(request: &request) else {
                XCTFail("route not found")
                server.stop()
                return
            }
            
            let id: Int? = request.getParam("id")
            XCTAssertTrue(id != nil)
            
            request.eventLoop = server.eventLoopGroup.next()
            let serverHandler = ServerHandler(fileIO: nil, errorHandler: nil)
            serverHandler.processRequest(allocator: server.channel!.allocator, request: request, route: route).whenComplete { result in
                switch result {
                case .success(let response):
                    XCTAssertTrue(response.status == .ok)
                case .failure(let err):
                    XCTFail(err.localizedDescription)
                }
                server.stop()
            }
        }
        
        XCTAssertNoThrow(try server.start(signal: false))
    }
    
    func testFilter() {
        let router = Router()
        router.post("/filter") { req, res in
            res.success()
        }
        let server = ZenNIO(router: router)
        server.setFilter(true, methods: [.POST], url: "/filter")
        
        var request = HttpRequest(head: HTTPRequestHead(version: HTTPVersion(major: 2, minor: 0), method: .POST, uri: "/filter"), body: [])
        guard let route = router.getRoute(request: &request) else {
            XCTFail("route not found")
            return
        }
        let response = HttpResponse(body: ByteBufferAllocator().buffer(capacity: 0))
        let serverHandler = ServerHandler(fileIO: nil, errorHandler: nil)
        XCTAssertFalse(serverHandler.processSession(request, response, route.filter))
    }

    func testAuthentication() {
        let router = Router()
        let server = ZenNIO(router: router)
        server.addAuthentication(handler: { (email, password) -> EventLoopFuture<String> in
            if email == "admin" && password == "admin" {
                return server.eventLoopGroup.next().makeSucceededFuture("uniqueId")
            }
            return server.eventLoopGroup.next().makeFailedFuture(HttpError.unauthorized)
        })
        router.post("/filter") { req, res in
            res.send(html: "<h1>Authenticated</h1>")
            res.success()
        }
        server.setFilter(true, methods: [.POST], url: "/filter")

        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
            var urlRequest = URLRequest(url: URL(string: "http://localhost:8888/api/login")!)
            urlRequest.httpMethod = "POST"
            urlRequest.addValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            urlRequest.addValue("application/json", forHTTPHeaderField: "Accept")

            let account = Account(username: "admin", password: "admin")
            urlRequest.httpBody = try! JSONEncoder().encode(account)
            
            URLSession.shared.dataTask(with: urlRequest) { (data, response, error) in
                if let error = error {
                    XCTFail(error.localizedDescription)
                    server.stop()
                    return
                }

                guard let data = data, let token = try? JSONDecoder().decode(Token.self, from: data) else {
                    XCTFail("body data")
                    server.stop()
                    return
                }
                
                var request = URLRequest(url: URL(string: "http://localhost:8888/filter")!)
                request.httpMethod = "POST"
                request.addValue("text/html; charset=utf-8", forHTTPHeaderField: "Content-Type")
                request.addValue("text/html", forHTTPHeaderField: "Accept")
                request.url = URL(string: "http://localhost:8888/filter")!
                request.addValue("Bearer: \(token.bearer)", forHTTPHeaderField: "Authentication")

                URLSession.shared.dataTask(with: request) { (data, response, error) in
                    server.stop()

                    if let error = error {
                        XCTFail(error.localizedDescription)
                        return
                    }
                    
                    let res = response as! HTTPURLResponse
                    XCTAssertTrue(res.statusCode != 401)
                
                }.resume()
            }.resume()
        }

        XCTAssertNoThrow(try server.start(signal: false))
    }
    
    func testFileIO() {
        let server = ZenNIO()
        server.addWebroot(path: FileManager.default.currentDirectoryPath)
        
        let data = "Hello".data(using: .utf8)!
        XCTAssertTrue(FileManager.default.createFile(atPath: "index.html", contents: data, attributes: nil))
        
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
            let url = URL(string: "http://localhost:8888/index.html")!
            URLSession.shared.dataTask(with: url) { (data, response, error) in
                server.stop()
                
                if let error = error {
                    XCTFail(error.localizedDescription)
                    return
                }
                
                let res = response as! HTTPURLResponse
                XCTAssertTrue(res.statusCode == 200)
                
            }.resume()
        }
        
        XCTAssertNoThrow(try server.start(signal: false))
        XCTAssertNoThrow(try FileManager.default.removeItem(atPath: "index.html"))
    }
    
    func testErrorHandler() {
        let router = Router()
        let server = ZenNIO(router: router)
        server.addError { (ctx, request, error) -> EventLoopFuture<HttpResponse> in
            print(error)
            let response = HttpResponse(body: ctx.channel.allocator.buffer(capacity: 0))
            response.send(text: error.localizedDescription)
            response.success(.internalServerError)
            return ctx.eventLoop.makeSucceededFuture(response)
        }
        
        router.get("/error") { req, res in
            res.failure(HttpError.internalError("test"))
        }
        
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
            let url = URL(string: "http://localhost:8888/error")!
            URLSession.shared.dataTask(with: url) { (data, response, error) in
                server.stop()
                
                if let error = error {
                    XCTFail(error.localizedDescription)
                    return
                }
                
                let res = response as! HTTPURLResponse
                XCTAssertTrue(res.statusCode == 500)
                
            }.resume()
        }

        XCTAssertNoThrow(try server.start(signal: false))
    }
    
    func testStart() {
        let server = ZenNIO(logs: [.file, .console])
//        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
//            server.stop()
//        }
        XCTAssertNoThrow(try server.start(signal: false))
    }
    
    func testStartHTTP2() {
        let crt = certificate.data(using: .utf8)!
        XCTAssertTrue(FileManager.default.createFile(atPath: "certificate.crt", contents: crt, attributes: nil))
        let key = privateKey.data(using: .utf8)!
        XCTAssertTrue(FileManager.default.createFile(atPath: "private.pem", contents: key, attributes: nil))

        let server = ZenNIO()
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
            server.stop()
        }

        XCTAssertNoThrow(
            try server.startSecure(
                certFile: "certificate.crt",
                keyFile: "private.pem",
                http: .v2
            )
        )

        XCTAssertNoThrow(try FileManager.default.removeItem(atPath: "certificate.crt"))
        XCTAssertNoThrow(try FileManager.default.removeItem(atPath: "private.pem"))
    }
    
    func testLogging() {
        _ = ZenNIO(logs: [.file])
        try? FileManager.default.removeItem(atPath: ZenLogger.file)
        
        var logger = ZenIoC.shared.resolve() as Logger
        logger.logLevel = .debug
        logger.log(level: .info, Logger.Message(stringLiteral: "Log info"))
        logger.log(level: .debug, Logger.Message(stringLiteral: "Log debug"))
        logger.log(level: .trace, Logger.Message(stringLiteral: "Log trace"))

        if let data = ZenLogger.data, let text = String(data: data, encoding: .utf8) {
            let count = text.split(separator: "\n").count
            XCTAssertTrue(count == 2)
        } else {
            XCTFail("log not found")
        }
    }
    
    
    static var allTests = [
        ("testRouter", testRouter),
        ("testHttpRequest", testHttpRequest),
        ("testHttpResponse", testHttpResponse),
        ("testHttpSession", testHttpSession),
        ("testFilter", testFilter),
        ("testAuthentication", testAuthentication),
        ("testFileIO", testFileIO),
        ("testErrorHandler", testErrorHandler),
        ("testLogging", testLogging),
        ("testStart", testStart),
        ("testStartHTTP2", testStartHTTP2)
    ]
    
    
    struct Client : Codable {
        var id : Int = 0
        var name: String = ""
        var email: String = ""
    }
    
    let certificate = """
-----BEGIN CERTIFICATE-----
MIIFGjCCBAKgAwIBAgISA8/rjX9qd+BbNW6HW9CazcliMA0GCSqGSIb3DQEBCwUA
MEoxCzAJBgNVBAYTAlVTMRYwFAYDVQQKEw1MZXQncyBFbmNyeXB0MSMwIQYDVQQD
ExpMZXQncyBFbmNyeXB0IEF1dGhvcml0eSBYMzAeFw0xODAzMjExOTM0MTBaFw0x
ODA2MTkxOTM0MTBaMB4xHDAaBgNVBAMTE3d3dy53ZWJyZXRhaWwuY2xvdWQwggEi
MA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCrjPtNyRyZyJsoWeZTps5V0P6s
v7yyRW9u3aGot31D2dmHI+DuJrXDVRedq7AS0BiWG0rNtVSPbfTzwz3l2g7EUXLb
Pvhshti5wTsEsrrN7gdLmD425XBxrH9pBWTanwLEorEvz/sofPD1yslR5PLoRNfK
7e/VxFKcsSnjOcZia9ETFX78Vrtmuu+O5Co775vyHtJR/WPpIXM8LneCZd2arX58
L/3MlJA6xplFH+N5WnloMI2TdK0hn64r0Th4DoNGVUzmw07ZOcfF64trkbYp5wxo
erOh0UDbnl2E1tgL8QdJi+h8k/53NCt1Z2ZnLEEa+32VzWxcJ8KMpmKeWd3FAgMB
AAGjggIkMIICIDAOBgNVHQ8BAf8EBAMCBaAwHQYDVR0lBBYwFAYIKwYBBQUHAwEG
CCsGAQUFBwMCMAwGA1UdEwEB/wQCMAAwHQYDVR0OBBYEFBDN5OWCH90COV5P2uRF
jmPZai5nMB8GA1UdIwQYMBaAFKhKamMEfd265tE5t6ZFZe/zqOyhMG8GCCsGAQUF
BwEBBGMwYTAuBggrBgEFBQcwAYYiaHR0cDovL29jc3AuaW50LXgzLmxldHNlbmNy
eXB0Lm9yZzAvBggrBgEFBQcwAoYjaHR0cDovL2NlcnQuaW50LXgzLmxldHNlbmNy
eXB0Lm9yZy8wLwYDVR0RBCgwJoIPd2VicmV0YWlsLmNsb3VkghN3d3cud2VicmV0
YWlsLmNsb3VkMIH+BgNVHSAEgfYwgfMwCAYGZ4EMAQIBMIHmBgsrBgEEAYLfEwEB
ATCB1jAmBggrBgEFBQcCARYaaHR0cDovL2Nwcy5sZXRzZW5jcnlwdC5vcmcwgasG
CCsGAQUFBwICMIGeDIGbVGhpcyBDZXJ0aWZpY2F0ZSBtYXkgb25seSBiZSByZWxp
ZWQgdXBvbiBieSBSZWx5aW5nIFBhcnRpZXMgYW5kIG9ubHkgaW4gYWNjb3JkYW5j
ZSB3aXRoIHRoZSBDZXJ0aWZpY2F0ZSBQb2xpY3kgZm91bmQgYXQgaHR0cHM6Ly9s
ZXRzZW5jcnlwdC5vcmcvcmVwb3NpdG9yeS8wDQYJKoZIhvcNAQELBQADggEBAGpz
eflI0c/qKy/qFONzXoLg+sbqTr9li4AvPN4F29S4mY0dzBFZa0DXD9wXrhwgAAvh
UUR5ElM/UySYIwYSS0HCt1im71ZknWFvkwmP6GbwE6CXHArKUSL1VxqXcRd0CAaY
MUytR37xxzZLsSwV2iUCc/9Z8u8z9jg7KakaTiCjREqJj+0b5DqxzOGDlzqnV4O/
aHGVaazpzMFaXZDTozX3oYWV9+1Oy0FrhhD/jupPESucN8yTWlHQ64LJK8v93NPe
SFSh7jREAA8Irluyo7k43Q0ivmXvZqgNxeACjlVOb+rU+6UFvp6oSWQlslKLBHdf
q4bCEYafRbC5gQlqFR8=
-----END CERTIFICATE-----
"""

    let privateKey = """
-----BEGIN RSA PRIVATE KEY-----
MIIEpAIBAAKCAQEAq4z7TckcmcibKFnmU6bOVdD+rL+8skVvbt2hqLd9Q9nZhyPg
7ia1w1UXnauwEtAYlhtKzbVUj23088M95doOxFFy2z74bIbYucE7BLK6ze4HS5g+
NuVwcax/aQVk2p8CxKKxL8/7KHzw9crJUeTy6ETXyu3v1cRSnLEp4znGYmvRExV+
/Fa7ZrrvjuQqO++b8h7SUf1j6SFzPC53gmXdmq1+fC/9zJSQOsaZRR/jeVp5aDCN
k3StIZ+uK9E4eA6DRlVM5sNO2TnHxeuLa5G2KecMaHqzodFA255dhNbYC/EHSYvo
fJP+dzQrdWdmZyxBGvt9lc1sXCfCjKZinlndxQIDAQABAoIBAA1iRWTvMM0Kqpg+
U0rpc6WcVZIyr00VP7ldjzQzhJFbmK4DbZQG7x1bMSl68JS3KYPkgzSDViKOiJLQ
A69AEPDeDeDvC8Cj0JrFaY5XR12zmVwbd5ce1WP4+kO+SP0JdNTUgJBjYIvrG32B
oa1C+HSIknFhmNmLpIpXBBaXNlQNRmtncDXeyc5BR+Ishv7K+AB3aVuqt8yZsczQ
mPrpUquTuNX3P8r95ImbKiOi7qZV5EPUrPJJ4ceg5BuNZglloUfuZnhXQJOBzWVk
pMF7B4sZgEw0TqTjA0arLoSlXRua4Qtd35tYH5WfWOuggH/FAVlmeLhUgHPxDVru
Fq7d9c0CgYEA6wD0kjtz0KuhLyWFTVVuNs88vGugxG7ylLN1UIy+VdTYLQNyQaIu
V75Q71G3WirB7jCncxU6bowo89SvKlG/l6+7+LwjdUMgte2Yy9GRzY43fouIB3c1
ahTN+LS4KShfdiy45oq9TLGUOCPIOk02uplVJXPV1f7Dm74oXaDmVoMCgYEAuuC3
2bZFnjlecEeA83ca3Xqh6BVSfF0Evd0rN+hFXfh7n/6etGSYNmiMG3dI+pk4iFOt
UGso96lOr7QihsZX/7AMt2pGe16aZsBWpXWpI4hByMIhi0/TqDqZdZgzBfWk3Fpp
nWV10MbuFIP4MAsQQYq4nPya3xeSDKv5Dpr8CBcCgYEAtTSpYVCifxa4VMhTv0vO
jkjCBm/fKVh7iJnQLeo4oapbfmoX4fASV+oSMlcKUGaD3wx5Mc3+nltJAKrQ3orm
dyo0gRlhJfw67s1kclUIXj35IISqwUb0UvXz1IBVOLc+1LqrYGk+ijKrnZZJwFrl
hoDRHO3yxu2JG0BHk9qLgc0CgYEAh/7zLIe94ChltpYCnKsnrNgKrUefEIvs4HLs
ebIZkQo8hTGZszOlpaqtk2tae6w3fNZQQT7KwHjAn5MasTP0ZEls56l6g1tUR8Rf
Ceg3X3lQTlYgbS55nGqQtQg+0W5zPDy7sWRducKbDekAG45hlSDruqsF1aZkjb40
8FEPap8CgYB6NbImv6RIHr2/dIocoTTPvZy5qTgRWuqaIihZr0LyrUZZiyeS06yT
7EH/9cD5B5X5T1MjtLrNy1rpuzhCYlJVOTrtVmS59SDAqvD629vy9lPziLNKnJ/Q
n2eAS9OJ7ZzpqzqdaxpKOR3GhMgPAHAD4FLz1E6a1zBKz8iXmvAA8g==
-----END RSA PRIVATE KEY-----
"""
}
