import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../network/stash_api_client.dart';

String normalizeServerUrl(String value) =>
    value.trim().replaceFirst(RegExp(r'/+$'), '');

String serverIdForUrl(String value) =>
    sha256.convert(utf8.encode(normalizeServerUrl(value))).toString();

class SavedServer {
  const SavedServer({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.version,
    required this.sceneCount,
    required this.tagCount,
  });

  final String id;
  final String name;
  final String baseUrl;
  final String version;
  final int sceneCount;
  final int tagCount;

  factory SavedServer.fromJson(Map<String, dynamic> json) => SavedServer(
    id: json['id'] as String,
    name: json['name'] as String,
    baseUrl: json['baseUrl'] as String,
    version: json['version'] as String? ?? '',
    sceneCount: json['sceneCount'] as int? ?? 0,
    tagCount: json['tagCount'] as int? ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'baseUrl': baseUrl,
    'version': version,
    'sceneCount': sceneCount,
    'tagCount': tagCount,
  };
}

class ServerSession {
  const ServerSession({required this.server, required this.apiKey});

  final SavedServer server;
  final String apiKey;

  String get id => server.id;
  String get name => server.name;
  String get baseUrl => server.baseUrl;
  String get version => server.version;
  int get sceneCount => server.sceneCount;
  int get tagCount => server.tagCount;
}

class ServerConnectionState {
  const ServerConnectionState({required this.servers, this.activeSession});

  final List<SavedServer> servers;
  final ServerSession? activeSession;
}

final serverSessionProvider =
    AsyncNotifierProvider<ServerSessionController, ServerConnectionState>(
      ServerSessionController.new,
    );

final activeServerSessionProvider = Provider<ServerSession?>((ref) {
  return ref.watch(serverSessionProvider).asData?.value.activeSession;
});

final savedServersProvider = Provider<List<SavedServer>>((ref) {
  return ref.watch(serverSessionProvider).asData?.value.servers ?? const [];
});

class ServerSessionController extends AsyncNotifier<ServerConnectionState> {
  static const _serversKey = 'servers_v2';
  static const _activeServerIdKey = 'active_server_id_v2';
  static const _legacyServerUrlKey = 'server_url';
  static const _legacyApiKeyKey = 'stash_api_key';
  static const _storage = FlutterSecureStorage();

  static String _apiKeyStorageKey(String serverId) => 'stash_api_key_$serverId';

  @override
  Future<ServerConnectionState> build() async {
    final preferences = await SharedPreferences.getInstance();
    var servers = _readServers(preferences);
    if (servers.isEmpty) {
      servers = await _migrateLegacyServer(preferences);
    }

    final activeId = preferences.getString(_activeServerIdKey);
    final activeServer = _findById(servers, activeId);
    if (activeServer == null) {
      return ServerConnectionState(servers: servers);
    }

    final apiKey = await _storage.read(key: _apiKeyStorageKey(activeServer.id));
    if (apiKey == null || apiKey.isEmpty) {
      await preferences.remove(_activeServerIdKey);
      return ServerConnectionState(servers: servers);
    }

    try {
      final session = await _createSession(
        activeServer.baseUrl,
        apiKey,
        name: activeServer.name,
      );
      servers = _replaceServer(servers, session.server);
      await _persistServers(preferences, servers);
      return ServerConnectionState(servers: servers, activeSession: session);
    } catch (_) {
      return ServerConnectionState(servers: servers);
    }
  }

  Future<void> connect(String baseUrl, String apiKey, {String? name}) async {
    final current =
        state.asData?.value ?? const ServerConnectionState(servers: []);
    final normalized = normalizeServerUrl(baseUrl);
    final trimmedKey = apiKey.trim();
    final existing = current.servers
        .where((server) => server.baseUrl == normalized)
        .firstOrNull;
    final displayName = name?.trim().isNotEmpty == true
        ? name!.trim()
        : existing?.name ?? _defaultServerName(normalized);
    final session = await _createSession(
      normalized,
      trimmedKey,
      name: displayName,
    );
    final servers = _replaceServer(current.servers, session.server);
    final preferences = await SharedPreferences.getInstance();
    await _storage.write(key: _apiKeyStorageKey(session.id), value: trimmedKey);
    await _persistServers(preferences, servers);
    await preferences.setString(_activeServerIdKey, session.id);
    state = AsyncData(
      ServerConnectionState(servers: servers, activeSession: session),
    );
  }

  Future<void> switchServer(String serverId) async {
    final current = state.asData?.value;
    final server = _findById(current?.servers ?? const [], serverId);
    if (current == null || server == null) return;
    if (current.activeSession?.id == serverId) return;

    final apiKey = await _storage.read(key: _apiKeyStorageKey(serverId));
    if (apiKey == null || apiKey.isEmpty) {
      throw StateError('这台服务器没有已保存的 API Key，请删除后重新添加。');
    }
    final session = await _createSession(
      server.baseUrl,
      apiKey,
      name: server.name,
    );
    final servers = _replaceServer(current.servers, session.server);
    final preferences = await SharedPreferences.getInstance();
    await _persistServers(preferences, servers);
    await preferences.setString(_activeServerIdKey, serverId);
    state = AsyncData(
      ServerConnectionState(servers: servers, activeSession: session),
    );
  }

  Future<void> deleteServer(String serverId) async {
    final current = state.asData?.value;
    if (current == null) return;
    final servers = current.servers
        .where((server) => server.id != serverId)
        .toList(growable: false);
    final preferences = await SharedPreferences.getInstance();
    await _storage.delete(key: _apiKeyStorageKey(serverId));
    await _persistServers(preferences, servers);

    if (current.activeSession?.id != serverId) {
      state = AsyncData(
        ServerConnectionState(
          servers: servers,
          activeSession: current.activeSession,
        ),
      );
      return;
    }

    await preferences.remove(_activeServerIdKey);
    state = AsyncData(ServerConnectionState(servers: servers));
    if (servers.isNotEmpty) {
      await switchServer(servers.first.id);
    }
  }

  Future<ServerSession> _createSession(
    String baseUrl,
    String apiKey, {
    required String name,
  }) async {
    final info = await StashApiClient(
      baseUrl: baseUrl,
      apiKey: apiKey,
    ).getServerInfo();
    return ServerSession(
      server: SavedServer(
        id: serverIdForUrl(baseUrl),
        name: name,
        baseUrl: baseUrl,
        version: info.version,
        sceneCount: info.sceneCount,
        tagCount: info.tagCount,
      ),
      apiKey: apiKey,
    );
  }

  List<SavedServer> _readServers(SharedPreferences preferences) {
    final raw = preferences.getString(_serversKey);
    if (raw == null) return const [];
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .map((item) => SavedServer.fromJson(item as Map<String, dynamic>))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<List<SavedServer>> _migrateLegacyServer(
    SharedPreferences preferences,
  ) async {
    final legacyUrl = preferences.getString(_legacyServerUrlKey);
    final legacyApiKey = await _storage.read(key: _legacyApiKeyKey);
    if (legacyUrl == null || legacyApiKey == null || legacyApiKey.isEmpty) {
      return const [];
    }
    final normalized = normalizeServerUrl(legacyUrl);
    final server = SavedServer(
      id: serverIdForUrl(normalized),
      name: _defaultServerName(normalized),
      baseUrl: normalized,
      version: '',
      sceneCount: 0,
      tagCount: 0,
    );
    await _storage.write(
      key: _apiKeyStorageKey(server.id),
      value: legacyApiKey,
    );
    await _persistServers(preferences, [server]);
    await preferences.setString(_activeServerIdKey, server.id);
    await preferences.remove(_legacyServerUrlKey);
    await _storage.delete(key: _legacyApiKeyKey);
    return [server];
  }

  static SavedServer? _findById(List<SavedServer> servers, String? id) {
    for (final server in servers) {
      if (server.id == id) return server;
    }
    return null;
  }

  static List<SavedServer> _replaceServer(
    List<SavedServer> servers,
    SavedServer replacement,
  ) {
    final result = [...servers];
    final index = result.indexWhere((server) => server.id == replacement.id);
    if (index < 0) {
      result.add(replacement);
    } else {
      result[index] = replacement;
    }
    return List.unmodifiable(result);
  }

  static String _defaultServerName(String baseUrl) {
    final uri = Uri.tryParse(baseUrl);
    return uri?.authority.isNotEmpty == true ? uri!.authority : baseUrl;
  }

  static Future<void> _persistServers(
    SharedPreferences preferences,
    List<SavedServer> servers,
  ) async {
    await preferences.setString(
      _serversKey,
      jsonEncode(servers.map((server) => server.toJson()).toList()),
    );
  }
}
