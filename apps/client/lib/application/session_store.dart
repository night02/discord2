import 'package:flutter_secure_storage/flutter_secure_storage.dart';
abstract class SessionStore {
  Future<String?> readAddress();
  Future<String?> readToken();
  Future<void> save(String address,String token);
  Future<void> clear();
  Future<void> saveAddress(String address);
}
class SecureSessionStore implements SessionStore {
  SecureSessionStore({FlutterSecureStorage? storage}):_storage=storage??const FlutterSecureStorage();
  final FlutterSecureStorage _storage;
  Future<void> _queue=Future<void>.value();
  Future<void> _write(Future<void> Function() operation) {
    final next=_queue.then((_)=>operation());
    _queue=next.catchError((Object _){});
    return next.timeout(const Duration(seconds:8));
  }
  @override Future<String?> readAddress() async {
    await _queue.timeout(const Duration(seconds:8));
    return _storage.read(key:'veylor_api_url').timeout(const Duration(seconds:6));
  }
  @override Future<String?> readToken() async {
    await _queue.timeout(const Duration(seconds:8));
    return _storage.read(key:'veylor_session').timeout(const Duration(seconds:6));
  }
  @override Future<void> save(String address,String token)=>_write(() async {
    await _storage.write(key:'veylor_api_url',value:address);
    await _storage.write(key:'veylor_session',value:token);
  });
  @override Future<void> clear()=>_write(()=>_storage.delete(key:'veylor_session'));
  @override Future<void> saveAddress(String address)=>_write(()=>_storage.write(key:'veylor_api_url',value:address));
}
