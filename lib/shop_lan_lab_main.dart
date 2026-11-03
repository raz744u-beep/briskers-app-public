// ignore_for_file: prefer_interpolation_to_compose_strings, curly_braces_in_flow_control_structures

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'lab/shop_lan_lab_store.dart';
import 'lab/shop_lan_lab_transport.dart';

/// Entry point for a SEPARATE Android debug application, never regular Briskers.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Briskers LAN TEST',
    home: LanLabScreen(),
  ));
}

class LanLabScreen extends StatefulWidget {
  const LanLabScreen({super.key});

  @override
  State<LanLabScreen> createState() => _LanLabScreenState();
}

class _LanLabScreenState extends State<LanLabScreen> {
  final _text = TextEditingController();
  LanLabStore? _store;
  LanLabTransport? _transport;
  List<LanLabNote> _notes = const [];
  LanLabPairing? _peer;
  String _pairingKey = '';
  String _deviceId = '';
  String? _address;
  String _status = 'Initializing the isolated test...';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<String?> _findLocalIp() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    final eligible = <(String, String)>[];
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        if (isLanLabPrivateIpv4(address)) {
          eligible.add((interface.name, address.address));
        }
      }
    }
    if (eligible.isEmpty) return null;
    eligible.sort((a, b) {
      final aw = a.$1.toLowerCase().contains('wlan') ? 0 : 1;
      final bw = b.$1.toLowerCase().contains('wlan') ? 0 : 1;
      return aw.compareTo(bw);
    });
    return eligible.first.$2;
  }

  Future<void> _initialize() async {
    try {
      // This isolated TEST targets SDK 36. Android 17 still permits LAN
      // sockets with INTERNET permission for apps targeting <= 36. Before
      // raising target SDK to 37, add ACCESS_LOCAL_NETWORK runtime consent.
      final prefs = await SharedPreferences.getInstance();
      var id = prefs.getString('briskers_lan_lab_device_id') ?? '';
      if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(id)) {
        id = lanLabRandomHex(16);
        await prefs.setString('briskers_lan_lab_device_id', id);
      }
      var key = prefs.getString('briskers_lan_lab_key') ?? '';
      if (!isValidLanLabKey(key)) {
        key = newLanLabPairingKey();
        await prefs.setString('briskers_lan_lab_key', key);
      }
      final store = await LanLabStore.open();
      final transport = LanLabTransport(
        store: store, pairingKey: key, deviceId: id,
        onRemoteChanged: _refresh,
      );
      await transport.start();
      final ip = await _findLocalIp();
      LanLabPairing? peer;
      final rawPeer = prefs.getString('briskers_lan_lab_peer');
      if (rawPeer != null) {
        try {
          peer = LanLabPairing.parse(rawPeer);
          if (peer.key != key) peer = null;
        } on FormatException {
          peer = null;
        }
      }
      final notes = await store.all();
      if (!mounted) {
        await transport.close();
        return;
      }
      setState(() {
        _store = store;
        _transport = transport;
        _notes = notes;
        _deviceId = id;
        _pairingKey = key;
        _peer = peer;
        _address = ip;
        _status = ip == null
            ? 'No private Wi-Fi IP found. Connect both phones to shop Wi-Fi.'
            : 'Listening on ' + ip + ':' + transport.port.toString();
      });
    } catch (e) {
      if (mounted) setState(() => _status = 'Setup failed: ' + e.toString());
    }
  }

  Future<void> _refresh() async {
    final store = _store;
    if (store == null) return;
    final notes = await store.all();
    final address = await _findLocalIp();
    if (mounted) setState(() {
      _notes = notes;
      _address = address;
    });
  }

  Future<void> _add() async {
    final store = _store;
    final message = _text.text.trim();
    if (store == null || message.isEmpty || message.length > 200) return;
    setState(() => _busy = true);
    try {
      final note = await LanLabNote.create(_deviceId, message);
      await store.save(note);
      _text.clear();
      await _refresh();
      if (mounted) setState(() => _status = 'Test note saved locally.');
    } catch (e) {
      if (mounted) setState(() => _status = 'Save failed: ' + e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scanPairing() async {
    if (_transport == null) return;
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _LanPairScanner()),
    );
    if (!mounted || result == null) return;
    try {
      final peer = LanLabPairing.parse(result);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('briskers_lan_lab_key', peer.key);
      await prefs.setString(
        'briskers_lan_lab_peer', jsonEncode(peer.toJson()),
      );
      _transport!.updatePairingKey(peer.key);
      setState(() {
        _pairingKey = peer.key;
        _peer = peer;
        _status = 'Paired to ' + peer.host +
            '. Create a test note and tap Sync with peer.';
      });
    } catch (e) {
      setState(() => _status = 'Pairing failed: ' + e.toString());
    }
  }

  Future<void> _sync() async {
    final peer = _peer;
    final transport = _transport;
    if (_busy) return;
    if (peer == null || transport == null) {
      if (mounted) {
        setState(() => _status =
            'Sync is not ready. Scan the other phone QR and reopen this '
            'test app if its local listener is not available.');
      }
      return;
    }

    final started = DateTime.now();
    final endpoint = '${peer.host}:${peer.port}';
    setState(() {
      _busy = true;
      _status = 'Connecting to $endpoint over shop Wi-Fi...';
    });
    try {
      LanLabSyncResult? result;
      for (var attempt = 1; attempt <= 2; attempt++) {
        try {
          result = await transport.syncWith(peer).timeout(
            const Duration(seconds: 25),
          );
          break;
        } on SocketException catch (error) {
          if (attempt == 2) rethrow;
          if (mounted) {
            setState(() => _status =
                'Connection interrupted (${error.message}). '
                'Retrying once with $endpoint...');
          }
          await Future<void>.delayed(const Duration(milliseconds: 400));
        } on TimeoutException {
          if (attempt == 2) rethrow;
          if (mounted) {
            setState(() => _status =
                'No response yet from $endpoint. Retrying once...');
          }
          await Future<void>.delayed(const Duration(milliseconds: 400));
        }
      }
      if (result == null) throw StateError('Peer returned no sync result');
      await _refresh();
      final elapsed = DateTime.now().difference(started).inSeconds;
      if (mounted) {
        setState(() => _status =
            'Sync successful: $endpoint responded in ${elapsed}s. '
            'Sent ${result!.sent} test notes; imported ${result.imported} new '
            'notes; ${result.totalLocal} saved locally. '
            '${result.imported == 0 ? "No new incoming notes." : ""}');
      }
    } on TimeoutException {
      if (mounted) {
        setState(() => _status =
            'Sync timeout: $endpoint did not respond in time. '
            'Keep the other phone app open, check both are on the same Wi-Fi, '
            'then retry. All notes remain saved locally.');
      }
    } on SocketException catch (error) {
      if (mounted) {
        setState(() => _status =
            'Wi-Fi peer unreachable at $endpoint: ${error.message}. '
            'Check the other app is open and the phone Wi-Fi IP has not '
            'changed. All notes remain saved locally.');
      }
    } catch (error) {
      if (mounted) {
        setState(() => _status =
            'Sync failed with $endpoint: $error. '
            'All notes remain saved locally; retry after checking pairing.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _text.dispose();
    final transport = _transport;
    if (transport != null) unawaited(transport.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pairing = _address == null || _transport?.port == null
        ? null
        : LanLabPairing(
          host: _address!, port: _transport!.port!, key: _pairingKey,
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Briskers Wi-Fi Sync TEST')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Card(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'SYNTHETIC DATA ONLY. This isolated APK never opens your '
                'Briskers business database, invoices, payments, or Supabase.',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(_status),
          const SizedBox(height: 8),
          Text('Local device: ' + (_deviceId.isEmpty
              ? 'Not ready' : _deviceId.substring(0, 8))),
          const SizedBox(height: 12),
          const Text('1. On first phone: show pairing QR.',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const Text('2. On second phone: scan QR, then tap Sync. '
              'Both phones must be on the same Wi-Fi.'),
          const SizedBox(height: 12),
          if (pairing != null) ...[
            Center(
              child: QrImageView(
                data: jsonEncode(pairing.toJson()),
                version: QrVersions.auto,
                size: 240,
                backgroundColor: Colors.white,
              ),
            ),
            Center(child: SelectableText(
              'Host ' + pairing.host + ':' + pairing.port.toString(),
            )),
          ],
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _transport == null ? null : _scanPairing,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Scan other phone pairing QR'),
          ),
          if (_peer != null)
            Text('Paired peer: ' + _peer!.host + ':' +
                _peer!.port.toString()),
          const Divider(height: 28),
          const Text('Create a harmless test record',
              style: TextStyle(fontWeight: FontWeight.bold)),
          TextField(
            controller: _text,
            maxLength: 200,
            decoration: const InputDecoration(
              labelText: 'Example: Note created on Samsung S26',
              border: OutlineInputBorder(),
            ),
          ),
          FilledButton.icon(
            onPressed: _store != null && !_busy ? _add : null,
            icon: const Icon(Icons.add),
            label: const Text('Save test note on this device'),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _peer != null && !_busy ? _sync : null,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
            label: Text(_busy
                ? 'Synchronizing — check status above'
                : _peer == null
                    ? 'Scan QR to enable synchronization'
                    : 'Sync both directions over shop Wi-Fi'),
          ),
          TextButton.icon(
            onPressed: _store != null && !_busy ? _refresh : null,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh locally saved notes'),
          ),
          const Divider(height: 24),
          Text('Saved synthetic notes (' + _notes.length.toString() + ')',
              style: Theme.of(context).textTheme.titleMedium),
          for (final note in _notes)
            ListTile(
              dense: true,
              leading: const Icon(Icons.note_alt_outlined),
              title: Text(note.text),
              subtitle: Text('Origin ' + note.origin.substring(0, 8) +
                  ' · ' + note.createdAt),
            ),
          const SizedBox(height: 20),
          const Text(
            'Keep the receiving phone app open during the first test. '
            'If it sleeps or Wi-Fi disconnects, the sending phone retains '
            'its notes and a later sync retries. The pairing QR grants access '
            'to synthetic test notes only; do not share it publicly.',
          ),
        ],
      ),
    );
  }
}

class _LanPairScanner extends StatefulWidget {
  const _LanPairScanner();

  @override
  State<_LanPairScanner> createState() => _LanPairScannerState();
}

class _LanPairScannerState extends State<_LanPairScanner> {
  bool _finished = false;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Scan LAN pairing QR')),
    body: MobileScanner(
      onDetect: (capture) {
        if (_finished) return;
        for (final barcode in capture.barcodes) {
          final data = barcode.rawValue;
          if (data != null && data.isNotEmpty) {
            _finished = true;
            Navigator.of(context).pop(data);
            return;
          }
        }
      },
    ),
  );
}
