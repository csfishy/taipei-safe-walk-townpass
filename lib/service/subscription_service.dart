import 'package:get/get.dart';
import 'package:town_pass/bean/subscription.dart';

class SubscriptionService extends GetxService {
  final RxList<SubscriptionItem> itemList = RxList();

  Future<SubscriptionService> init() async {
    return this;
  }

  void removeSubscription({required String title}) {
    itemList.removeWhere((item) => item.title == title);
  }
}
