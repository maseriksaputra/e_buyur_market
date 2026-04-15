// lib/app/core/network/api_client.dart
import 'package:dio/dio.dart';
import 'package:provider/provider.dart';
import '../../presentation/providers/auth_provider.dart';

class ApiClient {
  final Dio dio;
  ApiClient._(this.dio);

  factory ApiClient.of(context) {
    final auth = context.read<AuthProvider>();

    final base = const String.fromEnvironment(
      'API_BASE', defaultValue: 'https://api.ebuyurmarket.com',
    ).replaceAll(RegExp(r'/+$'), '');

    final dio = Dio(BaseOptions(baseUrl: '$base/'));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (opt, handler) {
        // hindari double slash
        opt.path = opt.path.replaceFirst(RegExp(r'^/+'), '');
        // set header Authorization dari AuthProvider
        final t = auth.token;
        if (t != null && t.isNotEmpty) {
          opt.headers['Authorization'] = 'Bearer $t';
        } else {
          opt.headers.remove('Authorization');
        }
        opt.headers['Accept'] = 'application/json';
        handler.next(opt);
      },
    ));
    return ApiClient._(dio);
  }
}
