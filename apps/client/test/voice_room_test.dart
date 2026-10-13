import 'package:flutter_test/flutter_test.dart';
import 'package:veylor/voice_room.dart';

void main() {
  test('accepts only HTTPS-upgraded WSS server credentials from API', () {
    final access=MediaAccess.fromJson({
      'url':'wss://example.livekit.cloud',
      'token':'x' * 128,
    });
    expect(access.url,'wss://example.livekit.cloud');
    expect(access.token.length,128);
  });

  test('rejects insecure, injected or incomplete LiveKit connection URLs', () {
    for(final raw in [
      'ws://example.livekit.cloud',
      'http://example.livekit.cloud',
      'wss://username:secret@example.livekit.cloud',
      'wss://example.livekit.cloud/#fragment',
      'wss://example.livekit.cloud/other-path',
      'wss://example.livekit.cloud:444',
      'wss:///invalid',
      'not a URL',
    ]) {
      expect(() => MediaAccess.fromJson({'url':raw,'token':'x'*128}),
        throwsFormatException,reason:raw);
    }
    expect(() => MediaAccess.fromJson({
      'url':'wss://example.livekit.cloud','token':'short',
    }),throwsFormatException);
  });

  test('room session credentials are not retained in a URL', () {
    final token='a' * 160;
    final access=MediaAccess.fromJson({'url':'wss://video.example.com','token':token});
    expect(access.url.contains(token),isFalse);
    expect(access.url,'wss://video.example.com');
  });
}
