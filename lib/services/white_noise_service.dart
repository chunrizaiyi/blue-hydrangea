enum WhiteNoiseKind {
  rain(
    label: '雨声',
    layers: [WhiteNoiseLayer('audio/gentle_rain_50m.ogg')],
    sourceTitle: 'Light rain loop',
    sourceId: 'Mixkit SFX 1253',
  ),
  ocean(
    label: '海浪',
    layers: [WhiteNoiseLayer('audio/gentle_ocean_50m.ogg')],
    sourceTitle: 'Sea waves loop',
    sourceId: 'Mixkit SFX 1196',
  ),
  breeze(
    label: '微风',
    layers: [WhiteNoiseLayer('audio/gentle_breeze_50m.ogg')],
    sourceTitle: 'Wind blowing ambience',
    sourceId: 'Mixkit SFX 2658',
  ),
  rainyNight(
    label: '雨夜',
    layers: [
      WhiteNoiseLayer('audio/gentle_rain_50m.ogg', gain: .78),
      WhiteNoiseLayer('audio/gentle_breeze_50m.ogg', gain: .22),
    ],
    sourceTitle: 'Light rain with a soft night breeze',
    sourceId: 'Mixkit SFX 1253 + 2658',
  ),
  coastalBreeze(
    label: '海风',
    layers: [
      WhiteNoiseLayer('audio/gentle_ocean_50m.ogg', gain: .8),
      WhiteNoiseLayer('audio/gentle_breeze_50m.ogg', gain: .2),
    ],
    sourceTitle: 'Sea waves with a gentle coastal breeze',
    sourceId: 'Mixkit SFX 1196 + 2658',
  ),
  gardenDream(
    label: '花园轻梦',
    layers: [
      WhiteNoiseLayer('audio/gentle_breeze_50m.ogg', gain: .5),
      WhiteNoiseLayer('audio/gentle_rain_50m.ogg', gain: .34),
      WhiteNoiseLayer('audio/gentle_ocean_50m.ogg', gain: .16),
    ],
    sourceTitle: 'Breeze, distant rain and soft water',
    sourceId: 'Mixkit SFX 2658 + 1253 + 1196',
  );

  const WhiteNoiseKind({
    required this.label,
    required this.layers,
    required this.sourceTitle,
    required this.sourceId,
  });

  final String label;
  final List<WhiteNoiseLayer> layers;
  final String sourceTitle;
  final String sourceId;
}

class WhiteNoiseLayer {
  const WhiteNoiseLayer(this.assetPath, {this.gain = 1});

  final String assetPath;
  final double gain;
}

const whiteNoiseLicense = 'Mixkit Sound Effects Free License';
