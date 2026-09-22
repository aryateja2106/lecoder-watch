import CryptoKit
import Darwin
import Foundation

// Keep this device's X25519 private key on the machine.
//
// The on-disk layout matches experiments/device-sync/key-file.ts:
// 32 bytes of clamped scalar, then 32 bytes of the matching public key.
// The file is <stateDir>/device.key mode 600. The directory is mode 700.
// Registration and mailbox JSON are not this file's job, and this type
// does not put the scalar in either of them. It does not dial out, and it
// does not write under a home directory. The shipping menu bar does not
// call it. A short file or a flipped byte fails closed with one error.

enum DeviceKeyFile {
    static let scalarLength = 32
    static let fileLength = 64
    static let fileName = "device.key"

    struct Failure: Error, Equatable {
        let message: String

        static let couldNotOpen = Failure(message: "device key file could not be opened")
        static let notAllowed = Failure(message: "device key state directory is not allowed")
        static let couldNotWrite = Failure(message: "device key file could not be written")
        static let notPrivateKey = Failure(message: "device key is not an x25519 private key")
        static let stateDirectoryRequired = Failure(message: "device key state directory is required")
    }

    static func save(privateKey: Curve25519.KeyAgreement.PrivateKey, stateDir: String) throws {
        let directory = try stateDirectory(stateDir)
        let body = try material(privateKey)
        try writeKeyFile(directory: directory, body: body)
    }

    static func load(stateDir: String) throws -> Curve25519.KeyAgreement.PrivateKey {
        let directory = try stateDirectory(stateDir)
        let file = (directory as NSString).appendingPathComponent(fileName)
        var fd: Int32 = -1
        defer {
            if fd >= 0 { _ = Darwin.close(fd) }
        }
        do {
            var listed = Darwin.stat()
            let listedRC = file.withCString { Darwin.lstat($0, &listed) }
            if listedRC != 0 { throw Failure.couldNotOpen }
            if (listed.st_mode & S_IFMT) == S_IFLNK || (listed.st_mode & S_IFMT) != S_IFREG {
                throw Failure.couldNotOpen
            }
            if listed.st_size != Int64(fileLength) { throw Failure.couldNotOpen }
            fd = file.withCString { Darwin.open($0, Darwin.O_RDONLY | Darwin.O_NOFOLLOW) }
            if fd < 0 { throw Failure.couldNotOpen }
            var info = Darwin.stat()
            if Darwin.fstat(fd, &info) != 0 { throw Failure.couldNotOpen }
            if (info.st_mode & S_IFMT) != S_IFREG || info.st_size != Int64(fileLength) {
                throw Failure.couldNotOpen
            }
            var buffer = [UInt8](repeating: 0, count: fileLength)
            let got = buffer.withUnsafeMutableBytes { raw -> Int in
                guard let base = raw.baseAddress else { return -1 }
                return Darwin.read(fd, base, fileLength)
            }
            if got != fileLength { throw Failure.couldNotOpen }
            let scalar = Data(buffer.prefix(scalarLength))
            let pub = Data(buffer.suffix(scalarLength))
            guard isCanonical(scalar) else { throw Failure.couldNotOpen }
            let key = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: scalar)
            guard key.rawRepresentation == scalar else { throw Failure.couldNotOpen }
            guard key.publicKey.rawRepresentation == pub else { throw Failure.couldNotOpen }
            return key
        } catch let error as Failure {
            if error == .notAllowed || error == .stateDirectoryRequired { throw error }
            throw Failure.couldNotOpen
        } catch {
            throw Failure.couldNotOpen
        }
    }

    private static func material(_ privateKey: Curve25519.KeyAgreement.PrivateKey) throws -> Data {
        let originalPub = privateKey.publicKey.rawRepresentation
        var scalar = [UInt8](privateKey.rawRepresentation)
        guard scalar.count == scalarLength, originalPub.count == scalarLength else {
            throw Failure.notPrivateKey
        }
        scalar[0] &= 248
        scalar[31] &= 127
        scalar[31] |= 64
        let clamped = Data(scalar)
        let restored: Curve25519.KeyAgreement.PrivateKey
        do {
            restored = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: clamped)
        } catch {
            throw Failure.notPrivateKey
        }
        guard restored.rawRepresentation == clamped else { throw Failure.notPrivateKey }
        guard restored.publicKey.rawRepresentation == originalPub else { throw Failure.notPrivateKey }
        var body = Data(clamped)
        body.append(originalPub)
        guard body.count == fileLength else { throw Failure.notPrivateKey }
        return body
    }

    private static func isCanonical(_ scalar: Data) -> Bool {
        guard scalar.count == scalarLength else { return false }
        let bytes = [UInt8](scalar)
        if (bytes[0] & 7) != 0 { return false }
        if (bytes[31] & 0x80) != 0 { return false }
        if (bytes[31] & 0x40) == 0 { return false }
        return true
    }

    private static let exactDeny: Set<String> = [
        "/tmp", "/var/tmp", "/private/tmp", "/home", "/root",
    ]

    private static func denied(_ path: String) -> Bool {
        path.split(omittingEmptySubsequences: true, whereSeparator: { $0 == "/" || $0 == "\\" })
            .contains { $0 == ".mesh" || $0 == "Users" }
    }

    private static func absoluteStandard(_ raw: String) -> String {
        let standard = (raw as NSString).standardizingPath
        if (standard as NSString).isAbsolutePath { return standard }
        let cwd = FileManager.default.currentDirectoryPath
        return ((cwd as NSString).appendingPathComponent(standard) as NSString).standardizingPath
    }

    private static func realPath(_ path: String) -> String? {
        let pointer = path.withCString { realpath($0, nil) }
        guard let pointer else { return nil }
        defer { free(pointer) }
        return String(cString: pointer)
    }

    private static func homeRoots() -> [String] {
        var homes: [String] = []
        func add(_ value: String?) {
            guard let value, !value.isEmpty else { return }
            let abs = absoluteStandard(value)
            if abs == "/" { return }
            homes.append(abs)
            if let real = realPath(abs), real != "/" { homes.append(real) }
        }
        add(FileManager.default.homeDirectoryForCurrentUser.path)
        add(ProcessInfo.processInfo.environment["HOME"])
        add(ProcessInfo.processInfo.environment["USERPROFILE"])
        return homes
    }

    private static func isUnderHome(_ dir: String) -> Bool {
        let dirPath = (dir as NSString).standardizingPath
        for home in homeRoots() {
            if dirPath == home { return true }
            let prefix = home.hasSuffix("/") ? home : home + "/"
            if dirPath.hasPrefix(prefix) { return true }
        }
        return false
    }

    private static func assertAllowed(_ dir: String) throws {
        if denied(dir) || isUnderHome(dir) || dir == "/" || exactDeny.contains(dir) {
            throw Failure.notAllowed
        }
    }

    private static func resolveExisting(_ path: String) throws -> String {
        var cursor = path
        var suffix: [String] = []
        while cursor != "/" && !FileManager.default.fileExists(atPath: cursor) {
            suffix.append((cursor as NSString).lastPathComponent)
            let parent = (cursor as NSString).deletingLastPathComponent
            if parent == cursor { throw Failure.notAllowed }
            cursor = parent
        }
        guard var built = realPath(cursor) else { throw Failure.notAllowed }
        for part in suffix.reversed() {
            built = (built as NSString).appendingPathComponent(part)
        }
        return built
    }

    private static func stateDirectory(_ stateDir: String) throws -> String {
        if stateDir.isEmpty || stateDir.contains("\0") {
            throw Failure.stateDirectoryRequired
        }
        if stateDir.contains("~") || denied(stateDir) {
            throw Failure.notAllowed
        }
        let resolved = absoluteStandard(stateDir)
        try assertAllowed(resolved)
        let real = try resolveExisting(resolved)
        try assertAllowed(real)
        return real
    }

    private static func writeKeyFile(directory: String, body: Data) throws {
        let file = (directory as NSString).appendingPathComponent(fileName)
        var fd: Int32 = -1
        func cleanup() {
            if fd >= 0 {
                _ = Darwin.close(fd)
                fd = -1
                _ = file.withCString { unlink($0) }
            }
        }
        do {
            var info = Darwin.stat()
            let exists = directory.withCString { Darwin.lstat($0, &info) } == 0
            if !exists {
                do {
                    try FileManager.default.createDirectory(
                        atPath: directory,
                        withIntermediateDirectories: true,
                        attributes: [.posixPermissions: 0o700]
                    )
                } catch let error as Failure {
                    throw error
                } catch {
                    throw Failure.couldNotWrite
                }
                if directory.withCString({ Darwin.lstat($0, &info) }) != 0 {
                    throw Failure.couldNotWrite
                }
            }
            if (info.st_mode & S_IFMT) == S_IFLNK || (info.st_mode & S_IFMT) != S_IFDIR {
                throw Failure.couldNotWrite
            }
            let realNow = try resolveExisting(directory)
            try assertAllowed(realNow)
            if realNow != directory { throw Failure.couldNotWrite }
            if directory.withCString({ chmod($0, 0o700) }) != 0 { throw Failure.couldNotWrite }
            if directory.withCString({ Darwin.lstat($0, &info) }) != 0 { throw Failure.couldNotWrite }
            if (info.st_mode & 0o777) != 0o700 { throw Failure.couldNotWrite }
            var current = Darwin.stat()
            if file.withCString({ Darwin.lstat($0, &current) }) == 0 {
                if (current.st_mode & S_IFMT) == S_IFLNK || (current.st_mode & S_IFMT) != S_IFREG {
                    throw Failure.couldNotWrite
                }
            }
            let flags = Darwin.O_WRONLY | Darwin.O_CREAT | Darwin.O_TRUNC | Darwin.O_NOFOLLOW
            fd = file.withCString { Darwin.open($0, flags, mode_t(0o600)) }
            if fd < 0 { throw Failure.couldNotWrite }
            let written = body.withUnsafeBytes { raw -> Int in
                guard let base = raw.baseAddress else { return -1 }
                return Darwin.write(fd, base, body.count)
            }
            if written != body.count { throw Failure.couldNotWrite }
            if Darwin.fchmod(fd, 0o600) != 0 { throw Failure.couldNotWrite }
            var stored = Darwin.stat()
            if Darwin.fstat(fd, &stored) != 0 { throw Failure.couldNotWrite }
            if (stored.st_mode & S_IFMT) != S_IFREG
                || stored.st_size != Int64(body.count)
                || (stored.st_mode & 0o777) != 0o600 {
                throw Failure.couldNotWrite
            }
            _ = Darwin.close(fd)
            fd = -1
        } catch let error as Failure {
            cleanup()
            if error == .notAllowed { throw error }
            throw Failure.couldNotWrite
        } catch {
            cleanup()
            throw Failure.couldNotWrite
        }
    }
}
