// CIDR Atlas
// Export destination checks and atomic export file replacement.
// Author: Sergio Farfan <sergio.farfan@gmail.com>

import 'dart:io';

const _sqliteCompanions = ['', '-wal', '-shm', '-journal'];

/// Throws a [FormatException] when [destination] names the open inventory
/// [database] or one of its SQLite companion files.
///
/// Both paths are compared after resolving symbolic links, so a link or a
/// relative path to the database is refused as well. On macOS and Windows,
/// whose default file systems ignore case, the comparison ignores case.
void checkExportDestination(String destination, String database) {
  final target = canonicalPath(destination);
  final protected = <String>{
    for (final base in {File(database).absolute.path, canonicalPath(database)})
      for (final suffix in _sqliteCompanions) '$base$suffix',
  };
  final ignoreCase = Platform.isMacOS || Platform.isWindows;
  bool same(String a, String b) =>
      a == b || (ignoreCase && a.toLowerCase() == b.toLowerCase());
  var refused = protected.any((path) => same(path, target));
  if (!refused && File(destination).existsSync()) {
    for (final path in protected) {
      if (File(path).existsSync() &&
          FileSystemEntity.identicalSync(destination, path)) {
        refused = true;
        break;
      }
    }
  }
  if (refused) {
    throw FormatException('--file $destination is the open inventory database '
        'or one of its SQLite files; choose a different export path.');
  }
}

/// Writes [content] to a temporary file beside the export target and renames
/// it into place, so a failed write never truncates an earlier export.
///
/// The target is [destination] itself or, for a symbolic link, the file the
/// link points at ([exportTarget]); a dangling link is followed and its
/// target created, as an in-place write would. When the target already
/// exists, the temporary file starts as a copy of it, so the replacement
/// keeps the earlier file's permission mode (for example 600 on a restricted
/// backup) without a window in which the new content is more widely
/// readable. Ownership is that of the current user.
void writeExportAtomically(String destination, String content) {
  final target = exportTarget(destination);
  final temporary =
      File('$target.tmp-$pid-${DateTime.now().microsecondsSinceEpoch}');
  try {
    if (FileSystemEntity.typeSync(target) == FileSystemEntityType.file) {
      try {
        File(target).copySync(temporary.path);
      } on FileSystemException catch (error) {
        throw FileSystemException(
            'Cannot read the existing export to keep its permissions; '
            'choose a different --file',
            target,
            error.osError);
      }
    }
    temporary.writeAsStringSync(content, flush: true);
    temporary.renameSync(target);
  } finally {
    if (temporary.existsSync()) temporary.deleteSync();
  }
}

const _maximumLinkHops = 40;

/// The file an export to [destination] writes: [destination] when it is not
/// a symbolic link, otherwise the end of its link chain, which may not exist
/// yet. Relative link targets are resolved against the link's directory.
/// Throws a [FileSystemException] for a link loop.
String exportTarget(String destination) {
  if (!FileSystemEntity.isLinkSync(destination)) return destination;
  var current = File(destination).absolute.path;
  var hops = 0;
  while (FileSystemEntity.isLinkSync(current)) {
    if (++hops > _maximumLinkHops) {
      throw FileSystemException(
          'Too many levels of symbolic links', destination);
    }
    final next = Link(current).targetSync();
    current = File(next).isAbsolute
        ? next
        : '${File(current).parent.path}${Platform.pathSeparator}$next';
  }
  return current;
}

/// The absolute path of [path] with symbolic links resolved as far as the
/// file system allows: the file itself when it exists, the target of a
/// dangling link, otherwise its nearest existing ancestor directory.
String canonicalPath(String path) {
  final file = File(path).absolute;
  // typeSync follows links and also finds directories, such as `sub/..`.
  if (FileSystemEntity.typeSync(file.path) != FileSystemEntityType.notFound) {
    return file.resolveSymbolicLinksSync();
  }
  if (FileSystemEntity.isLinkSync(file.path)) {
    // A dangling link: an export writes its eventual target.
    return canonicalPath(exportTarget(file.path));
  }
  final separator = Platform.pathSeparator;
  final segments =
      file.path.split(separator).where((segment) => segment.isNotEmpty);
  final name = segments.isEmpty ? '' : segments.last;
  if (name == '.' || name == '..') {
    // A missing directory followed by `..` cannot be resolved by the file
    // system; collapse it lexically so the comparison errs towards refusal.
    final normalized = Uri.file(file.path).normalizePath().toFilePath();
    return normalized == file.path ? file.path : canonicalPath(normalized);
  }
  final parent = file.parent;
  if (parent.path == file.path) return file.path;
  final resolvedParent = canonicalPath(parent.path);
  return resolvedParent.endsWith(separator)
      ? '$resolvedParent$name'
      : '$resolvedParent$separator$name';
}
