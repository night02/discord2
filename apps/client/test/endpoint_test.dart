import 'package:flutter_test/flutter_test.dart';
import 'package:veylor/api_endpoint.dart';
void main() {
  test('HTTPS accepted and normalized', (){
    expect(validateApiEndpoint(' https://example.org/ '),'https://example.org');
    expect(validateApiEndpoint('https://example.org:8443'),'https://example.org:8443');
  });
  test('local HTTP accepted', (){
    expect(validateApiEndpoint('http://127.0.0.1:8080'),'http://127.0.0.1:8080');
  });
  test('remote HTTP and unsafe URLs rejected', (){
    expect(()=>validateApiEndpoint('http://192.168.1.7:8080'),throwsFormatException);
    expect(()=>validateApiEndpoint('https://user:pass@example.org'),throwsFormatException);
    expect(()=>validateApiEndpoint('https://example.org/path'),throwsFormatException);
    expect(()=>validateApiEndpoint('not-a-url'),throwsFormatException);
  });
  test('first install uses new Postgres server and never reuses an old unscoped token',(){
    final selection=selectStartupServer(null);
    expect(selection.address,'https://veylor-postgres-staging.onrender.com');
    expect(selection.clearOldSession,isTrue);
    expect(selection.movedFromLegacy,isFalse);
  });
  test('upgrade moves legacy Veylor address and clears incompatible login session',(){
    final selection=selectStartupServer('https://veylor-v02-api.onrender.com');
    expect(selection.address,'https://veylor-postgres-staging.onrender.com');
    expect(selection.clearOldSession,isTrue);
    expect(selection.movedFromLegacy,isTrue);
  });
  test('preserve user configured API address and token on upgrade',(){
    final selection=selectStartupServer('https://my-domain.example:8443');
    expect(selection.address,'https://my-domain.example:8443');
    expect(selection.clearOldSession,isFalse);
    expect(selection.movedFromLegacy,isFalse);
  });
  test('already configured Postgres address remains unchanged',(){
    final selection=selectStartupServer('https://veylor-postgres-staging.onrender.com');
    expect(selection.clearOldSession,isFalse);
  });
}
