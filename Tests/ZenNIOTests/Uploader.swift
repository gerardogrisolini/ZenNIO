//
//  Uploader.swift
//  
//
//  Created by Gerardo Grisolini on 27/11/2019.
//

import Foundation

public class Uploader {

    /*
    public static func post(urls: [URL], note: String, completionHandler: @escaping ((Bool) -> (Void))) {

        let configuration = URLSessionConfiguration.default
        let session = URLSession(configuration: configuration)
        
        var url = URL(fileURLWithPath: "http://localhost:8888/api/upload")
        var request = URLRequest(url: url)
        request.cachePolicy = NSURLRequest.CachePolicy.reloadIgnoringLocalAndRemoteCacheData
        
        let boundary = generateBoundaryString()
        
        var headers = request.allHTTPHeaderFields ?? [:]
        //headers["Accept"] = "application/json"
        headers["Content-Type"] = "multipart/form-data;boundary=" + boundary
        request.allHTTPHeaderFields = headers
        request.httpMethod = "POST"
        
        let parameters = [
            "note" : note
        ]
        
        do {
            request.httpBody = try createBody(with: parameters, filePathKey: "files", paths: urls, boundary: boundary)
        }
        catch {
            print(error)
        }
        
        let task = session.uploadTask(with: request, from: request.httpBody!, completionHandler: { (data, response, error) in
            if error == nil {
                //print(NSString(data: data!, encoding: String.Encoding.utf8.rawValue)!)
                completionHandler(true)
            }
            else {
                print(error!)
                completionHandler(false)
            }
        })
        task.resume()
        
        session.finishTasksAndInvalidate()
    }
    */
    
    /// Create body of the `multipart/form-data` request
    ///
    /// - parameter parameters:   The optional dictionary containing keys and values to be passed to web service
    /// - parameter filePathKey:  The optional field name to be used when uploading files. If you supply paths, you must supply filePathKey, too.
    /// - parameter paths:        The optional array of file paths of the files to be uploaded
    /// - parameter boundary:     The `multipart/form-data` boundary
    ///
    /// - returns:                The `Data` of the body of the request

    public static func createBody(with parameters: [String: String]?, filePathKey: String, paths: [URL], boundary: String) throws -> Data {
        var body = Data()
        
        if parameters != nil {
            for (key, value) in parameters! {
                body.append("--\(boundary)\r\n")
                body.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n")
                body.append("\(value)\r\n")
            }
        }
        
        for url in paths {
            let filename = url.lastPathComponent
            let mimetype = mimeType(for: url)
            
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"\(filePathKey)\"; filename=\"\(filename)\"\r\n")
            body.append("Content-Type: \(mimetype)\r\n\r\n")
            
            let data = try Data(contentsOf: url)
            body.append(data)
            body.append("\r\n")
        }
        
        body.append("--\(boundary)--\r\n")
        
        return body
    }

    /// Create boundary string for multipart/form-data request
    ///
    /// - returns:            The boundary string that consists of "Boundary-" followed by a UUID string.

    public static func generateBoundaryString() -> String {
        return "Boundary-\(UUID().uuidString)"
    }

    /// Determine mime type on the basis of extension of a file.
    ///
    /// This requires `import MobileCoreServices`.
    ///
    /// - parameter path:         The path of the file for which we are going to determine the mime type.
    ///
    /// - returns:                Returns the mime type if successful. Returns `application/octet-stream` if unable to determine mime type.

    private static func mimeType(for url: URL) -> String {
        let pathExtension = url.pathExtension
        
        if let uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, pathExtension as NSString, nil)?.takeRetainedValue() {
            if let mimetype = UTTypeCopyPreferredTagWithClass(uti, kUTTagClassMIMEType)?.takeRetainedValue() {
                return mimetype as String
            }
        }
        return "application/octet-stream"
    }
}

extension Data {
    
    /// Append string to Data
    ///
    /// Rather than littering my code with calls to `data(using: .utf8)` to convert `String` values to `Data`, this wraps it in a nice convenient little extension to Data. This defaults to converting using UTF-8.
    ///
    /// - parameter string:       The string to be added to the `Data`.
    
    mutating func append(_ string: String, using encoding: String.Encoding = .utf8) {
        if let data = string.data(using: encoding) {
            append(data)
        }
    }
}
