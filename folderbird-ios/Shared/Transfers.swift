import Foundation

/// A single active or just-finished transfer. frac nil = indeterminate; done = finished (success or error).
struct Xfer: Equatable {
    var label: String
    var frac: Double?
    var done = false
    var error = false
}

/// Streaming download / upload with progress, built on URLSession delegates so a multi-hundred-MB file never
/// sits in memory as one Data (the Android app streams to a cache file for the same reason).
enum Transfers {

    /// Streams a device file to `dest` (replacing it). Progress is reported on the main queue; the fraction is nil
    /// until the server has announced a size.
    static func download(api: Api, deviceId: String, path: String, to dest: URL,
                         progress: (@MainActor (Double?) -> Void)? = nil) async throws {
        let req = try api.request("/api/v1/devices/\(Api.encode(deviceId))/files/download", query: [("path", path)])
        let delegate = DownloadDelegate(dest: dest, hadKey: !api.key.isEmpty, progress: progress)
        let session = URLSession(configuration: Api.config, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let holder = TaskHolder()
        // Cancelling the Swift task (a preview panel torn down mid-download) cancels the transfer, and the
        // delegate then resumes the continuation exactly once with URLError.cancelled.
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                delegate.continuation = cont
                let task = session.downloadTask(with: req)
                holder.task = task
                task.resume()
            }
        }, onCancel: {
            holder.task?.cancel()
        })
    }

    /// Multipart upload of a local file into `folder` on the device (field name "file"). The body is assembled in a
    /// temp file and streamed from disk. Progress (0…1) tracks phone → server bytes; once they are all sent the
    /// SERVER is still delivering to the PC, which the caller shows as an indeterminate phase.
    static func upload(api: Api, deviceId: String, folder: String, fileURL: URL, fileName: String,
                       progress: (@MainActor (Double) -> Void)? = nil) async throws {
        var target = folder
        while target.hasSuffix("\\") || (target.count > 1 && target.hasSuffix("/")) { target.removeLast() }
        let boundary = "fb-" + UUID().uuidString
        let bodyURL = try multipartBody(fileURL: fileURL, fileName: fileName, boundary: boundary)
        defer { try? FileManager.default.removeItem(at: bodyURL) }

        var req = try api.request("/api/v1/devices/\(Api.encode(deviceId))/files/upload", query: [("path", target)], method: "POST")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let delegate = UploadDelegate(hadKey: !api.key.isEmpty, progress: progress)
        let session = URLSession(configuration: Api.config, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            delegate.continuation = cont
            session.uploadTask(with: req, fromFile: bodyURL).resume()
        }
    }

    /// Copies a picked / dropped / shared file into our own sandbox. Nonisolated and async, so it runs off the
    /// caller's actor; coordinated so an iCloud Drive item is downloaded first instead of failing.
    static func stage(_ url: URL, into dir: URL, name: String) async throws -> URL {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let local = dir.appendingPathComponent(name)
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { readURL in
            do {
                if FileManager.default.fileExists(atPath: local.path) { try FileManager.default.removeItem(at: local) }
                try FileManager.default.copyItem(at: readURL, to: local)
            } catch {
                copyError = error
            }
        }
        if let e = coordinationError { throw e }
        if let e = copyError { throw e }
        return local
    }

    private static func multipartBody(fileURL: URL, fileName: String, boundary: String) throws -> URL {
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("fb-upload-\(UUID().uuidString).bin")
        guard FileManager.default.createFile(atPath: out.path, contents: nil) else {
            throw ApiError.message("Couldn't stage the upload.")
        }
        do {
            // The throwing FileHandle APIs turn I/O failures (disk full, vanished file) into errors the callers
            // already render, instead of Objective-C exceptions.
            let writer = try FileHandle(forWritingTo: out)
            defer { try? writer.close() }
            let safeName = fileName
                .replacingOccurrences(of: "\\", with: "_")
                .replacingOccurrences(of: "\"", with: "_")
                .replacingOccurrences(of: "\r", with: "")
                .replacingOccurrences(of: "\n", with: "")
            let head = "--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(safeName)\"\r\nContent-Type: application/octet-stream\r\n\r\n"
            try writer.write(contentsOf: Data(head.utf8))
            let reader = try FileHandle(forReadingFrom: fileURL)
            defer { try? reader.close() }
            while let chunk = try reader.read(upToCount: 1 << 20), !chunk.isEmpty {
                try writer.write(contentsOf: chunk)
            }
            try writer.write(contentsOf: Data("\r\n--\(boundary)--\r\n".utf8))
        } catch {
            try? FileManager.default.removeItem(at: out)
            throw error
        }
        return out
    }
}

private final class TaskHolder: @unchecked Sendable {
    var task: URLSessionTask?
}

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(RedirectPolicy.sanitized(request, from: task))
    }
    let dest: URL
    let hadKey: Bool
    let progress: (@MainActor (Double?) -> Void)?
    var continuation: CheckedContinuation<Void, Error>?
    private var failure: Error?
    private var landed = false

    init(dest: URL, hadKey: Bool, progress: (@MainActor (Double?) -> Void)?) {
        self.dest = dest; self.hadKey = hadKey; self.progress = progress
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let p = progress else { return }
        let frac: Double? = totalBytesExpectedToWrite > 0
            ? min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)) : nil
        Task { @MainActor in p(frac) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else {
            let body = (try? Data(contentsOf: location)) ?? Data()
            failure = Api.httpError(status: status, body: body, hadKey: hadKey)
            return
        }
        do {
            let fm = FileManager.default
            try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.moveItem(at: location, to: dest)
            landed = true
        } catch {
            failure = error
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let c = continuation else { return }
        continuation = nil
        if let e = error { c.resume(throwing: e) }
        else if let f = failure { c.resume(throwing: f) }
        else if landed { c.resume() }
        else { c.resume(throwing: ApiError.message("Download failed.")) }
    }
}

private final class UploadDelegate: NSObject, URLSessionDataDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(RedirectPolicy.sanitized(request, from: task))
    }
    let hadKey: Bool
    let progress: (@MainActor (Double) -> Void)?
    var continuation: CheckedContinuation<Void, Error>?
    private var received = Data()
    private var lastPct = -1

    init(hadKey: Bool, progress: (@MainActor (Double) -> Void)?) { self.hadKey = hadKey; self.progress = progress }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard let p = progress, totalBytesExpectedToSend > 0 else { return }
        let pct = Int(totalBytesSent * 100 / totalBytesExpectedToSend)
        guard pct != lastPct else { return }
        lastPct = pct
        let frac = min(1, Double(totalBytesSent) / Double(totalBytesExpectedToSend))
        Task { @MainActor in p(frac) }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        received.append(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let c = continuation else { return }
        continuation = nil
        if let e = error { c.resume(throwing: e); return }
        let status = (task.response as? HTTPURLResponse)?.statusCode ?? 0
        if (200...299).contains(status) { c.resume() }
        else { c.resume(throwing: Api.httpError(status: status, body: received, hadKey: hadKey)) }
    }
}
