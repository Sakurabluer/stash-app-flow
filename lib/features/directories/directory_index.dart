// Server paths are parsed independently of the phone's operating system.
String serverPath(String value) {
  var path = value.replaceAll('\\', '/');
  final unc = path.startsWith('//');
  path = path.replaceAll(RegExp('/+'), '/');
  if (unc) path = '/$path';
  while (path.endsWith('/') &&
      path != '/' &&
      !RegExp(r'^[A-Za-z]:/$').hasMatch(path)) {
    path = path.substring(0, path.length - 1);
  }
  return path;
}

String pathKey(String value) {
  final path = serverPath(value);
  return RegExp(r'^[A-Za-z]:').hasMatch(path) || path.startsWith('//')
      ? path.toLowerCase()
      : path;
}

String parentPath(String value) {
  final path = serverPath(value);
  if (path == '/' || RegExp(r'^[A-Za-z]:/$').hasMatch(path)) return '';
  final last = path.lastIndexOf('/');
  if (last < 0) return '';
  if (last == 0) return '/';
  if (last == 2 && path[1] == ':') return path.substring(0, 3);
  // A UNC share is a root, not a child of an imaginary local directory.
  if (path.startsWith('//') && path.substring(2).split('/').length <= 2) {
    return '';
  }
  return path.substring(0, last);
}

String pathName(String value) {
  final path = serverPath(value);
  final name = path.substring(path.lastIndexOf('/') + 1);
  return name.isEmpty ? path : name;
}

bool pathWithin(String path, String root) {
  final key = pathKey(path);
  final base = pathKey(root);
  return base.isNotEmpty &&
      (key == base || key.startsWith(base.endsWith('/') ? base : '$base/'));
}

bool validScanPath(String path) =>
    path.isNotEmpty &&
    !path.contains('\u0000') &&
    !serverPath(path).split('/').any((part) => part == '.' || part == '..') &&
    (path.startsWith('/') ||
        path.startsWith('\\\\') ||
        RegExp(r'^[A-Za-z]:[/\\]').hasMatch(path));

int naturalCompare(String a, String b) {
  final left = RegExp(
    r'\d+|\D+',
  ).allMatches(a.toLowerCase()).map((m) => m[0]!).toList();
  final right = RegExp(
    r'\d+|\D+',
  ).allMatches(b.toLowerCase()).map((m) => m[0]!).toList();
  for (var i = 0; i < left.length && i < right.length; i++) {
    final x = left[i];
    final y = right[i];
    var c = 0;
    if (RegExp(r'^\d+$').hasMatch(x) && RegExp(r'^\d+$').hasMatch(y)) {
      final xn = x.replaceFirst(RegExp(r'^0+'), '');
      final yn = y.replaceFirst(RegExp(r'^0+'), '');
      c = xn.length.compareTo(yn.length);
      if (c == 0) c = xn.compareTo(yn);
    } else {
      c = x.compareTo(y);
    }
    if (c != 0) return c;
  }
  final c = left.length.compareTo(right.length);
  return c != 0 ? c : a.compareTo(b);
}

class DirectoryVideo {
  DirectoryVideo({
    required this.id,
    required this.createdAt,
    required this.paths,
  });
  final String id;
  final String createdAt;
  final List<String> paths;

  factory DirectoryVideo.fromJson(Map<String, dynamic> json) => DirectoryVideo(
    id: json['id'].toString(),
    createdAt: json['created_at'] as String? ?? '',
    paths: (json['files'] as List? ?? [])
        .map((f) => (f as Map)['path'] as String? ?? '')
        .where((p) => p.isNotEmpty)
        .toList(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'created_at': createdAt,
    'files': paths.map((p) => {'path': p}).toList(),
  };

  String filenameIn(
    String directory,
    bool recursive, {
    Iterable<String> hidden = const [],
  }) {
    final matching =
        paths
            .where(
              (p) => fileInScope(p, (
                path: directory,
                recursive: recursive,
              ), hidden),
            )
            .toList()
          ..sort(naturalCompare);
    return matching.isEmpty ? id : pathName(matching.first);
  }
}

class MediaDirectory {
  MediaDirectory(this.path);
  final String path;
  final Set<String> directIds = {};
  final Set<String> allIds = {};
  final Set<String> children = {};
  String? folderId;
  bool archive = false;
}

class ServerFolder {
  const ServerFolder({
    required this.id,
    required this.path,
    this.archive = false,
  });
  final String id;
  final String path;
  final bool archive;
  factory ServerFolder.fromJson(Map<String, dynamic> json) => ServerFolder(
    id: json['id'].toString(),
    path: json['path'] as String,
    archive: json['archive'] == true || json['zip_file'] != null,
  );
  Map<String, dynamic> toJson() => {'id': id, 'path': path, 'archive': archive};
}

typedef DirectoryScope = ({String path, bool recursive});

// Match a file inside the selected scope; hidden copies do not hide visible copies.
bool fileInScope(String file, DirectoryScope scope, Iterable<String> hidden) {
  final parent = parentPath(file);
  return (scope.recursive
          ? pathWithin(parent, scope.path)
          : pathKey(parent) == pathKey(scope.path)) &&
      !hidden.any((root) => pathWithin(parent, root));
}

class DirectoryIndex {
  DirectoryIndex({
    required this.videos,
    required this.scanRoots,
    required this.updatedAt,
    this.folders = const [],
  }) {
    for (final folder in folders) {
      var path = serverPath(folder.path);
      if (path.isEmpty) continue;
      final node = nodes.putIfAbsent(
        pathKey(path),
        () => MediaDirectory(folder.path),
      );
      node.folderId = folder.id;
      node.archive = folder.archive;
      final visited = <String>{};
      while (path.isNotEmpty && visited.add(pathKey(path))) {
        final current = path;
        nodes.putIfAbsent(pathKey(current), () => MediaDirectory(current));
        final parent = parentPath(current);
        if (parent.isNotEmpty) {
          nodes
              .putIfAbsent(pathKey(parent), () => MediaDirectory(parent))
              .children
              .add(pathKey(current));
        }
        path = parent;
      }
    }
    for (final video in videos.values) {
      for (final file in video.paths) {
        var path = parentPath(file);
        if (path.isEmpty) continue;
        final direct = nodes.putIfAbsent(
          pathKey(path),
          () => MediaDirectory(path),
        );
        direct.directIds.add(video.id);
        final visited = <String>{};
        while (path.isNotEmpty && visited.add(pathKey(path))) {
          final currentPath = path;
          final node = nodes.putIfAbsent(
            pathKey(path),
            () => MediaDirectory(currentPath),
          );
          node.allIds.add(video.id);
          final parent = parentPath(path);
          if (parent.isNotEmpty) {
            nodes
                .putIfAbsent(pathKey(parent), () => MediaDirectory(parent))
                .children
                .add(pathKey(path));
          }
          path = parent;
        }
      }
    }
    final candidates = scanRoots
        .where((p) => nodes.containsKey(pathKey(p)))
        .map(pathKey)
        .toSet();
    // Configured roots take priority; files outside them remain discoverable.
    for (final video in videos.values) {
      for (final file in video.paths) {
        if (candidates.any((root) => pathWithin(file, root))) continue;
        var root = parentPath(file);
        if (root.isEmpty) continue;
        while (parentPath(root).isNotEmpty &&
            parentPath(root) != '/' &&
            !RegExp(r'^[A-Za-z]:/$').hasMatch(parentPath(root))) {
          root = parentPath(root);
        }
        candidates.add(pathKey(root));
      }
    }
    // Historical image folders can remain indexed after a scan root is removed.
    for (final folder in folders) {
      if (folder.path.isEmpty ||
          nodes[pathKey(folder.path)]!.children.isNotEmpty ||
          candidates.any(
            (root) =>
                pathWithin(folder.path, root) || pathWithin(root, folder.path),
          )) {
        continue;
      }
      var root = serverPath(folder.path);
      while (parentPath(root).isNotEmpty &&
          parentPath(root) != '/' &&
          !RegExp(r'^[A-Za-z]:/$').hasMatch(parentPath(root)) &&
          !candidates.any(
            (configured) => pathWithin(configured, parentPath(root)),
          )) {
        root = parentPath(root);
      }
      candidates.add(pathKey(root));
    }
    roots =
        candidates
            .where(
              (p) => !candidates.any(
                (other) => other != p && pathWithin(p, other),
              ),
            )
            .toList()
          ..sort((a, b) => naturalCompare(nodes[a]!.path, nodes[b]!.path));
  }

  final Map<String, DirectoryVideo> videos;
  final List<String> scanRoots;
  final DateTime updatedAt;
  final List<ServerFolder> folders;
  final Map<String, MediaDirectory> nodes = {};
  late final List<String> roots;

  MediaDirectory? directory(String path) => nodes[pathKey(path)];

  int sceneCount(
    String path, {
    bool recursive = false,
    Iterable<String> hidden = const [],
  }) {
    final node = directory(path);
    if (node == null) return 0;
    final ids = recursive ? node.allIds : node.directIds;
    return hidden.isEmpty
        ? ids.length
        : ids
              .where(
                (id) => videos[id]!.paths.any(
                  (p) => fileInScope(p, (
                    path: path,
                    recursive: recursive,
                  ), hidden),
                ),
              )
              .length;
  }

  List<String> sceneIds(
    String path, {
    bool recursive = false,
    bool byDate = false,
    bool descending = false,
    Iterable<String> hidden = const [],
  }) {
    final node = directory(path);
    if (node == null) return [];
    final names = <String, String>{};
    final ids = (recursive ? node.allIds : node.directIds)
        .where(
          (id) =>
              hidden.isEmpty ||
              videos[id]!.paths.any(
                (p) =>
                    fileInScope(p, (path: path, recursive: recursive), hidden),
              ),
        )
        .toList();
    if (!byDate) {
      for (final id in ids) {
        names[id] = videos[id]!.filenameIn(path, recursive, hidden: hidden);
      }
    }
    ids.sort((a, b) {
      final c = byDate
          ? videos[a]!.createdAt.compareTo(videos[b]!.createdAt)
          : naturalCompare(names[a]!, names[b]!);
      final result = c == 0 ? naturalCompare(a, b) : c;
      return descending ? -result : result;
    });
    return ids;
  }

  factory DirectoryIndex.fromJson(Map<String, dynamic> json) => DirectoryIndex(
    videos: {
      for (final row in json['videos'] as List)
        (row as Map)['id'].toString(): DirectoryVideo.fromJson(
          Map<String, dynamic>.from(row),
        ),
    },
    scanRoots: List<String>.from(json['roots'] as List),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
    folders: (json['folders'] as List? ?? [])
        .map(
          (row) => ServerFolder.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList(),
  );

  Map<String, dynamic> toJson() => {
    'videos': videos.values.map((v) => v.toJson()).toList(),
    'roots': scanRoots,
    'updatedAt': updatedAt.toIso8601String(),
    'folders': folders.map((f) => f.toJson()).toList(),
  };
}
