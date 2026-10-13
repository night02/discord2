import 'package:flutter_test/flutter_test.dart';
import 'package:veylor/media_gallery_layout.dart';

void main() {
  test('desktop and mobile galleries keep usable thumbnail counts', () {
    expect(MediaGalleryLayout.columnsForWidth(390,watchingScreen:false),1);
    expect(MediaGalleryLayout.columnsForWidth(390,watchingScreen:true),2);
    expect(MediaGalleryLayout.columnsForWidth(550,watchingScreen:false),2);
    expect(MediaGalleryLayout.columnsForWidth(550,watchingScreen:true),3);
    expect(MediaGalleryLayout.columnsForWidth(920,watchingScreen:false),3);
    expect(MediaGalleryLayout.columnsForWidth(1000,watchingScreen:true),4);
  });

  test('shared screen receives most of the available vertical space', () {
    expect(MediaGalleryLayout.stageFlexForWidth(390),6);
    expect(MediaGalleryLayout.stageFlexForWidth(1280),7);
  });
}
