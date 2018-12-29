# ZenNIO

<img src="https://github.com/gerardogrisolini/Webretail/blob/master/webroot/media/logo.png?raw=true" width="80" alt="Webretail - RMS" />

HTTP Server for IoT developed with SwiftNIO

#### Under active development. Please do not use.


### Getting Started

```
dependencies: [
    .package(url: "https://github.com/gerardogrisolini/ZenNIO.git", from: "1.0.4")
]
```

### Example Usage

```
import ZenNIO

let router = Router()

// Optional authentication on: http://<ip>:<port>/auth
router.addAuthentication(handler: { (email, password) -> (Bool) in
    return email == "admin" && password == "admin"
})

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
            "ip": req.session!.ip,
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
//server.webroot = "/Users/admin/Projects/zenNio/webroot"

do {
    try server.start()
} catch {
    print(error)
}

```

macOS

```
brew install nghttp2
```

Ubuntu 18.04

```
apt-get install -y git curl libatomic1 libicu60 libxml2 libz-dev pkg-config clang netcat-openbsd lsof perl nghttp2 libnghttp2-dev
```
