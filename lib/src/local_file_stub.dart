/// Minimal [File] placeholder for web/WASM builds, where `dart:io` is
/// unavailable. Only the path is kept; local files are not playable on web.
class File {
  const File(this.path);

  final String path;
}

/// Returns the path of a local [file].
String localFilePath(File file) => file.path;
