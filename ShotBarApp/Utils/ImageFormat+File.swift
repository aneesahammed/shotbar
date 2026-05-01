import Foundation
import UniformTypeIdentifiers

extension ImageFormat {
    var fileExtension: String {
        switch self {
        case .png:
            return AppConstants.FileExtensions.png
        case .jpg:
            return AppConstants.FileExtensions.jpg
        }
    }

    var utType: UTType {
        switch self {
        case .png:
            return .png
        case .jpg:
            return .jpeg
        }
    }
}
