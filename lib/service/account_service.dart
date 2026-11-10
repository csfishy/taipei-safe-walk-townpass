import 'package:town_pass/bean/account.dart';
import 'package:get/get.dart';

class AccountService extends GetxService {
  Account? _account;

  Account? get account => _account;

  Future<AccountService> init() async {
    // No authenticated account backend is configured.
    return this;
  }

  void updateAccount(Account account) {
    _account = account;
  }
}
