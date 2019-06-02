import XCTest
@testable import ZenNIO
@testable import ZenNIOSSL
@testable import ZenNIOH2

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
    <meta charset="UTF-8">
    <title>OPC-UA</title>
    <base href="/">
    <meta name="viewport" content="width=device-width, user-scalable=no" />
    <link rel="stylesheet" href="style.css">
    <script src="main.js"></script>
</head>
<body onload="loadContent()">
    <h1>OPC-UA</h1>
    <span>Id <strong id="deviceId"></strong></span>
    <br/><span>Type <strong id="deviceType"></strong></span>
    <div class="header-panel" id="info"></div>
    <div id="content">
        <img src="logo.jpg" />
        <img src="logo1.jpg" />
        <img src="logo.png" />
    </div>
    <div class="control-panel">
        <div class="control-panel-left"><input type="checkbox" id="autoScroller" checked/> scroll to bottom</div>
        <div class="control-panel-left">
            <select id="frequency" onchange="changeFrequency(this.value)">
                <option value="1">1</option>
                <option value="2">2</option>
                <option value="5">5</option>
                <option value="10">10</option>
                <option value="30">30</option>
                <option value="60">60</option>
            </select>
            refresh rate in seconds
        </div>
        <div class="control-panel-right">
            <select id="history"></select>
            <button onclick="showHistory()">Open</button>
        </div>
    </div>
</body>
</html>
"""
            res.addHeader(.link, value: "</logo.jpg>; rel=preload; as=image, </logo1.jpg>; rel=preload; as=image, </logo.png>; rel=preload; as=image,  </style.css>; rel=preload; as=style, </main.js>; rel=preload; as=script")
//            res.addHeader(.cache, value: "no-cache")
//            res.addHeader(.cache, value: "max-age=1440") // 1 days
//            res.addHeader(.expires, value: Date(timeIntervalSinceNow: TimeInterval(1440.0 * 60.0)).rfc5322Date)
            res.send(html: html)
            res.completed()
        }

        /*
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
        */
        
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

        let server = ZenNIOH2(router: router)
        
        // OAuth2 (optional)
        server.addAuthentication(handler: { (email, password) -> (String?) in
            return email == password ? "ok" : nil
        })
        server.setFilter(true, methods: [.POST], url: "/api/client")
        server.setFilter(true, methods: [.POST], url: "/client")

        // Webroot with static files (optional)
        server.addWebroot(path: "/Users/gerardo/Projects/webroot")
        
        // CORS (optional)
        //server.addCORS()
        
        // SSL (optional)
        XCTAssertNoThrow(
            try server.addSSL(
                certFile: "/Users/gerardo/Projects/ZenNIO/certificate.crt",
                keyFile: "/Users/gerardo/Projects/ZenNIO/private.pem"
            )
        )

        XCTAssertNoThrow(try server.start())
    }

    static var allTests = [
        ("testStartServer", testStartServer),
    ]
}
