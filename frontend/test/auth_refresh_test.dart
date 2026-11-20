import 'dart:convert';

import 'package:believers_palace/core/api_client.dart';
import 'package:believers_palace/core/auth_provider.dart';
import 'package:believers_palace/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('concurrent expired requests share one refresh and retry once',
      () async {
    SharedPreferences.setMockInitialValues({
      'token': 'expired',
      'refreshToken': 'refresh-one',
    });
    var refreshes = 0;
    var retries = 0;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/auth/refresh')) {
        refreshes++;
        expect(jsonDecode(request.body)['refreshToken'], 'refresh-one');
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return http.Response(
            jsonEncode({
              'accessToken': 'current',
              'refreshToken': 'refresh-two',
              'user': {
                'id': 'member',
                'name': 'Member',
                'email': 'member@example.test',
                'role': 'user',
                'createdAt': '2026-01-01T00:00:00Z',
              },
            }),
            200);
      }
      if (request.headers['Authorization'] != 'Bearer current') {
        return http.Response('{}', 401);
      }
      retries++;
      return http.Response('{"result":true}', 200);
    });
    final apiClient = ApiClient(client: client)..setToken('expired');
    final auth = AuthNotifier(ApiService(apiClient));
    addTearDown(auth.dispose);
    final results = await Future.wait([
      apiClient.getRaw('/first'),
      apiClient.getRaw('/second'),
      apiClient.getRaw('/third'),
    ]);
    expect(refreshes, 1);
    expect(retries, 3);
    expect(results, everyElement({'result': true}));
    expect((await SharedPreferences.getInstance()).getString('refreshToken'),
        'refresh-two');
  });
}
