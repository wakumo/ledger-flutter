import 'dart:async';
import 'dart:convert';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ledger_ethereum/ledger_ethereum.dart';
import 'package:ledger_example/bloc/ledger_event.dart';
import 'package:ledger_example/bloc/ledger_state.dart';
import 'package:ledger_example/channel/ledger_channel.dart';
import 'package:web3dart/crypto.dart';
import 'package:web3dart/web3dart.dart';

class LedgerBleBloc extends Bloc<LedgerBleEvent, LedgerBleState> {
  final LedgerChannel channel;
  StreamSubscription? _scanSubscription;

  LedgerBleBloc({
    required this.channel,
  }) : super(
          const LedgerBleState(
            devices: [],
            accounts: [],
          ),
        ) {
    on<LedgerBleScanStarted>(_onScanStarted, transformer: restartable());
    on<LedgerBleUsbStarted>(_onUsbStarted);
    on<LedgerBleConnectRequested>(_onConnectStarted);
    on<LedgerBleSignPersonalMessageRequested>(_onSignPersonalMessageRequested);
    on<LedgerBleDisconnectRequested>(_onDisconnectStarted);
  }

  Future<void> _onScanStarted(LedgerBleScanStarted event, Emitter emit) async {
    emit(state.copyWith(
      status: () => LedgerBleStatus.scanning,
    ));

    await emit.forEach(
      channel.ledger.scan(),
      onData: (data) {
        return state.copyWith(
          status: () => LedgerBleStatus.scanning,
          devices: () => [...state.devices, data],
        );
      },
    );
  }

  Future<void> _onUsbStarted(LedgerBleUsbStarted event, Emitter emit) async {
    final devices = await channel.ledger.listUsbDevices();
    final currentState = state;

    emit(currentState.copyWith(
      status: () => LedgerBleStatus.scanning,
      devices: () => [...state.devices, ...devices],
    ));
  }

  Future<void> _onConnectStarted(
    LedgerBleConnectRequested event,
    Emitter emit,
  ) async {
    final device = event.device;
    await channel.ledger.stopScanning();
    await channel.ledger.connect(device);

    final accounts = <String>[];

    try {
      final ethereumApp = EthereumAppLedger(channel.ledger);

      final publicKeys = await ethereumApp.getAccounts(device);
      final publicKey = publicKeys.firstOrNull;
      if (publicKey != null) {
        final address = EthereumAddress(publicKeyToAddress(
                decompressPublicKey(hexToBytes(publicKey)).sublist(1)))
            .hexEip55;
        accounts.add(address);
      }

      emit(state.copyWith(
        status: () => LedgerBleStatus.connected,
        selectedDevice: () => device,
        accounts: () => accounts,
      ));
    } catch (ex) {
      await channel.ledger.disconnect(device);

      emit(state.copyWith(
        status: () => LedgerBleStatus.failure,
        selectedDevice: () => device,
        accounts: () => accounts,
        error: () => ex,
      ));
    }
  }

  Future<void> _onSignPersonalMessageRequested(
    LedgerBleSignPersonalMessageRequested event,
    Emitter emit,
  ) async {
    final device = event.device;

    try {
      final ethereumApp = EthereumAppLedger(channel.ledger);

      const message = 'This is message';
      final signature = await ethereumApp.signPersonalMessage(
          device, Uint8List.fromList(utf8.encode(message)));
      final signatureInHex = bytesToHex(signature);
      print(signatureInHex);

      emit(state.copyWith(
        signature: () => signatureInHex,
      ));
    } catch (ex) {
      if (kDebugMode) {
        print(ex);
      }
    }
  }

  Future<void> _onDisconnectStarted(
    LedgerBleDisconnectRequested event,
    Emitter emit,
  ) async {
    final device = event.device;
    await channel.ledger.disconnect(device);

    emit(state.copyWith(
      status: () => LedgerBleStatus.idle,
      devices: () => [],
      selectedDevice: () => null,
      accounts: () => [],
      signature: () => null,
    ));
  }

  @override
  Future<void> close() async {
    _scanSubscription?.cancel();
    final device = state.device;
    if (device != null) {
      await channel.ledger.dispose(
        onError: (error) {},
      );
    }

    return super.close();
  }
}
