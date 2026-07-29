import 'package:flutter_test/flutter_test.dart';
import 'package:stash_mobile/core/server/server_session.dart';

void main() {
  test('normalizes server URLs', () {
    expect(
      normalizeServerUrl('  http://example.test:9999///  '),
      'http://example.test:9999',
    );
    expect(normalizeServerUrl('https://example.test'), 'https://example.test');
  });

  test('server ID is stable for equivalent URLs', () {
    expect(
      serverIdForUrl('http://example.test:9999/'),
      serverIdForUrl('  http://example.test:9999  '),
    );
    expect(
      serverIdForUrl('http://example.test:9999'),
      isNot(serverIdForUrl('https://example.test:9999')),
    );
  });

  test('SavedServer JSON round-trip preserves metadata', () {
    const server = SavedServer(
      id: 'server-id',
      name: '家庭服务器',
      baseUrl: 'http://example.test:9999',
      version: '0.31.1',
      sceneCount: 42,
      tagCount: 9,
    );

    final restored = SavedServer.fromJson(server.toJson());

    expect(restored.id, server.id);
    expect(restored.name, server.name);
    expect(restored.baseUrl, server.baseUrl);
    expect(restored.version, server.version);
    expect(restored.sceneCount, server.sceneCount);
    expect(restored.tagCount, server.tagCount);
  });
}
