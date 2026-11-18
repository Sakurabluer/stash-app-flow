import 'package:flutter_test/flutter_test.dart';
import 'package:stash_mobile/features/directories/directory_index.dart';
import 'package:stash_mobile/shared/models/scene.dart';

void main() {
  DirectoryVideo video(String id, List<String> paths, {String date = ''}) =>
      DirectoryVideo(id: id, createdAt: date, paths: paths);

  DirectoryIndex index(
    List<DirectoryVideo> videos, {
    List<String> roots = const ['/media'],
  }) => DirectoryIndex(
    videos: {for (final v in videos) v.id: v},
    scanRoots: roots,
    updatedAt: DateTime.utc(2026, 11, 18),
  );

  test('native picture-only and archive folders survive the cache', () {
    final tree = DirectoryIndex(
      videos: {},
      scanRoots: ['/pictures'],
      updatedAt: DateTime.utc(2026),
      folders: const [
        ServerFolder(id: '1', path: '/pictures/album'),
        ServerFolder(id: '2', path: '/pictures/album/book.zip', archive: true),
      ],
    );
    final restored = DirectoryIndex.fromJson(tree.toJson());
    expect(restored.roots, ['/pictures']);
    expect(restored.directory('/pictures/album')!.folderId, '1');
    expect(restored.directory('/pictures/album/book.zip')!.archive, true);
    expect(restored.directory('/pictures')!.children, {'/pictures/album'});
  });

  test('hidden descendants exclude content but retain a visible duplicate', () {
    final tree = index([
      video('1', ['/media/hidden/1.mp4']),
      video('2', ['/media/hidden/2.mp4', '/media/visible/2.mp4']),
      video('3', ['/media/hidden/deep/3.mp4']),
    ]);
    expect(
      tree.sceneIds('/media', recursive: true, hidden: ['/media/hidden']),
      ['2'],
    );
    expect(
      tree.sceneCount('/media', recursive: true, hidden: ['/media/hidden']),
      1,
    );
    expect(
      fileInScope('/media/AB/1.jpg', (path: '/media/A', recursive: true), []),
      false,
    );
  });

  test('deep directories, boundary checks and unique scene counts agree', () {
    final tree = index([
      video('1', [
        '/media/A/01.mp4',
        '/media/A/02.mp4',
        '/media/A/season/03.mp4',
      ]),
      video('2', ['/media/A/season/deep/04.mp4']),
      video('3', ['/media/AB/05.mp4']),
      video('4', ['/media/A/06.mp4', '/media/AB/07.mp4']),
    ]);
    expect(tree.directory('/media/A')!.directIds, {'1', '4'});
    expect(tree.directory('/media/A')!.allIds, {'1', '2', '4'});
    expect(tree.directory('/media')!.allIds.length, 4);
    expect(tree.directory('/media/A/season/deep')!.directIds, {'2'});
    expect(tree.sceneIds('/media/A', recursive: true), ['1', '2', '4']);
    expect(pathWithin('/media/AB/05.mp4', '/media/A'), isFalse);
    expect(tree.roots, ['/media']);
  });

  test('natural filename order uses the file in the selected directory', () {
    final tree = index([
      video('a', ['/other/Z.mp4', '/media/第10集.mp4'], date: '2026-11-02'),
      video('b', ['/media/第2集.mp4'], date: '2026-11-03'),
      video('c', ['/media/第1集.mp4'], date: '2026-11-01'),
    ]);
    expect(tree.sceneIds('/media'), ['c', 'b', 'a']);
    expect(tree.sceneIds('/media', descending: true), ['a', 'b', 'c']);
    expect(tree.sceneIds('/media', byDate: true, descending: true), [
      'b',
      'a',
      'c',
    ]);
    expect(
      naturalCompare('a99999999999999999999', 'a100000000000000000000'),
      lessThan(0),
    );
  });

  test('Windows drives and UNC shares work without phone path rules', () {
    final tree = index(
      [
        video('1', [r'D:\Media\A\01.mp4', r'd:\media\a\02.mp4']),
        video('2', [r'\\nas\share\video\03.mp4']),
      ],
      roots: [r'D:\Media', r'\\nas\share'],
    );
    expect(tree.directory('d:/MEDIA/a')!.directIds, {'1'});
    expect(tree.directory('//NAS/SHARE/video')!.directIds, {'2'});
    expect(parentPath('D:/'), '');
    expect(parentPath(r'\\nas\share'), '');
    expect(parentPath('/one.mp4'), '/');
    expect(parentPath('/'), '');
    expect(pathWithin('D:/Media2/a.mp4', r'D:\Media'), isFalse);
  });

  test(
    'Linux path case remains significant and unsafe scan paths are rejected',
    () {
      expect(pathWithin('/media/a/x', '/media/A'), isFalse);
      expect(validScanPath('/media/A/../private'), isFalse);
      expect(validScanPath(r'D:\Media\..\private'), isFalse);
      expect(validScanPath('relative/path'), isFalse);
      expect(validScanPath('/media/ok'), isTrue);
      expect(validScanPath(r'D:\Media\ok'), isTrue);
    },
  );

  test(
    'complete index includes scenes beyond the initial page and survives cache round trip',
    () {
      final original = index(
        List.generate(1050, (i) => video('$i', ['/media/season$i/file.mp4'])),
      );
      final restored = DirectoryIndex.fromJson(original.toJson());
      expect(restored.directory('/media/season1049')!.directIds, {'1049'});
      expect(restored.directory('/media')!.allIds.length, 1050);
      expect(restored.updatedAt, original.updatedAt);
    },
  );

  test(
    'configured roots, overlapping roots and unconfigured files stay navigable',
    () {
      final tree = index(
        [
          video('1', ['/media/A/01.mp4']),
          video('2', ['/archive/B/02.mp4']),
        ],
        roots: ['/media', '/media/A', '/empty'],
      );
      expect(tree.roots.toSet(), {'/media', '/archive'});
      expect(tree.directory('/empty'), isNull);
    },
  );

  test(
    'Scene retains every file while preserving existing primary playback fields',
    () {
      final scene = Scene.fromJson({
        'id': '1',
        'files': [
          {'path': '/media/A/1.mp4', 'basename': '1.mp4', 'duration': 42},
          {'path': '/media/B/2.mp4', 'basename': '2.mp4', 'duration': 99},
        ],
      });
      expect(scene.files.map((f) => f.path), [
        '/media/A/1.mp4',
        '/media/B/2.mp4',
      ]);
      expect(scene.filePath, '/media/A/1.mp4');
      expect(scene.durationSeconds, 42);
    },
  );
}
