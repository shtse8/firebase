import 'dart:async';

import 'firestore_sdk_interface.dart';

class FirestoreODM {
  final FirestoreSDK sdk;

  const FirestoreODM(this.sdk);

  Future<T> runTransaction<T>(FutureOr<T> Function() cb) async {
    final handlers = <FutureOr<void> Function()>[];
    void onSuccess(void Function() cb) {
      handlers.add(cb);
    }

    final result = await sdk.runTransaction((transaction) async {
      return await runZoned(
        cb,
        zoneValues: {
          #transaction: transaction,
          #onSuccess: onSuccess,
        },
      );
    });

    for (final handler in handlers) {
      await handler();
    }

    return result;
  }

  static Transaction? get currentTransaction =>
      Zone.current[#transaction] as Transaction?;

  static void onCurrentTransactionSuccess(void Function() callback) {
    final onSuccess =
        Zone.current[#onSuccess] as void Function(void Function())?;
    onSuccess?.call(callback);
  }
}
