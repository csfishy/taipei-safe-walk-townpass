
import 'package:carousel_slider/carousel_controller.dart';
import 'package:town_pass/bean/home_banner.dart';
import 'package:get/get.dart';

class NewsBannerWidgetController extends GetxController {
  final CarouselSliderController controller = CarouselSliderController();

  int _carouselIndex = 0;

  int get carouselIndex => _carouselIndex;

  set carouselIndex(int index) {
    _carouselIndex = index;
    update();
  }

  bool _isLoading = true;

  bool get isLoading => _isLoading;

  set isLoading(bool value) {
    _isLoading = value;
    update();
  }

  HomeBannerList? list;

  @override
  void onInit() {
    super.onInit();

    list = const HomeBannerList(data: []);
    isLoading = false;
  }
}
