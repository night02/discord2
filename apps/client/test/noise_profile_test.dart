import 'package:flutter_test/flutter_test.dart';
import 'package:veylor/noise_profile.dart';

void main() {
  test('AI mode is never presented as available on Windows or Linux', () {
    expect(NoiseCapability.supportsAi(
      isAndroid:false,isIos:false,isMacOs:false),isFalse);
  });

  test('Supported mobile and macOS devices may check processor capability', () {
    expect(NoiseCapability.supportsAi(
      isAndroid:true,isIos:false,isMacOs:false),isTrue);
    expect(NoiseCapability.supportsAi(
      isAndroid:false,isIos:true,isMacOs:false),isTrue);
    expect(NoiseCapability.supportsAi(
      isAndroid:false,isIos:false,isMacOs:true),isTrue);
  });

  test('WebRTC noise suppression is on by default and can be disabled', () {
    expect(NoiseCapability.useNativeSuppression(NoiseProfile.standard),isTrue);
    expect(NoiseCapability.useNativeSuppression(NoiseProfile.ai),isTrue);
    expect(NoiseCapability.useNativeSuppression(NoiseProfile.off),isFalse);
  });

  test('labels never confuse ordinary suppression with AI', () {
    expect(NoiseCapability.label(NoiseProfile.standard),'Padrão (WebRTC)');
    expect(NoiseCapability.label(NoiseProfile.ai),'IA (LiveKit)');
    expect(NoiseCapability.description(NoiseProfile.standard),contains('sem IA'));
  });
}
