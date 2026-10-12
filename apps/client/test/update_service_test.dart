import 'package:flutter_test/flutter_test.dart';
import 'package:veylor/update_service.dart';

void main(){
  Map<String,dynamic> valid()=>{
    'schema':1,'platform':'android','channel':'beta',
    'version':'0.2.0','build':2,'notes':'Teste','installation':'manual',
    'download_url':'https://github.com/Night0231-creator/discord2/actions/runs/38262623141'
  };
  test('parse valid update and compare build numbers',(){
    final data=AndroidUpdate.fromJson(valid());
    expect(data.isNewerThan(1),isTrue);
    expect(data.isNewerThan(2),isFalse);
    expect(data.isNewerThan(3),isFalse);
  });
  test('block injected download links and unsupported schemes',(){
    final fake=valid()..['download_url']='https://example.org/app.apk';
    expect(()=>AndroidUpdate.fromJson(fake),throwsFormatException);
    final http=valid()..['download_url']='http://github.com/Night0231-creator/discord2/actions/runs/38262623141';
    expect(()=>AndroidUpdate.fromJson(http),throwsFormatException);
    final query=valid()..['download_url']='https://github.com/Night0231-creator/discord2/actions/runs/38262623141?token=123';
    expect(()=>AndroidUpdate.fromJson(query),throwsFormatException);
  });
  test('official GitHub beta release page is a valid Android update location',(){
    final release=valid()..['download_url']='https://github.com/Night0231-creator/discord2/releases/tag/v0.3.2-beta';
    expect(AndroidUpdate.fromJson(release).downloadUrl.host,'github.com');
  });
  test('Android rejects automatic installs and links on nonstandard HTTPS ports',(){
    final automatic=valid()..['installation']='automatic';
    expect(()=>AndroidUpdate.fromJson(automatic),throwsFormatException);
    final port=valid()..['download_url']='https://github.com:8443/Night0231-creator/discord2/actions/runs/38262623141';
    expect(()=>AndroidUpdate.fromJson(port),throwsFormatException);
  });
    test('reject non-android and incorrect version numbers',(){
    final ios=valid()..['platform']='ios';
    expect(()=>AndroidUpdate.fromJson(ios),throwsFormatException);
    final build=valid()..['build']=-1;
    expect(()=>AndroidUpdate.fromJson(build),throwsFormatException);
  });
}
