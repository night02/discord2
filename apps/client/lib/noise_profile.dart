/// Audio effects applied to the microphone before LiveKit publishes it.
///
/// AI processing is supported through the official LiveKit Flutter noise
/// filter only on Android, iOS and macOS. On Windows/Linux use WebRTC's native
/// suppression. The earlier website's RNNoise AudioWorklet cannot be reused
/// as a Flutter native microphone track processor.
enum NoiseProfile { off, standard, ai }

class NoiseCapability {
  const NoiseCapability._();

  static bool supportsAi({required bool isAndroid, required bool isIos,
    required bool isMacOs}) => isAndroid || isIos || isMacOs;

  static bool useNativeSuppression(NoiseProfile profile) =>
      profile != NoiseProfile.off;

  static String label(NoiseProfile profile) => switch (profile) {
    NoiseProfile.off => 'Desligada',
    NoiseProfile.standard => 'Padrão (WebRTC)',
    NoiseProfile.ai => 'IA (LiveKit)',
  };

  static String description(NoiseProfile profile) => switch (profile) {
    NoiseProfile.off => 'Sem supressão; cancelamento de eco mantido',
    NoiseProfile.standard => 'Redução de ruído WebRTC, sem IA',
    NoiseProfile.ai => 'Filtro de IA local, quando suportado pelo aparelho',
  };
}
