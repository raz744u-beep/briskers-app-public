import '../../services/receipt_scanning_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Owner-only enrollment of the receipt gateway credential.
/// This does not change the Briskers/Supabase connection mode and never
/// writes the token to SQLite, shared preferences, logs or the network.
class ReceiptAiGatewaySettingsScreen extends StatefulWidget {
  const ReceiptAiGatewaySettingsScreen({
    super.key,
    required this.businessId,
    required this.isOwner,
  });

  final String businessId;
  final bool isOwner;

  @override
  State<ReceiptAiGatewaySettingsScreen> createState() =>
      _ReceiptAiGatewaySettingsScreenState();
}

class _ReceiptAiGatewaySettingsScreenState
    extends State<ReceiptAiGatewaySettingsScreen> {
  static const _storage = FlutterSecureStorage();
  final _controller = TextEditingController();
  bool _showNotice = true;
  bool _hasToken = false;
  bool _busy = true;
  String? _message;

  String get _key => 'receipt_ai_gateway_token:${widget.businessId}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!widget.isOwner) {
      if (mounted) {
        setState(() {
          _busy = false;
          _message = 'Only the Owner may enroll this device.';
        });
      }
      return;
    }
    try {
      final notice = await ReceiptScanningNotice.shown(widget.businessId);
      final existing = await _storage.read(key: _key);
      if (!mounted) return;
      setState(() {
        _showNotice = notice;
        _hasToken = existing != null && existing.isNotEmpty;
        _busy = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _message = 'Secure storage could not be opened on this device.';
        });
      }
    }
  }

  Future<void> _save() async {
    if (!widget.isOwner || _busy) return;
    final token = _controller.text.trim();
    if (token.length < 32 || token.contains(RegExp(r'\s'))) {
      setState(() => _message = 'Enter the full receipt-only gateway token.');
      return;
    }
    setState(() { _busy = true; _message = null; });
    try {
      await _storage.write(key: _key, value: token);
      if (!mounted) return;
      _controller.clear();
      setState(() {
        _hasToken = true;
        _message = 'Receipt gateway token securely saved on this device. '
            'Shop synchronization was not changed.';
      });
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'Secure storage could not save the token.');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _revoke() async {
    if (!widget.isOwner || _busy) return;
    setState(() { _busy = true; _message = null; });
    try {
      await _storage.delete(key: _key);
      if (!mounted) return;
      _controller.clear();
      setState(() {
        _hasToken = false;
        _message = 'This device no longer has a receipt AI token.';
      });
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'Could not remove the token from secure storage.');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Receipt AI connection')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'This connection sends only receipts you explicitly approve '
            'for online recognition. Briskers remains in its existing '
            'Force Offline/Auto mode for financial synchronization.',
          ),
          const SizedBox(height: 16),
          Text(_hasToken
              ? 'Receipt gateway credential is saved on this device.'
              : 'No receipt gateway credential is saved on this device.'),
          const SizedBox(height: 16),
          if (widget.isOwner) ...[
            SwitchListTile(
              title: const Text('Show scanning notice'),
              value: _showNotice,
              onChanged: _busy ? null : (value) async {
                if (await ReceiptScanningNotice.setShown(widget.businessId, value) && mounted) {
                  setState(() => _showNotice = value);
                }
              },
            ),
            TextField(
              controller: _controller,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              keyboardType: TextInputType.visiblePassword,
              decoration: const InputDecoration(
                labelText: 'Receipt gateway token',
                helperText: 'Not your OpenAI API key. Never share in chat.',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : _save,
              icon: const Icon(Icons.lock_outline),
              label: const Text('Save securely on this device'),
            ),
            if (_hasToken)
              OutlinedButton.icon(
                onPressed: _busy ? null : _revoke,
                icon: const Icon(Icons.phonelink_erase_outlined),
                label: const Text('Disconnect this device'),
              ),
          ],
          if (_message != null) ...[
            const SizedBox(height: 12),
            Text(_message!),
          ],
        ],
      ),
    );
  }
}
