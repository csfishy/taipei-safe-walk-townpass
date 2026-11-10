
import 'package:town_pass/bean/activity.dart';
import 'package:get/get.dart';

class ActivityBannerWidgetController extends GetxController {
  bool _isLoading = false;

  bool get isLoading => _isLoading;

  set isLoading(bool value) {
    _isLoading = value;
    update();
  }

  ActivityList? list;

  @override
  void onInit() {
    super.onInit();

    _isLoading = true;

    list = const ActivityList(data: []);
    isLoading = false;
  }
}
