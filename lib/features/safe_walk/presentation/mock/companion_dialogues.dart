// 女性台詞只顯示在螢幕上供使用者照讀，不會使用麥克風或語音辨識。

/// 來電顯示名稱。
const callerName = '男友';

/// 男性 TTS 每說完一句後，使用者照著螢幕說出的唯一繁中台詞。
/// 最後一句男性台詞播放後直接結束劇本，因此只需要 steps.length - 1 組。
const Map<String, List<List<String>>> companionReplies = {
  'stalker-deterrence': [
    ['我快到了，但我後面好像有人一直跟著我。'],
    ['好，我看到你了，我現在直接走過去。電話先不要掛。'],
  ],
};

/// 單一嚇阻劇本不開放自由延伸，避免英文聲線朗讀任意繁中內容。
const List<String> callTemplates = [];
const Map<String, String> callTemplateAcks = {};
