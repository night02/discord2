import 'package:flutter_test/flutter_test.dart';
import 'package:veylor/update_service.dart';

void main() {
  Map<String,dynamic> windows()=> {
    'schema':1,
    'platform':'windows',
    'channel':'beta',
    'installation':'manual',
    'version':'0.3.1',
    'build':5,
    'notes':'Instalador de teste',
    'download_url':'https://github.com/Night0231-creator/discord2/actions/runs/38278251122',
  };

  test('Windows update accepts official GitHub Actions run',(){
    final info=WindowsUpdate.fromJson(windows());
    expect(info.version,'0.3.1');
    expect(info.isNewerThan(4),isTrue);
    expect(info.isNewerThan(5),isFalse);
    expect(info.isNewerThan(6),isFalse);
  });

  test('Windows update accepts official beta GitHub Release',(){
    final value=windows()..['download_url']='https://github.com/Night0231-creator/discord2/releases/tag/v0.3.1-beta';
    final info=WindowsUpdate.fromJson(value);
    expect(info.downloadUrl.path,'/Night0231-creator/discord2/releases/tag/v0.3.1-beta');
  });

  test('Windows update never executes untrusted download addresses',(){
    for(final uri in [
      'http://github.com/Night0231-creator/discord2/actions/runs/38278251122',
      'https://evil.example.com/installer.exe',
      'https://github.com.evil.com/Night0231-creator/discord2/releases/tag/v0.3.1-beta',
      'https://github.com/Night0231-creator/discord2/releases/download/v0.3.1-beta/installer.exe',
      'https://github.com/Night0231-creator/discord2/actions/runs/38278251122?url=https://evil.example',
      'https://attacker:pass@github.com/Night0231-creator/discord2/actions/runs/38278251122',
      'https://github.com:8443/Night0231-creator/discord2/actions/runs/38278251122',
      'https://github.com/Night0231-creator/discord2/releases/tag/random',
    ]) {
      final value=windows()..['download_url']=uri;
      expect(()=>WindowsUpdate.fromJson(value),throwsFormatException,reason:uri);
    }
  });

  test('Windows update refuses other platforms, old schema and auto-install',(){
    final android=windows()..['platform']='android';
    expect(()=>WindowsUpdate.fromJson(android),throwsFormatException);
    final auto=windows()..['installation']='automatic';
    expect(()=>WindowsUpdate.fromJson(auto),throwsFormatException);
    final invalid=windows()..['build']=-100;
    expect(()=>WindowsUpdate.fromJson(invalid),throwsFormatException);
  });
}
