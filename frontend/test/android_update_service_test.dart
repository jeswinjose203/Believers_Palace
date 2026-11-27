import 'package:believers_palace/services/android_update_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('build number and APK come from the pinned stable release', () {
    final release = AndroidRelease.fromJson({
      'tag_name': 'v1.2.3+45',
      'assets': [
        {
          'name': 'believers-palace.apk',
          'size': 1024,
          'state': 'uploaded',
          'browser_download_url': 'https://untrusted.example/app.apk',
        }
      ],
    });

    expect(release?.build, 45);
    expect(release?.version, '1.2.3');
    expect(release?.size, 1024);
    expect(release?.apk.host, 'github.com');
    expect(release?.apk.path, endsWith('/v1.2.3+45/believers-palace.apk'));
  });

  test('missing, incomplete and malformed releases are ignored', () {
    for (final payload in [
      null,
      {'tag_name': 'v1.2.3+45', 'assets': []},
      {
        'tag_name': 'v1.2.3+45',
        'assets': [
          {'name': 'believers-palace.apk', 'state': 'new', 'size': 0}
        ],
      },
      {
        'tag_name': 'v1.2.3/other+46',
        'assets': [
          {'name': 'believers-palace.apk', 'state': 'uploaded', 'size': 42}
        ],
      },
    ]) {
      expect(AndroidRelease.fromJson(payload), isNull);
    }
  });
}
