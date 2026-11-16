import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:resit/features/settings/data/account_service.dart';

final accountServiceProvider = Provider<AccountService>((ref) => AccountService(ref));
