# ZenNIO

<img src="https://github.com/gerardogrisolini/Webretail/blob/master/webroot/media/logo.png?raw=true" width="80" alt="Webretail - RMS" />

HTTP Server for IoT

<ul>
<li>Non-blocking, event-driven architecture built on top of Apple's SwiftNIO delivers high performance.</li>
<li>Written in Swift, the powerful programming language that is also easy to learn.</li>
<li>Expressive, protocol-oriented design with a focus on type-safety and maintainability.</li>
</ul>


### Getting Started

```
dependencies: [
    .package(url: "https://github.com/gerardogrisolini/ZenNIO.git", from: "1.3.0")
]
```

### Example Usage

```
import ZenNIO

let router = Router()

router.get("/") { req, res in
    res.send(html: "<html><body><h1>Hello World!</h1></body></html>")
    res.completed()
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

let server = ZenNIO(port: 8080, router: router)

// Webroot with static files (optional)
server.addWebroot(path: "/var/www/html")

// CORS (optional)
server.addCORS()

// OAuth2 (optional: http://<ip>:<port>/auth)
server.addAuthentication(handler: { (email, password) -> (Bool) in
    return email == "admin" && password = "admin"
})
server.addFilter(method: .GET, url: "/hello/*")

// SSL (optional)
try server.addSSL(certFile: "./cert.pem", keyFile: "./key.pem", http: .v2)

// Start server
try server.start()
```

## Example Template

### templates/hello.html
```
...
<h1>Hello {{ name}}!</h1>

<p>There are {{ items.count }} items.</p>

<ul>
    {% for item in items %}
    <li>{{ item }}</li>
    {% endfor %}
</ul>
...
```

### API
```
router.get("/hello.html") { req, res in
    self.counter += 1

    let context: [String : Any] = [
        "name": "World",
        "items": ["Item 1", "Item 2", "Item 3"]
    ]
    do {
        try res.send(template: "hello.html", context: context)
        res.completed()
    } catch {
        print(error)
        res.completed(.internalServerError)
    }
}
```

### Dependencies

#### macOS

```
brew install nghttp2 libressl pkg-config
```

#### Ubuntu 18.04

```
apt-get install -y git curl libatomic1 libicu60 libxml2 libz-dev pkg-config clang netcat-openbsd lsof perl nghttp2 libnghttp2-dev
```
