# ZenNIO

<img src="https://github.com/gerardogrisolini/ZenRetail/blob/master/Assets/logo.png?raw=true" width="80" alt="ZenRetail - RMS" />

HTTP Server for IoT

<ul>
<li>Non-blocking, event-driven architecture built on top of Apple's SwiftNIO delivers high performance.</li>
<li>Written in Swift, the powerful programming language that is also easy to learn.</li>
<li>Expressive, protocol-oriented design with a focus on type-safety and maintainability.</li>
</ul>


### Getting Started

ZenNIO primarily uses SwiftPM as its build tool, so we recommend using that as well. If you want to depend on ZenNIO in your own project, it's as simple as adding a dependencies clause to your Package.swift:
```
dependencies: [
    .package(url: "https://github.com/gerardogrisolini/ZenNIO.git", from: "2.5.2")
]
```
and then adding the appropriate ZenNIO module(s) to your target dependencies.


### Make server
```
import ZenNIO

let server = ZenNIO()
```

### Webroot with static files
```
server.addWebroot(path: "/Library/WebServer/Documents")
```

### CORS
```
server.addCORS()
```

### Authentication and Filters ( http://localhost:8888/auth )

```
server.addAuthentication(handler: { (email, password) -> String in
    if email == "admin" && password == "admin" {
        return "uniqueId"
    }
    return ""
})
server.setFilter(true, methods: [.POST], url: "/*")
```

### Make routes and handlers

```
let router = ZenIoC.shared.resolve() as Router

router.get("/hello.html") { req, res in
    res.send(html: "<html><body><h1>Hello World!</h1></body></html>")
    res.success()
}

router.get("/hello.txt") { req, res in
    res.send(text: "Hello World!")
    res.success()
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
```

### Start server

```
try server.start()
```

### Start server (SSL / HTTP2)

```
try server.startSecure(
    certFile: "certificate.crt",
    keyFile: "private.pem",
    http: .v2
)
```
