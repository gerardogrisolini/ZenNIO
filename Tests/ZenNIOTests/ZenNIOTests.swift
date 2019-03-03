import XCTest
@testable import ZenNIO
@testable import ZenSMTP

final class ZenNIOTests: XCTestCase {

    struct Client : Codable {
        var id : Int = 0
        var name: String = ""
        var email: String = ""
    }

    func testSendEmail() {
        var response: Bool = false
        
        let email = Email(
            fromName: "ZenSMTP",
            fromEmail: "info@grisolini.com",
            toName: nil,
            toEmail: "gerardo@grisolini.com",
            subject: "Email test",
            body: "<html><body><h1>Email attachment test</h1></body></html>",
            attachments: [
                Attachment(
                    fileName: "logo.png",
                    contentType: "image/png",
                    data: AuthenticationProvider().logo
                )
            ]
        )

        let config = ServerConfiguration(
            hostname: "pro.eu.turbo-smtp.com",
            port: 25,
            username: "g.grisolini@bluecityspa.com",
            password: "Sm0CPGnB",
            cert: nil, //.file("/Users/gerardo/Projects/ZenNIO/SSL/cert.pem"),
            key: nil //.file("/Users/gerardo/Projects/ZenNIO/SSL/key.pem")
        )
        
        let smtp = ZenSMTP(config: config)
        
        smtp.send(email: email) { error in
            if let error = error {
                print("❌ : \(error)")
            } else {
                response = true
                print("✅")
            }
        }

        let exp = expectation(description: "Test send email for 10 seconds")
        let result = XCTWaiter.wait(for: [exp], timeout: 10.0)
        if result == XCTWaiter.Result.timedOut {
            XCTAssertTrue(response)
        } else {
            XCTFail("Test interrupted")
        }
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
                guard let id = req.getParam(Int.self, key: "id") else {
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
                guard let name = req.getParam(String.self, key: "name"),
                    let email = req.getParam(String.self, key: "email") else {
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
                guard let id = req.getParam(Int.self, key: "id") else {
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
                guard let fileName = req.getParam(String.self, key: "file"),
                    let file = req.getParam(Data.self, key: fileName),
                    let note = req.getParam(String.self, key: "note") else {
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
                guard let name = req.getParam(String.self, key: "name") else {
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

        let server = ZenNIO(router: router)
        
        // OAuth2 (optional)
        server.addAuthentication(handler: { (email, password) -> (Bool) in
            return email == password
        })
        server.addFilter(method: .POST, url: "/*")
//        // Webroot with static files (optional)
//        server.addWebroot(path: "/var/www/html")
//        // CORS (optional)
//        server.addCORS()
//        // SSL (optional)
        XCTAssertNoThrow(
            try server.addSSL(
                certFile: "/Users/gerardo/Projects/ZenNIO/SSL/cert.pem",
                keyFile: "/Users/gerardo/Projects/ZenNIO/SSL/key.pem",
                http: .v2
            )
        )

        XCTAssertNoThrow(try server.start())
    }

    static var allTests = [
        ("testSendEmail", testSendEmail),
        ("testStartServer", testStartServer),
    ]
}
