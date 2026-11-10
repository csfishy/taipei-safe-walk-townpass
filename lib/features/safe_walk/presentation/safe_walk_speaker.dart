/// 朗讀介面：M3 只定義畫面需要的行為，實際語音（TTS 套件或 M5 音訊 Adapter）由 M1／M5 注入。
abstract class SafeWalkSpeaker {
  /// 是否真的會發出聲音；false 時畫面要寫明「只顯示文字」。
  bool get available;

  /// 開始朗讀；讀完呼叫 [onDone]。重複呼叫要先停止上一句。
  void speak(String text, {void Function()? onDone});
  void stop();
}

/// 預設：沒有配置語音，只顯示文字。
class UnavailableSpeaker implements SafeWalkSpeaker {
  const UnavailableSpeaker();
  @override
  bool get available => false;
  @override
  void speak(String text, {void Function()? onDone}) => onDone?.call();
  @override
  void stop() {}
}

/// 選配：能發出模擬來電鈴聲的 speaker。畫面只在 speaker 實作它時才響鈴，因此不影響既有 fake。
/// 鈴聲只是「模擬陪伴」的提示音，不是真實來電。
abstract interface class SafeWalkRinger {
  /// 開始響鈴；之後的 [stopRing]、背景、SOS 都必須使遲到的播放失效。
  void startRing();
  void stopRing();
}
