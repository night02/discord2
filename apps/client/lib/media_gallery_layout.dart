/// Responsive layout policy for the Veylor LiveKit voice/video room.
///
/// A screen share gets a dedicated stage. Its participant grid remains visible
/// below it, even on portrait phones; fullscreen video never hides microphone
/// or disconnect actions.
class MediaGalleryLayout {
  const MediaGalleryLayout._();

  static int columnsForWidth(double width, {required bool watchingScreen}) {
    if (watchingScreen) {
      if (width >= 1000) return 4;
      if (width >= 550) return 3;
      return 2;
    }
    if (width >= 920) return 3;
    if (width >= 550) return 2;
    return 1;
  }

  static int stageFlexForWidth(double width) => width >= 920 ? 7 : 6;
}
