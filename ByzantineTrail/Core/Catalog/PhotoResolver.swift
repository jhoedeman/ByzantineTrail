import Foundation

struct PhotoResolver {
    let photoBaseURL: URL
    /// Injected for testability; production passes a Bundle lookup.
    let thumbExistsInBundle: (String) -> Bool

    init(photoBaseURL: URL, bundle: Bundle = .main) {
        self.photoBaseURL = photoBaseURL
        self.thumbExistsInBundle = { relativePath in
            let name = (relativePath as NSString).lastPathComponent
            let base = (name as NSString).deletingPathExtension
            let ext = (name as NSString).pathExtension
            return bundle.url(forResource: base, withExtension: ext, subdirectory: "thumbs") != nil
        }
    }

    init(photoBaseURL: URL, thumbExistsInBundle: @escaping (String) -> Bool) {
        self.photoBaseURL = photoBaseURL
        self.thumbExistsInBundle = thumbExistsInBundle
    }

    func thumbURL(for photo: Photo) -> URL {
        if thumbExistsInBundle(photo.thumb) {
            let name = (photo.thumb as NSString).lastPathComponent
            return Bundle.main.bundleURL
                .appendingPathComponent("thumbs")
                .appendingPathComponent(name)
        }
        return photoBaseURL.appendingPathComponent(photo.thumb)
    }

    func fullURL(for photo: Photo) -> URL {
        photoBaseURL.appendingPathComponent(photo.full)
    }
}
