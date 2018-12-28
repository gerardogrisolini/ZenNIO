# ZenNIO

<img src="https://github.com/gerardogrisolini/Webretail/blob/master/webroot/media/logo.png?raw=true" width="80" alt="Webretail - RMS" />

HTTP Server for IoT developed with SwiftNIO

#### Under active development. Please do not use.


### Getting Started

```
dependencies: [
    .package(url: "https://github.com/gerardogrisolini/ZenNIO.git", from: "1.0.0")
]
```

### Example Usage

```
import ZenNIO

let router = Router()

router.get("/hello") { req, res in
    res.send(text: "Hello World!")
    res.completed()
}

let server = ZenNIO(port: 8080, router: router)
//server.webroot = "/Users/admin/Projects/zenNio/webroot"
//server.addAuthentication(handler: { (email, password) -> (Bool) in
//    return email == password
//})

try? server.start()

```

macOS

```
brew install nghttp2
```

Ubuntu 18.04

```
apt-get install -y git curl libatomic1 libicu60 libxml2 libz-dev pkg-config clang netcat-openbsd lsof perl nghttp2 libnghttp2-dev
```
