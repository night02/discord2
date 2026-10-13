import 'package:flutter_test/flutter_test.dart';
import 'package:veylor/media/share_profile.dart';
void main(){
  test('bitrate is measured from deltas; reset counters have no invented rate',(){
    final meter=BitrateMeter();expect(meter.sample(1000,1000),isNull);expect(meter.sample(251000,2000),2000000);
    expect(meter.sample(0,3000),isNull);expect(meter.sample(1000,3000),isNull);meter.reset();expect(meter.sample(2000,4000),isNull);
  });
  test('capture and encoder profiles include limits and experimental flags',(){
    expect(ShareProfile.motion.fps,60);expect(ShareProfile.motion.bitrate,greaterThan(ShareProfile.balanced.bitrate));
    expect(ShareProfile.motion.experimental,isTrue);expect(ShareProfile.balanced.experimental,isFalse);expect(const StreamMetrics().hasVideo,isFalse);
  });
}
