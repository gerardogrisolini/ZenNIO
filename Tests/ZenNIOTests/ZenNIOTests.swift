import XCTest
@testable import zenNIO

final class zenNIOTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        
       struct Client : Codable {
            var id : Int = 0
            var name: String = ""
            var email: String = ""
        }

        struct Hello : Codable {
            var ip: String = ""
            var message: String = ""
        }

        let router = Router()
        
        // Authentication
        router.addAuthentication(handler: { (email, password) -> (Bool) in
            return email == password
        })

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
                    .then(res => res.status == 401 ? alert(res.statusText) : res.json())
                    .then(json => json ? alert(JSON.stringify(json)) : console.log('Invalid json'))
                    .catch(error => console.log(error));
                }
            </script>
        </head>
        <body style='text-align:center;'>
            <h1>Welcome to ZenNIO!</h1>
            <p><a href="/auth">Authentication</a></p>
            <p><a href="/farm">Farm</a></p>
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
        router.post("/api/client", secure: true) { req, res in
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
        router.post("/client", secure: true) { req, res in
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
        router.post("/upload", secure: true) { req, res in
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
        
        router.get("/farm") { req, res in
            let houseAnimals: Set = ["🐶", "🐱"]
            let farmAnimals: Set = ["🐮", "🐔", "🐑", "🐶", "🐱"]
            let cityAnimals: Set = ["🐦", "🐭"]
            
            let content = """
houseAnimals: \(houseAnimals.joined(separator: ","))
farmAnimals: \(farmAnimals.joined(separator: ","))
cityAnimals: \(cityAnimals.joined(separator: ","))
"""
            res.send(text: content)
            res.completed()
        }

        router.get("/hello") { req, res in
            res.send(text: "Hello World!")
            res.completed()
        }

        router.get("/hello.html") { req, res in
            res.send(html: "<html><body><h1>Hello World!</h1></body></html>")
            res.completed()
        }

        router.get("/hello/:name") { req, res in
            do {
                guard let name = req.getParam(String.self, key: "name") else {
                    throw HttpError.badRequest
                }

                var hello = Hello()
                hello.ip = req.session.ip
                hello.message = "Hello \(name)!"
            
                try res.send(json: hello)
                res.completed()
            } catch HttpError.badRequest {
                res.completed(.badRequest)
            } catch {
                print(error)
                res.completed(.internalServerError)
            }
        }


        let server = ZenNIO(port: 8080, router: router)
        
//        XCTAssertNoThrow(
//            try server.addSSL(
//                certFile: "/Users/admin/Projects/zenNio/cert.pem",
//                keyFile: "/Users/admin/Projects/zenNio/key.pem",
//                http: .v2
//            )
//        )
        XCTAssertNoThrow(try server.start())
    }


    static var allTests = [
        ("testExample", testExample),
    ]
}
