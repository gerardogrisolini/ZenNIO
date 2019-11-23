import XCTest
import NIO
import NIOHTTP1
import ZenNIO
@testable import ZenNIOSSL

final class ZenNIOTests: XCTestCase {

    struct Client : Codable {
        var id : Int = 0
        var name: String = ""
        var email: String = ""
    }

    func testStartServer() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        
        let router = Router()

        router.get("/hello") { req, res in
            res.send(text: "Hello World!")
            res.success()
        }
        
        // Default page (text/html)
        router.get("/test") { req, res in
            let html = """
<!DOCTYPE html>
<html>
<head>
    <meta charset='UTF-8'>
    <title>ZenNIO</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <script>
        function submitJson() {
            const json = JSON.stringify({
                id: 0,
                name: document.getElementById("name").value,
                email: document.getElementById("email").value
            });
            const url = "/api/client";
            fetch(url, {
                headers: {
                  'Content-Type': 'application/json;charset=UTF-8',
                  'Authorization': localStorage.getItem('token')
                },
                method : "POST",
                //mode: 'cors',
                cache: 'no-cache',
                body: json
            })
            .then(res => res.status == 401 ? alert(res.status + ' - Unauthorized') : res.json())
            .then(json => json ? alert(JSON.stringify(json)) : console.log('Invalid json'))
            .catch(error => console.log(error));
        }
    </script>
</head>
<body style='text-align:center;'>
    <h1>Welcome to ZenNIO!</h1>
    <p><a href="/auth">Authentication</a></p>
    <p><a href="/hello">Hello</a></p>
    <hr>
    <p><a href="/client?id=10">Get (text/html)</a></p>
    <p><a href="/api/client/10">Get (application/json)</a></p>
    <hr>
    Authentication required (JWT)
    <form method="POST" action="/client">
        <br/><input type="text" id="name" name="name" placeholder="name"/>
        <br/><input type="text" id="email" name="email" placeholder="email"/>
        <br/>
        <input type="submit" name="submit" value="Post (application/x-www-form-urlencoded)"/>
        <input type="button" name="button" value="Post (application/json)" onclick="submitJson()"/>
    </form>
    <hr>
    <form method="POST" action="/upload" enctype="multipart/form-data">
        <input type="text" name="note" placeholder="note"/>
        <input type="file" name="file"/>
        <input type="submit" name="submit" value="Post (multipart/form)"/>
    </form>
    <hr>
</body>
</html>
"""
            res.send(html: html)
            res.success()
        }
        
        // Post account (application/json) JWT required
        router.post("/api/client") { req, res in
            guard let client = try? JSONDecoder().decode(Client.self, from: Data(req.body)) else {
                return res.failure(.badRequest("body data"))
            }

            do {
                try res.send(json: client)
                res.success()
            } catch {
                res.failure(.internalError(error.localizedDescription))
            }
        }
        
        // Get account (application/json)
        router.get("/api/client/:id") { req, res in
            guard let id: Int = req.getParam("id") else {
                return res.failure(.badRequest("parameter id"))
            }

            do {
                var client = Client()
                client.id = id
                try res.send(json: client)
                res.success()
            } catch {
                res.failure(.internalError(error.localizedDescription))
            }
        }

        // Post account (text/html) JWT required
        router.post("/client") { req, res in
            guard let name: String = req.getParam("name"),
                let email: String = req.getParam("email") else {
                return res.failure(.badRequest("parameter name and/or email"))
            }

            res.send(html: "<h3>name: \(name)<br/>email: \(email)</h3>")
            res.success()
        }

        // Get account (text/html)
        router.get("/client") { req, res in
            guard let id: Int = req.getParam("id") else {
                res.failure(.badRequest("parameter id"))
                return
            }

            res.send(text: "client: \(id)")
            res.success()
        }

        // Upload file (text/html) JWT required
        router.post("/upload") { req, res in
            guard let fileName: String = req.getParam("file"),
                let file: Data = req.getParam(fileName),
                let note: String = req.getParam("note") else {
                return res.failure(.badRequest("parameter file and/or note"))
            }

            do {
                let url = URL(fileURLWithPath: "/tmp").appendingPathComponent(fileName)
                try file.write(to: url)
                res.send(html: "file: \(url.path)<br/>note: \(note)")
                res.success()
            } catch {
                res.failure(.internalError(error.localizedDescription))
            }
        }
        
        router.get("/hello/:name") { req, res in
            guard let name: String = req.getParam("name") else {
                return res.failure(.badRequest("parameter name"))
            }

            do {
                let json = [
                    "ip": req.clientIp,
                    "message": "Hello \(name)!"
                ]
                try res.send(json: json)
                res.success()
            } catch {
                res.failure(.internalError(error.localizedDescription))
            }

        }

        
        // ZenNIO
        let server = ZenNIO(numberOfThreads: 4, router: router)
        server.logger.logLevel = .trace
        
        // OAuth2 (optional)
        server.addAuthentication(handler: { (email, password) -> EventLoopFuture<String> in
            return server.eventLoopGroup.next().makeSucceededFuture(email == password ? "ok" : "")
        })
        server.setFilter(true, methods: [.POST], url: "/api/client")
        server.setFilter(true, methods: [.POST], url: "/client")

        /*
        // Webroot with static files (optional)
        server.addWebroot(path: "/Library/WebServer/Documents")

        // CORS (optional)
        server.addCORS()

        // Error handler (optional)
        server.addError { (ctx, request, error) -> EventLoopFuture<HttpResponse> in
            var html = ""
            var status: HTTPResponseStatus
            switch error {
            case let e as IOError where e.errnoCode == ENOENT:
                html += "<h3>IOError (not found)</h3>"
                status = .notFound
            case let e as IOError:
                html += "<h3>IOError (other)</h3><h4>\(e.description)</h4>"
                status = .expectationFailed
            default:
                html += "<h3>\(error)</h3>"
                status = .internalServerError
            }

            html = """
<!DOCTYPE HTML PUBLIC "-//IETF//DTD HTML 2.0//EN">
<html>
<head><title>ZenNIO</title></head>
<body>
    <h1>Test error handler</h1>
    \(html)
</body>
</html>
"""
            let response = HttpResponse(body: ctx.channel.allocator.buffer(capacity: 0))
            response.send(html: html)
            response.completed(status)
            return ctx.eventLoop.makeSucceededFuture(response)
        }
        */
        
        XCTAssertNoThrow(try server.start())
        
        // SSL and HTTP2 (secure mode)
        //XCTAssertNoThrow(
        //    try server.startSecure(
        //        certFile: "/Users/gerardo/Projects/Zen/ZenNIO/certificate.crt",
        //        keyFile: "/Users/gerardo/Projects/Zen/ZenNIO/private.pem",
        //        http: .v2
        //    )
        //)
    }
    
    static var allTests = [
        ("testStartServer", testStartServer),
    ]
}
