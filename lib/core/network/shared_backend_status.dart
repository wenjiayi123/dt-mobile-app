import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dio_provider.dart';

/// Share only an in-flight status read. Later refreshes still query the server,
/// including identity and audit evidence, rather than reusing an old success.
class SharedBackendStatusRepository {
  SharedBackendStatusRepository(this._dio);

  final Dio _dio;
  Future<Map<String, dynamic>>? _pending;

  Future<Map<String, dynamic>> loadStatus() =>
      _pending ??= _loadStatus().whenComplete(() => _pending = null);

  Future<Map<String, dynamic>> _loadStatus() async {
    final response = await _dio.get<Object>('/api/mobile/status');
    final raw = response.data;
    if (raw is! Map) {
      throw const FormatException('共享后端状态不是 JSON 对象');
    }
    return raw.map((key, value) => MapEntry(key.toString(), value));
  }
}

final sharedBackendStatusRepositoryProvider =
    Provider<SharedBackendStatusRepository>(
      (ref) => SharedBackendStatusRepository(ref.read(dioProvider)),
    );
