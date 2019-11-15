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
        
        // Default page (text/html)
        router.get("/") { req, res in
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
            res.completed()
        }
        
        // Post account (application/json) JWT required
        router.post("/api/client") { req, res in
            do {
                guard req.body.count > 0 else {
                    throw HttpError.badRequest
                }
                let data = Data(req.body)
                var client = try JSONDecoder().decode(Client.self, from: data)
                client.id = 10
                try res.send(json: client)
                res.completed()
            } catch HttpError.badRequest {
                res.completed(.badRequest)
            } catch {
                print(error)
                res.completed(.internalServerError)
            }
        }
        
        // Get account (application/json)
        router.get("/api/client/:id") { req, res in
            do {
                guard let id: Int = req.getParam("id") else {
                    throw HttpError.badRequest
                }
         
                var client = Client()
                client.id = id
                try res.send(json: client)
                res.completed()
            } catch HttpError.badRequest {
                res.completed(.badRequest)
            } catch {
                print(error)
                res.completed(.internalServerError)
            }
        }

        // Post account (text/html) JWT required
        router.post("/client") { req, res in
            do {
                guard let name: String = req.getParam("name"),
                    let email: String = req.getParam("email") else {
                    throw HttpError.badRequest
                }
         
                res.send(html: "<h3>name: \(name)<br/>email: \(email)</h3>")
                res.completed()
            } catch {
                res.completed(.badRequest)
            }
        }

        // Get account (text/html)
        router.get("/client") { req, res in
            do {
                guard let id: Int = req.getParam("id") else {
                    throw HttpError.badRequest
                }
         
                res.send(text: "client: \(id)")
                res.completed()
            } catch {
                res.completed(.badRequest)
            }
        }

        // Upload file (text/html) JWT required
        router.post("/upload") { req, res in
            do {
                guard let fileName: String = req.getParam("file"),
                    let file: Data = req.getParam(fileName),
                    let note: String = req.getParam("note") else {
                        throw HttpError.badRequest
                }
         
                let url = URL(fileURLWithPath: "/tmp").appendingPathComponent(fileName)
                try file.write(to: url)
                res.send(html: "file: \(url.path)<br/>note: \(note)")
                res.completed()
            } catch HttpError.badRequest {
                res.completed(.badRequest)
            } catch {
                print(error)
                res.completed(.internalServerError)
            }
        }

        router.get("/hello") { req, res in
            res.send(text: "Hello World!")
            res.completed()            
        }
        
        router.get("/hello/:name") { req, res in
            do {
                guard let name: String = req.getParam("name") else {
                    throw HttpError.badRequest
                }

                let json = [
                    "ip": req.clientIp,
                    "message": "Hello \(name)!"
                ]
                try res.send(json: json)
                res.completed()
            } catch HttpError.badRequest {
                res.completed(.badRequest)
            } catch {
                print(error)
                res.completed(.internalServerError)
            }
        }

        
        // ZenNIO
        let server = ZenNIO(port: 8888, router: router)
        
        // OAuth2 (optional)
        server.addAuthentication(handler: { (email, password) -> EventLoopFuture<String> in
            return server.eventLoopGroup.next().makeSucceededFuture(email == password ? "ok" : "")
        })
        server.setFilter(true, methods: [.POST], url: "/api/client")
        server.setFilter(true, methods: [.POST], url: "/client")

        // Webroot with static files (optional)
        server.addWebroot(path: "/Library/WebServer/Documents")
        
        // CORS (optional)
        server.addCORS()
        
        // Error handler (optional)
        server.addError { (ctx, request, error) -> HttpResponse in
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
                html += "<h3>\(type(of: error)) error</h3>"
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
            return response
        }

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
