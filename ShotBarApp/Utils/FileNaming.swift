import Foundation

enum FileNaming {
    static func nextAvailableURL(
        in directory: URL,
        baseName: String,
        extension ext: String,
        fileManager: FileManager = .default
    ) -> URL {
        let sanitized = sanitizedBaseName(baseName)
        var candidate = directory.appendingPathComponent(sanitized).appendingPathExtension(ext)
        var counter = 2

        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory
                .appendingPathComponent("\(sanitized) (\(counter))")
                .appendingPathExtension(ext)
            counter += 1
        }

        return candidate
    }

    static func sanitizedBaseName(_ baseName: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:")
        let sanitized = baseName
            .components(separatedBy: invalidCharacters)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return sanitized.isEmpty ? "Screenshot" : sanitized
    }
}
