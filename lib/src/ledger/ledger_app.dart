import 'dart:typed_data';

import 'package:ledger_flutter/ledger_flutter.dart';

/// Applications on Ledger devices play a vital role in managing your crypto
/// assets – for each cryptocurrency, there’s a dedicated app.
/// These apps can be installed onto your hardware wallet by connecting it to
/// Ledger Live.
abstract class LedgerApp {
  final Ledger ledger;

  LedgerApp(this.ledger);

  Future<List<String>> getAccounts(LedgerDevice device);

  Future<Uint8List> signPersonalMessage(
    LedgerDevice device,
    Uint8List message,
  );

  Future<Uint8List> signTransaction(
    LedgerDevice device,
    Uint8List transaction,
  );

  Future<Uint8List> signEIP712Message(LedgerDevice device, String jsonMessage);

  Future<Uint8List> signEIP712HashedMessage(
      {required LedgerDevice device,
      required Uint8List domainSeparator,
      required Uint8List hashStructMessage});
}
