import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct DeployCommand: Equatable {
    public var executable: String
    public var arguments: [String]
    public var environment: [String: String]
}

public enum Deploy {
    private static let cloudflareUploadConcurrency = 3

    public static func deploySite(
        root: URL,
        config: InksteadWriterConfig,
        env: [String: String] = ProcessInfo.processInfo.environment,
        http: @escaping HTTPClient = DefaultHTTPClient.send,
        run: (DeployCommand, URL) throws -> Void = runCommand,
        log: (String) -> Void = { print($0) }
    ) async throws {
        guard let deploy = config.deploy else {
            throw InksteadWriterError.config("No deployment provider is configured.")
        }
        let mergedEnv = readEnv(root: root).merging(env) { _, new in new }
        let distDir = root.appendingPathComponent(config.build?.output ?? "dist")
        switch deploy.provider {
        case .cloudflareWorkers:
            guard let projectName = deploy.projectName, !projectName.isEmpty else {
                throw InksteadWriterError.config("Cloudflare Workers deployment requires deploy.projectName.")
            }
            guard let accountID = mergedEnv["CLOUDFLARE_ACCOUNT_ID"], !accountID.isEmpty else {
                throw InksteadWriterError.config("Cloudflare Workers deployment requires CLOUDFLARE_ACCOUNT_ID.")
            }
            guard let apiToken = mergedEnv["CLOUDFLARE_API_TOKEN"], !apiToken.isEmpty else {
                throw InksteadWriterError.config("Cloudflare Workers deployment requires CLOUDFLARE_API_TOKEN.")
            }
            try await deployCloudflareWorkers(distDir: distDir, accountID: accountID, apiToken: apiToken, scriptName: projectName, http: http, log: log)
        case .netlify:
            guard let siteId = mergedEnv["NETLIFY_SITE_ID"], !siteId.isEmpty else {
                throw InksteadWriterError.config("Netlify deployment requires NETLIFY_SITE_ID.")
            }
            guard let authToken = mergedEnv["NETLIFY_AUTH_TOKEN"], !authToken.isEmpty else {
                throw InksteadWriterError.config("Netlify deployment requires NETLIFY_AUTH_TOKEN.")
            }
            try await deployNetlify(distDir: distDir, siteId: siteId, authToken: authToken, http: http)
        case .githubPages:
            guard mergedEnv["GITHUB_ACTIONS"] != nil else {
                throw InksteadWriterError.config("GitHub Pages deployment is handled by GitHub Actions. Push your site to GitHub to publish it.")
            }
            try "".write(to: distDir.appendingPathComponent(".nojekyll"), atomically: true, encoding: .utf8)
        case .gitlabPages:
            guard mergedEnv["GITLAB_CI"] != nil else {
                throw InksteadWriterError.config("GitLab Pages deployment is handled by GitLab CI. Push your site to GitLab to publish it.")
            }
            try "".write(to: distDir.appendingPathComponent(".nojekyll"), atomically: true, encoding: .utf8)
            let publicDir = root.appendingPathComponent("public")
            if FileManager.default.fileExists(atPath: publicDir.path) {
                try FileManager.default.removeItem(at: publicDir)
            }
            try FileManager.default.copyItem(at: distDir, to: publicDir)
        }
    }

    private static func deployCloudflareWorkers(
        distDir: URL,
        accountID: String,
        apiToken: String,
        scriptName: String,
        http: @escaping HTTPClient,
        log: (String) -> Void
    ) async throws {
        let prepareStarted = Date()
        let assets = try cloudflareAssets(in: distDir)
        let totalBytes = assets.reduce(0) { $0 + $1.size }
        log("Cloudflare assets: prepared \(assets.count) files (\(formatBytes(totalBytes))) in \(formatDuration(since: prepareStarted)).")
        let manifest = Dictionary(uniqueKeysWithValues: assets.map { asset in
            ("/\(asset.path)", ["hash": asset.hash, "size": asset.size] as [String: Any])
        })
        let manifestBody = try JSONSerialization.data(withJSONObject: ["manifest": manifest])
        let sessionStarted = Date()
        let uploadSession = try await sendJSON(
            URLRequest.cloudflare(
                url: "https://api.cloudflare.com/client/v4/accounts/\(pathSegment(accountID))/workers/scripts/\(pathSegment(scriptName))/assets-upload-session",
                method: "POST",
                bearerToken: apiToken,
                contentType: "application/json",
                body: manifestBody
            ),
            action: "Cloudflare asset upload session",
            http: http
        )
        log("Cloudflare assets: upload session created in \(formatDuration(since: sessionStarted)).")
        let result = uploadSession["result"] as? [String: Any]
        guard let uploadJWT = result?["jwt"] as? String else {
            throw InksteadWriterError.io("Cloudflare asset upload session did not return an upload token.")
        }
        let buckets = result?["buckets"] as? [[String]] ?? []
        let completionJWT = try await uploadCloudflareAssets(
            buckets: buckets,
            assetsByHash: try cloudflareAssetsByHash(assets),
            uploadJWT: uploadJWT,
            accountID: accountID,
            http: http,
            log: log
        )
        let workerStarted = Date()
        try await uploadCloudflareWorker(accountID: accountID, apiToken: apiToken, scriptName: scriptName, completionJWT: completionJWT, http: http)
        log("Cloudflare Worker uploaded in \(formatDuration(since: workerStarted)).")
    }

    private static func uploadCloudflareAssets(
        buckets: [[String]],
        assetsByHash: [String: CloudflareAsset],
        uploadJWT: String,
        accountID: String,
        http: @escaping HTTPClient,
        log: (String) -> Void
    ) async throws -> String {
        if buckets.isEmpty {
            log("Cloudflare assets: no changed files to upload.")
            return uploadJWT
        }
        let fileCount = buckets.reduce(0) { $0 + $1.count }
        let uploadBytes = buckets.flatMap { $0 }.reduce(0) { total, hash in
            total + (assetsByHash[hash]?.size ?? 0)
        }
        log("Cloudflare assets: uploading \(fileCount) changed files in \(buckets.count) buckets (\(formatBytes(uploadBytes))).")
        let started = Date()
        let client = SendableHTTPClient(send: http)
        var completionJWT: String?
        var uploadedFiles = 0
        try await withThrowingTaskGroup(of: CloudflareBucketUploadResult.self) { group in
            var iterator = buckets.enumerated().makeIterator()

            func enqueueNext() {
                guard let next = iterator.next() else { return }
                group.addTask {
                    try await uploadCloudflareBucket(
                        bucket: next.element,
                        bucketIndex: next.offset,
                        bucketCount: buckets.count,
                        assetsByHash: assetsByHash,
                        uploadJWT: uploadJWT,
                        accountID: accountID,
                        http: client.send
                    )
                }
            }

            for _ in 0..<min(cloudflareUploadConcurrency, buckets.count) {
                enqueueNext()
            }

            while let result = try await group.next() {
                uploadedFiles += result.fileCount
                if let jwt = result.completionJWT {
                    completionJWT = jwt
                }
                log("Cloudflare assets: uploaded \(uploadedFiles) of \(fileCount) files.")
                enqueueNext()
            }
        }
        guard let completionJWT else {
            throw InksteadWriterError.io("Cloudflare asset upload did not return a completion token.")
        }
        log("Cloudflare assets: upload completed in \(formatDuration(since: started)).")
        return completionJWT
    }

    private static func uploadCloudflareBucket(
        bucket: [String],
        bucketIndex: Int,
        bucketCount: Int,
        assetsByHash: [String: CloudflareAsset],
        uploadJWT: String,
        accountID: String,
        http: @escaping HTTPClient
    ) async throws -> CloudflareBucketUploadResult {
        var attempt = 1
        while true {
            do {
                var form = HTTPMultipartForm()
                for hash in bucket {
                    guard let asset = assetsByHash[hash] else {
                        throw InksteadWriterError.io("Cloudflare requested unknown asset hash \(hash).")
                    }
                    let bytes = try Data(contentsOf: asset.url)
                    form.addField(name: hash, value: bytes.base64EncodedString(), contentType: asset.contentType)
                }
                let response = try await sendJSON(
                    URLRequest.cloudflare(
                        url: "https://api.cloudflare.com/client/v4/accounts/\(pathSegment(accountID))/workers/assets/upload?base64=true",
                        method: "POST",
                        bearerToken: uploadJWT,
                        contentType: "multipart/form-data; boundary=\(form.boundary)",
                        body: form.body()
                    ),
                    action: "Cloudflare asset upload bucket \(bucketIndex + 1)/\(bucketCount)",
                    http: http
                )
                let completionJWT = (response["result"] as? [String: Any])?["jwt"] as? String
                return CloudflareBucketUploadResult(fileCount: bucket.count, completionJWT: completionJWT)
            } catch {
                guard attempt < 5 else { throw error }
                let delaySeconds = UInt64(1 << (attempt - 1))
                try await Task.sleep(nanoseconds: delaySeconds * 1_000_000_000)
                attempt += 1
            }
        }
    }

    private static func cloudflareAssetsByHash(_ assets: [CloudflareAsset]) throws -> [String: CloudflareAsset] {
        var output: [String: CloudflareAsset] = [:]
        for asset in assets {
            if let existing = output[asset.hash] {
                if existing.size != asset.size || existing.contentType != asset.contentType {
                    throw InksteadWriterError.io("Cloudflare asset hash collision for \(asset.hash).")
                }
                continue
            }
            output[asset.hash] = asset
        }
        return output
    }

    private static func uploadCloudflareWorker(accountID: String, apiToken: String, scriptName: String, completionJWT: String, http: @escaping HTTPClient) async throws {
        let metadata: [String: Any] = [
            "main_module": "main.js",
            "compatibility_date": "2026-05-10",
            "assets": [
                "jwt": completionJWT,
                "config": [
                    "html_handling": "auto-trailing-slash",
                    "not_found_handling": "404-page"
                ]
            ],
            "bindings": [
                ["name": "ASSETS", "type": "assets"]
            ]
        ]
        let metadataData = try JSONSerialization.data(withJSONObject: metadata)
        var form = HTTPMultipartForm()
        form.addField(name: "metadata", value: String(decoding: metadataData, as: UTF8.self), contentType: "application/json")
        form.addFile(name: "main.js", filename: "main.js", mimeType: "application/javascript+module", bytes: Data(cloudflareWorkerScript.utf8))
        _ = try await sendJSON(
            URLRequest.cloudflare(
                url: "https://api.cloudflare.com/client/v4/accounts/\(pathSegment(accountID))/workers/scripts/\(pathSegment(scriptName))",
                method: "PUT",
                bearerToken: apiToken,
                contentType: "multipart/form-data; boundary=\(form.boundary)",
                body: form.body()
            ),
            action: "Cloudflare Worker upload",
            http: http
        )
    }

    private static func deployNetlify(distDir: URL, siteId: String, authToken: String, http: @escaping HTTPClient) async throws {
        let zip = try ZipArchive.archiveDirectory(distDir)
        guard let url = URL(string: "https://api.netlify.com/api/v1/sites/\(pathSegment(siteId))/deploys") else {
            throw InksteadWriterError.config("NETLIFY_SITE_ID contains characters that cannot be used in a deploy URL.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/zip", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.setValue("\(InksteadWriterMetadata.executableName)/\(InksteadWriterMetadata.currentVersion)", forHTTPHeaderField: "User-Agent")
        request.httpBody = zip
        let response = try await http(request)
        guard (200..<300).contains(response.statusCode) else {
            throw InksteadWriterError.io("Netlify deploy returned \(response.statusCode).")
        }
    }

    private static func sendJSON(_ request: URLRequest, action: String, http: @escaping HTTPClient) async throws -> [String: Any] {
        let response = try await http(request)
        let json = (try? JSONSerialization.jsonObject(with: response.body)) as? [String: Any]
        guard (200..<300).contains(response.statusCode) else {
            let message = cloudflareErrorMessage(json: json) ?? "HTTP \(response.statusCode)"
            throw InksteadWriterError.io("\(action) failed: \(message).")
        }
        if let success = json?["success"] as? Bool, !success {
            let message = cloudflareErrorMessage(json: json) ?? "API returned success=false"
            throw InksteadWriterError.io("\(action) failed: \(message).")
        }
        return json ?? [:]
    }

    private static func cloudflareErrorMessage(json: [String: Any]?) -> String? {
        guard let errors = json?["errors"] as? [[String: Any]], !errors.isEmpty else {
            return nil
        }
        return errors.compactMap { $0["message"] as? String }.joined(separator: "; ")
    }

    private static func cloudflareAssets(in distDir: URL) throws -> [CloudflareAsset] {
        try BuildConcurrency.map(cloudflareAssetFiles(in: distDir)) { file in
            let contentType = DevSupport.contentType(for: file.path)
            let pathExtension = URL(fileURLWithPath: file.path).pathExtension
            return CloudflareAsset(
                path: file.path,
                url: file.url,
                hash: try cloudflareAssetHash(url: file.url, pathExtension: pathExtension),
                size: file.size,
                contentType: contentType
            )
        }
    }

    private static func cloudflareAssetFiles(in distDir: URL) throws -> [CloudflareAssetFile] {
        guard FileManager.default.fileExists(atPath: distDir.path) else {
            throw InksteadWriterError.io("Build output directory \(distDir.path) does not exist.")
        }
        let rootPath = distDir.standardizedFileURL.path
        guard let enumerator = FileManager.default.enumerator(at: distDir, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: []) else {
            throw InksteadWriterError.io("Could not read build output directory \(distDir.path).")
        }
        var files: [CloudflareAssetFile] = []
        for case let file as URL in enumerator {
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true else { continue }
            guard let size = values.fileSize else {
                throw InksteadWriterError.io("Could not read file size for \(file.path).")
            }
            let path = file.standardizedFileURL.path
            let relative = path.hasPrefix(rootPath) ? String(path.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/")) : file.lastPathComponent
            guard !relative.isEmpty else { continue }
            files.append(CloudflareAssetFile(
                path: relative.replacingOccurrences(of: "\\", with: "/"),
                url: file,
                size: size
            ))
        }
        return files.sorted { $0.path < $1.path }
    }

    private static func cloudflareAssetHash(url: URL, pathExtension: String) throws -> String {
        let bytes = try Data(contentsOf: url)
        let input = Data((bytes.base64EncodedString() + pathExtension).utf8)
        return String(BLAKE3.hex(input).prefix(32))
    }

    public static func runCommand(_ command: DeployCommand, cwd: URL) throws {
        let process = Process()
        ProcessSupport.configure(process, launch: ProcessSupport.command(command), cwd: cwd, environment: command.environment)
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw InksteadWriterError.io("\(command.executable) \(command.arguments.joined(separator: " ")) exited with \(process.terminationStatus).")
        }
    }

    private static func readEnv(root: URL) -> [String: String] {
        let file = root.appendingPathComponent(".env")
        guard let source = try? String(contentsOf: file, encoding: .utf8) else { return [:] }
        var output: [String: String] = [:]
        for line in source.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 { output[parts[0]] = parts[1] }
        }
        return output
    }

    private static func pathSegment(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: urlPathSegmentAllowed) ?? value
    }

    private static var urlPathSegmentAllowed: CharacterSet {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return allowed
    }

    private static var cloudflareWorkerScript: String {
        "export default { async fetch(request, env) { return env.ASSETS.fetch(request); } };\n"
    }

    private static func formatDuration(since start: Date) -> String {
        let seconds = Date().timeIntervalSince(start)
        if seconds < 10 {
            return String(format: "%.2fs", seconds)
        }
        return String(format: "%.1fs", seconds)
    }

    private static func formatBytes(_ bytes: Int) -> String {
        let units = ["B", "KB", "MB", "GB"]
        var value = Double(bytes)
        var unit = 0
        while value >= 1024, unit < units.count - 1 {
            value /= 1024
            unit += 1
        }
        if unit == 0 {
            return "\(bytes) B"
        }
        return String(format: "%.1f %@", value, units[unit])
    }
}

private struct CloudflareAssetFile: Sendable {
    var path: String
    var url: URL
    var size: Int
}

private struct CloudflareAsset: Sendable {
    var path: String
    var url: URL
    var hash: String
    var size: Int
    var contentType: String
}

private struct CloudflareBucketUploadResult: Sendable {
    var fileCount: Int
    var completionJWT: String?
}

private struct SendableHTTPClient: @unchecked Sendable {
    var send: HTTPClient
}

private extension URLRequest {
    static func cloudflare(url: String, method: String, bearerToken: String, contentType: String, body: Data) throws -> URLRequest {
        guard let url = URL(string: url) else {
            throw InksteadWriterError.config("Cloudflare URL could not be constructed.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("\(InksteadWriterMetadata.executableName)/\(InksteadWriterMetadata.currentVersion)", forHTTPHeaderField: "User-Agent")
        request.httpBody = body
        return request
    }
}
