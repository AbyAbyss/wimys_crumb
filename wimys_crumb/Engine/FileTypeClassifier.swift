// FileTypeClassifier.swift
// Static extension → FileTypeCategory dictionary. Used in the scan hot path
// (millions of calls), so this must allocate nothing per file: lookups are
// direct dictionary reads keyed by an already-lowercased String.

import Foundation

enum FileTypeClassifier {

    /// Lowercased file extension → category. `nil` (no extension) and unknown
    /// extensions fall through to `.other`.
    private static let table: [String: FileTypeCategory] = {
        var m: [String: FileTypeCategory] = [:]

        // Video
        for ext in ["mov","mp4","m4v","avi","mkv","wmv","webm","mpg","mpeg",
                    "flv","3gp","hevc","prores","mts","m2ts","ts","vob"] {
            m[ext] = .video
        }

        // Photos
        for ext in ["jpg","jpeg","png","heic","heif","gif","bmp","tiff","tif",
                    "raw","cr2","cr3","nef","arw","dng","webp","psd","ai","svg",
                    "icns","ico"] {
            m[ext] = .photos
        }

        // Code
        for ext in ["swift","m","mm","h","hpp","c","cc","cpp","cxx",
                    "java","kt","kts","scala","groovy",
                    "js","mjs","cjs","jsx","ts","tsx","vue","svelte",
                    "py","pyc","pyo","ipynb",
                    "rb","erb","go","rs","php","cs","fs","fsx",
                    "html","htm","css","scss","sass","less",
                    "json","yaml","yml","toml","xml","plist","graphql","gql",
                    "sql","sh","bash","zsh","fish",
                    "lua","r","jl","elm","clj","cljs","ex","exs","erl","hrl",
                    "dart","nim","zig","v","hs","ml","mli","pl","pm","tcl",
                    "md","markdown","rst","tex",
                    "lock","gradle","cmake"] {
            m[ext] = .code
        }

        // Apps
        for ext in ["app","dmg","pkg","mpkg","xip","ipa","apk"] {
            m[ext] = .apps
        }

        // Documents
        for ext in ["pdf","doc","docx","odt","rtf","pages",
                    "xls","xlsx","ods","numbers","csv","tsv",
                    "ppt","pptx","odp","key",
                    "txt","epub","mobi","azw","azw3"] {
            m[ext] = .documents
        }

        // Music
        for ext in ["mp3","aac","m4a","wav","flac","alac","ogg","oga","opus",
                    "wma","aif","aiff","mid","midi","ape","dsf"] {
            m[ext] = .music
        }

        // Archives
        for ext in ["zip","tar","gz","tgz","bz2","tbz","xz","txz","zst","lz",
                    "rar","7z","sit","sitx","jar","war","ear","iso"] {
            m[ext] = .archives
        }

        return m
    }()

    /// Classify by extension. `ext` should be already lowercased; pass the empty
    /// string or nil for files with no extension.
    @inline(__always)
    static func category(forExtension ext: String?) -> FileTypeCategory {
        guard let ext, !ext.isEmpty else { return .other }
        return table[ext] ?? .other
    }
}
