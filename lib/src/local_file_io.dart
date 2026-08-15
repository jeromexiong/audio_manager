import 'dart:io' show File;

export 'dart:io' show File;

/// Returns the path of a local [file] on native platforms.
String localFilePath(File file) => file.path;
