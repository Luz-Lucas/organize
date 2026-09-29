import 'dart:async';

import 'package:intl/date_symbol_data_local.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await initializeDateFormatting('pt_BR');
  await testMain();
}
