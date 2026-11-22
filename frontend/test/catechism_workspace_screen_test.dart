import 'dart:convert';

import 'package:believers_palace/core/api_client.dart';
import 'package:believers_palace/core/auth_provider.dart';
import 'package:believers_palace/screens/login_screen.dart';
import 'package:believers_palace/services/api_service.dart';
import 'package:believers_palace/features/catechism/screens/catechism_workspace_screen.dart';
import 'package:believers_palace/features/catechism/services/catechism_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Response _json(Map<String, Object?> body, [int status = 200]) =>
    http.Response(jsonEncode(body), status);

Widget _app(Widget screen, MockClient client) => ProviderScope(
      overrides: [
        catechismApiProvider.overrideWithValue(
          CatechismApi(ApiClient(client: client)),
        ),
      ],
      child: MaterialApp(home: screen),
    );

void main() {
  testWidgets('teacher sign-in uses the dedicated endpoint and saves the mode',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final paths = <String>[];
    final client = MockClient((request) async {
      paths.add(request.url.path);
      expect(jsonDecode(request.body), {
        'email': 'teacher@example.test',
        'password': 'teacher-password',
      });
      return _json({
        'accessToken': 'access',
        'refreshToken': 'refresh',
        'user': {
          'id': 'teacher',
          'name': 'Teacher',
          'email': 'teacher@example.test',
          'role': 'user',
          'createdAt': '2026-01-01T00:00:00Z',
        },
      });
    });
    final scope = ProviderContainer(overrides: [
      authProvider.overrideWith(
          (ref) => AuthNotifier(ApiService(ApiClient(client: client)))),
    ]);
    addTearDown(scope.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: scope,
      child: const MaterialApp(home: LoginScreen()),
    ));
    await tester.enterText(
        find.byType(TextField).at(0), 'teacher@example.test');
    await tester.enterText(find.byType(TextField).at(1), 'teacher-password');
    final teacherMode = find.text('Catechism teacher sign-in');
    await tester.ensureVisible(teacherMode);
    await tester.tap(teacherMode);
    final login = find.text('Login');
    await tester.ensureVisible(login);
    await tester.tap(login);
    await tester.pumpAndSettle();
    expect(paths.single, endsWith('/auth/teacher-login'));
    expect(scope.read(authProvider).teacherMode, true);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('teacherMode'), true);
  });
  testWidgets('teacher assignments page through lookahead results',
      (tester) async {
    final pages = <String?>[];
    final client = MockClient((request) async {
      expect(request.url.path, endsWith('/catechism-teacher/classes'));
      final page = request.url.queryParameters['page'];
      pages.add(page);
      return _json({
        'classes': [
          for (var i = 0; i < (page == '1' ? 21 : 1); i++)
            {
              'id': '$page-$i',
              'name': 'Class $page-$i',
              'church': 'Parish',
              'substitute': page == '2',
            },
        ],
      });
    });

    await tester.pumpWidget(_app(const CatechismTeacherScreen(), client));
    await tester.pumpAndSettle();
    final next = find.text('Next');
    final list = find.byType(Scrollable);
    await tester.scrollUntilVisible(next, 450, scrollable: list);
    expect(find.text('Class 1-20'), findsNothing);
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(find.text('Class 2-0'), findsOneWidget);
    expect(find.textContaining('Substitute'), findsOneWidget);
    expect(pages, ['1', '2']);
  });

  testWidgets(
      'guardian history loads on demand and displays marks and attendance',
      (tester) async {
    final paths = <String>[];
    final client = MockClient((request) async {
      paths.add(request.url.path);
      if (request.url.path.endsWith('/students/student')) {
        return _json({
          'attendance': [
            {'lesson_date': '2026-11-22', 'status': 'present'},
          ],
          'marks': [
            {'assessment': 'Term exam', 'score': 8, 'maximum': 10},
          ],
        });
      }
      return _json({
        'canRegister': false,
        'canTeach': false,
        'students': [
          {'id': 'student', 'name': 'Student', 'canViewHistory': true},
        ],
        'teachers': [],
        'publications': [],
        'syllabus': {'kind': 'syllabus', 'title': 'Outline', 'body': 'Topics'},
      });
    });

    await tester.pumpWidget(
      _app(const CatechismWorkspaceScreen(classId: 'class'), client),
    );
    await tester.pumpAndSettle();
    expect(paths, hasLength(1));
    expect(find.text('Outline'), findsOneWidget);
    expect(find.text('Register student'), findsNothing);
    expect(find.text('Publish marks'), findsNothing);
    await tester.tap(find.text('Student'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View attendance and marks'));
    await tester.pumpAndSettle();
    expect(find.text('Term exam'), findsOneWidget);
    expect(find.text('8 / 10'), findsOneWidget);
    expect(find.text('present'), findsOneWidget);
    expect(paths.last, endsWith('/workspace/students/student'));
  });

  testWidgets('announcement retries reuse the same publication request ID',
      (tester) async {
    final ids = <String>[];
    final client = MockClient((request) async {
      if (request.method == 'POST') {
        expect(request.url.path, endsWith('/workspace/announcement'));
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['title'], 'Class news');
        ids.add(body['requestId'] as String);
        return ids.length == 1
            ? _json({'message': 'Try again'}, 503)
            : _json({'saved': true});
      }
      return _json({
        'canRegister': false,
        'canTeach': true,
        'students': [],
        'teachers': [],
        'publications': [],
        'syllabus': null,
      });
    });

    await tester.pumpWidget(
      _app(const CatechismWorkspaceScreen(classId: 'class'), client),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Post announcement'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'Class news');
    await tester.enterText(find.byType(TextField).at(1), 'Update');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Try again'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(ids, hasLength(2));
    expect(ids.last, ids.first);
    expect(ids.first, matches(RegExp(r'^[a-f0-9]{32}$')));
    expect(find.text('Saved'), findsOneWidget);
  });

  testWidgets('admin forms submit registration and substitute assignment data',
      (tester) async {
    final writes = <(String, Map<String, dynamic>)>[];
    final client = MockClient((request) async {
      if (request.method == 'POST') {
        writes.add((
          request.url.path,
          jsonDecode(request.body) as Map<String, dynamic>
        ));
        return _json({'saved': true});
      }
      return _json({
        'canRegister': true,
        'canTeach': false,
        'students': [],
        'teachers': [],
        'publications': [],
        'syllabus': null,
      });
    });

    await tester.pumpWidget(
      _app(const CatechismWorkspaceScreen(classId: 'class'), client),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Register teacher'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byType(TextField).at(0), 'teacher@example.test');
    await tester.tap(find.text('Substitute teacher'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Register student'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'Student');
    await tester.tap(find.byType(TextField).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byType(TextField).at(2), 'guardian@example.test');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(writes, hasLength(2));
    expect(writes[0].$1, endsWith('/workspace/teachers'));
    expect(writes[0].$2['substitute'], true);
    expect(writes[0].$2['email'], 'teacher@example.test');
    expect(writes[1].$1, endsWith('/workspace/students'));
    expect(writes[1].$2['studentName'], 'Student');
    expect(writes[1].$2['email'], 'guardian@example.test');
    expect(writes[1].$2['dateOfBirth'], endsWith('T00:00:00Z'));
  });
}
