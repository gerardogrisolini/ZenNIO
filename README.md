# ZenNIO

<img src="https://github.com/gerardogrisolini/Webretail/blob/master/webroot/media/logo.png?raw=true" width="80" alt="Webretail - RMS" />

HTTP Server for IoT

<ul>
<li>Non-blocking, event-driven architecture built on top of Apple's SwiftNIO delivers high performance.</li>
<li>Written in Swift, the powerful programming language that is also easy to learn.</li>
<li>Expressive, protocol-oriented design with a focus on type-safety and maintainability.</li>
</ul>

#### ZenNIO's master branch is at the moment developing what will become SwiftNIO 2.0.0 which will be Swift 5-only. 


### Getting Started

```
dependencies: [
    .package(url: "https://github.com/gerardogrisolini/ZenNIO.git", from: "1.1.2")
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
            "ip": req.session.ip,
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

## Example Template

### templates/hello.html
```
...
Hello {{ name}}!

There are {{ items.count }} items.

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
brew install nghttp2
```

#### Ubuntu 18.04

```
apt-get install -y git curl libatomic1 libicu60 libxml2 libz-dev pkg-config clang netcat-openbsd lsof perl nghttp2 libnghttp2-dev
```
