import 'package:town_pass/bean/message.dart';
import 'package:get/get.dart';

class MessageViewController extends GetxController {
  List<MessageType> get tabTypeList => [
        MessageType.personal,
        MessageType.tcg,
        MessageType.system,
      ];

  final Rxn<MessageList> list = Rxn();

  bool _isLoading = true;

  bool get isLoading => _isLoading;

  List<MessageItem> messageList({required MessageType type}) {
    return list.value?.data.where((message) => message.type == type).toList() ?? [];
  }

  int unreadCount({required MessageType type}) {
    return list.value?.data
            .where(
              (message) => message.type == type && !message.hasRead,
            )
            .length ??
        0;
  }

  @override
  void onInit() {
    super.onInit();
    fetch();
  }

  Future<void> fetch() async {
    _isLoading = true;
    update();

    list.value = const MessageList(data: []);

    _isLoading = false;
    update();
  }
}
