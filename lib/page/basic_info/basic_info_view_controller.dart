import 'package:town_pass/bean/account.dart';
import 'package:town_pass/service/account_service.dart';
import 'package:get/get.dart';

class BasicInfoViewController extends GetxController {
  final AccountService _accountService = Get.find<AccountService>();

  bool get hasAccount => _accountService.account != null;

  String get account => _accountService.account?.account ?? '';

  String get name => _accountService.account?.realName ?? '';

  final RxnString idNumber = RxnString();

  final RxnString birthday = RxnString();

  final RxnString email = RxnString();

  final RxnString phoneNumber = RxnString();

  final RxnString address = RxnString();

  @override
  void onInit() {
    super.onInit();
    syncAccount();
  }

  void syncAccount() {
    idNumber.value = _accountService.account?.idNumber;
    birthday.value = _accountService.account?.birthday;
    email.value = _accountService.account?.email;
    phoneNumber.value = _accountService.account?.phoneNumber;
    address.value = _accountService.account?.residentAddress;
  }

  void updateAccount({
    String? idNumber,
    String? birthday,
    String? email,
    String? phoneNumber,
    String? address,
  }) {
    final current = _accountService.account;
    if (current == null) return;
    _accountService.updateAccount(
      Account(
        id: current.id,
        account: current.account,
        username: current.username,
        realName: current.realName,
        idNumber: idNumber ?? current.idNumber,
        email: email ?? current.email,
        phoneNumber: phoneNumber ?? current.phoneNumber,
        birthday: birthday ?? current.birthday,
        memberType: current.memberType,
        verifyLevel: current.verifyLevel,
        addressList: current.addressList,
        residentAddress: address ?? current.residentAddress,
        citizen: current.citizen,
        nativePeople: current.nativePeople,
        cityInternetUid: current.cityInternetUid,
      ),
    );
    syncAccount();
  }
}
