import 'dart:async';

import 'package:ledger_flutter/ledger.dart';

class LedgerBleConnectionManager extends BleConnectionManager {
  /// Ledger Nano X service id
  static const serviceId = '13D63400-2C97-0004-0000-4C6564676572';
  static const writeCharacteristicKey = '13D63400-2C97-0004-0002-4C6564676572';
  static const notifyCharacteristicKey = '13D63400-2C97-0004-0001-4C6564676572';

  final bleManager = FlutterReactiveBle();
  final LedgerOptions _options;
  final PermissionRequestCallback? onPermissionRequest;
  final _scannedIds = <String>{};
  final _connectedDevices = <String, GattGateway>{};

  bool _isScanning = false;
  StreamSubscription? _scanSubscription;
  StreamController<LedgerDevice> streamController =
      StreamController.broadcast();

  LedgerBleConnectionManager({
    required LedgerOptions options,
    this.onPermissionRequest,
  }) : _options = options;

  @override
  Stream<LedgerDevice> scan({LedgerOptions? options}) async* {
    // Check for permissions
    final granted = (await onPermissionRequest?.call(status)) ?? true;
    if (!granted) {
      return;
    }

    if (_isScanning) {
      return;
    }

    // Start scanning
    _isScanning = true;
    _scannedIds.clear();

    _scanSubscription?.cancel();
    _scanSubscription = bleManager.scanForDevices(
      withServices: [Uuid.parse(serviceId)],
      scanMode: options?.scanMode ?? _options.scanMode,
      requireLocationServicesEnabled: options?.requireLocationServicesEnabled ??
          _options.requireLocationServicesEnabled,
    ).listen(
      (device) {
        if (_scannedIds.contains(device.id)) {
          return;
        }

        final lDevice = LedgerDevice(
          id: device.id,
          address: device.id,
          name: device.name,
          rssi: device.rssi,
        );

        _scannedIds.add(lDevice.id);
        streamController.add(lDevice);
      },
    );

    Future.delayed(options?.maxScanDuration ?? _options.maxScanDuration, () {
      stop();
    });

    yield* streamController.stream;
  }

  @override
  Future<void> connect(
    LedgerDevice device, {
    LedgerOptions? options,
  }) async {
    // Check for permissions
    final granted = (await onPermissionRequest?.call(status)) ?? true;
    if (!granted) {
      return;
    }

    // Stop scanning when connecting to a device.
    await stop();

    // There are numerous issues on the Android BLE stack that leave it hanging
    // when you try to connect to a device that is not in range.
    // To work around this issue use the method connectToAdvertisingDevice to
    // first scan for the device and only if it is found connect to it.
    final c = Completer();

    StreamSubscription? subscription;
    _connectedDevices[device.id]?.disconnect();
    subscription = bleManager
        .connectToAdvertisingDevice(
      id: device.id,
      withServices: [Uuid.parse(serviceId)],
      prescanDuration: options?.prescanDuration ?? _options.prescanDuration,
      connectionTimeout:
          options?.connectionTimeout ?? _options.connectionTimeout,
    )
        .listen(
      (state) async {
        if (state.connectionState == DeviceConnectionState.connected) {
          final services = await bleManager.discoverServices(device.id);
          final ledger = DiscoveredLedger(
            device: device,
            subscription: subscription,
            services: services,
          );

          final gateway = LedgerGattGateway(
            bleManager: bleManager,
            ledger: ledger,
            mtu: options?.mtu ?? _options.mtu,
          );

          await gateway.start();
          _connectedDevices[device.id] = gateway;

          c.complete();
        }
      },
      onError: (ex) async {
        await disconnect(device);
        c.completeError(ex);
      },
    );

    return c.future;
  }

  @override
  Future<T> sendRequest<T>(
    LedgerDevice device,
    LedgerOperation request,
  ) async {
    final d = _connectedDevices[device.id];
    if (d == null) {
      throw LedgerException(message: 'Unable to send request.');
    }

    return d.sendRequest<T>(request);
  }

  /// Returns the current status of the BLE subsystem of the host device.
  BleStatus get status => bleManager.status;

  @override
  Future<void> disconnect(LedgerDevice device) async {
    _connectedDevices[device.id]?.disconnect();
    _connectedDevices.remove(device.id);
  }

  @override
  Future<void> stop() async {
    _isScanning = false;
    _scanSubscription?.cancel();
  }

  @override
  Future<void> dispose() async {
    await stop();

    for (var subscription in _connectedDevices.values) {
      subscription.disconnect();
    }

    _connectedDevices.clear();
  }
}
