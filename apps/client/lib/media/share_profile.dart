enum ShareProfile {
  economy('720p · 30 FPS',1280,720,30,2500000,false),
  balanced('1080p · 30 FPS',1920,1080,30,5000000,false),
  motion('1080p · 60 FPS',1920,1080,60,8000000,true),
  high('1440p · 30 FPS',2560,1440,30,9000000,true);
  const ShareProfile(this.label,this.width,this.height,this.fps,this.bitrate,this.experimental);
  final String label;
  final int width,height,fps,bitrate;
  final bool experimental;
}
class StreamMetrics {
  const StreamMetrics({this.width,this.height,this.fps,this.bitsPerSecond,this.roundTripMs,this.limitation,this.codec});
  final num? width,height,fps,bitsPerSecond,roundTripMs;
  final String? limitation,codec;
  bool get hasVideo=>width!=null && height!=null && fps!=null;
}
class BitrateMeter {
  num? _bytes;int? _at;
  num? sample(num? bytes,int milliseconds){
    final previous=_bytes,at=_at;_bytes=bytes;_at=milliseconds;
    if(bytes==null || previous==null || at==null || milliseconds<=at || bytes<previous)return null;
    return (bytes-previous)*8000/(milliseconds-at);
  }
  void reset(){_bytes=null;_at=null;}
}
