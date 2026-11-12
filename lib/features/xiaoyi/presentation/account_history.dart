import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dt_mobile_app/core/network/dio_provider.dart';

class AccountHistoryPage extends ConsumerWidget {
  const AccountHistoryPage({super.key, required this.baseUrl});
  final String baseUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final token = ref.watch(authTokenProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('账号历史与工单 / My activity')),
      body: token == null || token.trim().isEmpty
          ? Center(child: TextButton(
              onPressed: () => Navigator.of(context).pushNamed('/auth'),
              child: const Text('登录 / Sign in'),
            ))
          : _Activity(key: ObjectKey(token), baseUrl: baseUrl, token: token),
    );
  }
}

class _Activity extends StatefulWidget {
  const _Activity({super.key, required this.baseUrl, required this.token});
  final String baseUrl;
  final String token;
  @override
  State<_Activity> createState() => _ActivityState();
}

class _ActivityState extends State<_Activity> {
  late final Dio _dio;
  late Future<List<List<Map<String, dynamic>>>> _catalog;
  String? _selection;
  Future<List<Widget>>? _detail;

  @override
  void initState() {
    super.initState();
    _dio = Dio(BaseOptions(baseUrl: widget.baseUrl,
        headers: {'Authorization': 'Bearer ${widget.token}'},
        connectTimeout: const Duration(seconds: 8), receiveTimeout: const Duration(seconds: 15)));
    _catalog = _load();
  }

  @override
  void dispose() {
    _dio.close(force: true);
    super.dispose();
  }

  List<Map<String, dynamic>> _rows(dynamic data) =>
      (data['items'] as List).map((v) => Map<String, dynamic>.from(v as Map)).toList();
  Future<List<List<Map<String, dynamic>>>> _load() async {
    final replies = await Future.wait([
      _dio.get<dynamic>('/api/conversations', queryParameters: {'limit': 30}),
      _dio.get<dynamic>('/api/harness/joint/missions', queryParameters: {'mine': true}),
    ]);
    return replies.map((r) => _rows(r.data)).toList();
  }

  Future<List<Widget>> _conversation(String id) async {
    final reply = await _dio.get<dynamic>('/api/conversations/${Uri.encodeComponent(id)}',
        queryParameters: {'scope': 'mine', 'limit': 200});
    return [for (final turn in _rows(reply.data).reversed)
      ListTile(title: Text(turn['question'].toString()),
        subtitle: Text((turn['response'] as Map)['answer']?.toString() ?? '—'))];
  }

  Future<List<Widget>> _workOrder(String id) async {
    final reply = await _dio.get<dynamic>('/api/harness/joint/missions/${Uri.encodeComponent(id)}');
    final data = Map<String,dynamic>.from(reply.data as Map);
    if (data['id'] != id) throw StateError('工单编号不匹配');
    final approvals = data['business_approvals'] as List? ?? const [];
    return [
      ListTile(title: Text(data['config']['goal'].toString()),
          subtitle: Text('${data['id']} · ${data['status']}')),
      for(final note in approvals)
        if(note is Map) ListTile(title: Text('${note['slot']} · ${note['actor_id']}'),
            subtitle: Text(note['opinion']?.toString() ?? '—')),
    ];
  }

  void _open(String id, {required bool isChat}) => setState(() {
    _selection = id;
    _detail = isChat ? _conversation(id) : _workOrder(id);
  });

  Widget _error(Object? e) {
    final code = e is DioException ? e.response?.statusCode : null;
    return Text(code==401||code==403 ? '需要有效凭证 / Sign in again'
        : '读取失败 / Could not load${code==null?'':' (HTTP $code)'}');
  }

  @override
  Widget build(BuildContext context) {
    if (_selection != null) {
      return ListView(padding: const EdgeInsets.all(12), children: [
        OutlinedButton(onPressed: () => setState(() { _selection=null; _detail=null; }),
            child: const Text('返回账号列表 / Back to activity')),
        FutureBuilder<List<Widget>>(future:_detail, builder:(context,snapshot) {
          if(snapshot.connectionState!=ConnectionState.done) return const LinearProgressIndicator();
          if(snapshot.hasError)return _error(snapshot.error);
          return Column(children: snapshot.data ?? []);
        }),
      ]);
    }
    return FutureBuilder<List<List<Map<String,dynamic>>>>(future:_catalog,builder:(context,s) {
      if(s.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator());
      final groups=s.data ?? [<Map<String,dynamic>>[],<Map<String,dynamic>>[]];
      return ListView(padding:const EdgeInsets.all(12),children:[
        OutlinedButton(onPressed:()=>setState(()=>_catalog=_load()),child:const Text('刷新历史 / Refresh activity')),
        if(s.hasError)_error(s.error)
        else ...[
          const Text('我的对话 / Conversations'),
          if(groups[0].isEmpty)const Text('暂无对话 / No conversations'),
          for(final row in groups[0])ListTile(title:Text(row['title'].toString()),
              subtitle:Text('${row['session_id']} · ${row['turns']}'),onTap:()=>_open(row['session_id'].toString(),isChat:true)),
          const Text('我的工单 / Work orders'),
          if(groups[1].isEmpty)const Text('暂无工单 / No work orders'),
          for(final row in groups[1])ListTile(title:Text(row['config']['goal'].toString()),
              subtitle:Text('${row['id']} · ${row['status']}'),onTap:()=>_open(row['id'].toString(),isChat:false)),
        ],
      ]);
    });
  }
}
