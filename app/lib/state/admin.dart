import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/admin.dart';
import '../models/menu.dart';
import 'session.dart';

// Owner screens read fresh data each time they open and after every change (invalidate).
final adminCategoriesProvider = FutureProvider.autoDispose<List<Category>>(
  (ref) => ref.watch(adminRepositoryProvider).categories(),
);

final adminDishesProvider = FutureProvider.autoDispose<List<Dish>>(
  (ref) => ref.watch(adminRepositoryProvider).dishes(),
);

final adminTablesProvider = FutureProvider.autoDispose<List<ManagedTable>>(
  (ref) => ref.watch(adminRepositoryProvider).tables(),
);

final staffUsersProvider = FutureProvider.autoDispose<List<StaffUser>>(
  (ref) => ref.watch(adminRepositoryProvider).users(),
);

/// Keyed by business day `YYYY-MM-DD`.
final dailyReportProvider = FutureProvider.autoDispose.family<DailyReport, String>(
  (ref, date) => ref.watch(adminRepositoryProvider).dailyReport(date),
);

final paymentsReportProvider = FutureProvider.autoDispose.family<List<PaymentRecord>, String>(
  (ref, date) => ref.watch(adminRepositoryProvider).payments(date),
);

final backupStatusProvider = FutureProvider.autoDispose<BackupStatus>(
  (ref) => ref.watch(adminRepositoryProvider).backupStatus(),
);

/// Keyed by `(from, to)` business days, `YYYY-MM-DD`.
final salesSummaryProvider = FutureProvider.autoDispose.family<SalesSummary, ({String from, String to})>(
  (ref, range) => ref.watch(adminRepositoryProvider).summary(range.from, range.to),
);
