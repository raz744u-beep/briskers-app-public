import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/formatters.dart';
import '../../services/briskers_api.dart';

class ShopInfoSettingsScreen extends StatefulWidget {
  const ShopInfoSettingsScreen({
    super.key,
    required this.businessId,
    required this.fallbackBusinessName,
    this.onBusinessNameChanged,
  });

  final String businessId;
  final String fallbackBusinessName;
  final ValueChanged<String>? onBusinessNameChanged;

  @override
  State<ShopInfoSettingsScreen> createState() => _ShopInfoSettingsScreenState();
}

class _ShopInfoSettingsScreenState extends State<ShopInfoSettingsScreen> {
  static const _api = BriskersApi();

  final _name = TextEditingController();
  final _address = TextEditingController();
  final _latitude = TextEditingController();
  final _longitude = TextEditingController();
  final _hours = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _googleReviews = TextEditingController();
  final _facebook = TextEditingController();
  final _about = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name.text = widget.fallbackBusinessName;
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _latitude.dispose();
    _longitude.dispose();
    _hours.dispose();
    _phone.dispose();
    _email.dispose();
    _googleReviews.dispose();
    _facebook.dispose();
    _about.dispose();
    super.dispose();
  }

  String _value(dynamic value) => value?.toString() ?? '';

  Future<void> _load() async {
    try {
      final data = await _api.businessSettings(widget.businessId);
      if (!mounted) return;
      setState(() {
        _name.text = _value(data['name']);
        _address.text = _value(data['address']);
        _latitude.text = _value(data['latitude']);
        _longitude.text = _value(data['longitude']);
        _hours.text = _value(data['operating_hours']);
        _phone.text = formatUsPhone(_value(data['phone']));
        _email.text = _value(data['email']);
        _googleReviews.text = _value(data['google_reviews_url']);
        _facebook.text = _value(data['facebook_page_url']);
        _about.text = _value(data['about_service']);
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  num? _optionalNumber(TextEditingController controller, String label) {
    final text = controller.text.trim();
    if (text.isEmpty) return null;
    final value = num.tryParse(text);
    if (value == null) {
      throw FormatException('$label is not a valid number.');
    }
    return value;
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Shop name is required.');
      return;
    }

    num? lat;
    num? lng;
    try {
      lat = _optionalNumber(_latitude, 'Latitude');
      lng = _optionalNumber(_longitude, 'Longitude');
    } on FormatException catch (error) {
      setState(() => _error = error.message);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final saved = await _api.updateBusinessSettings(
        widget.businessId,
        name: name,
        address: _address.text.trim().isEmpty ? null : _address.text.trim(),
        latitude: lat,
        longitude: lng,
        operatingHours: _hours.text.trim().isEmpty ? null : _hours.text.trim(),
        phone: digitsOnly(_phone.text).isEmpty ? null : digitsOnly(_phone.text),
        email: _email.text.trim().isEmpty ? null : _email.text.trim(),
        googleReviewsUrl:
            _googleReviews.text.trim().isEmpty ? null : _googleReviews.text.trim(),
        facebookPageUrl:
            _facebook.text.trim().isEmpty ? null : _facebook.text.trim(),
        aboutService: _about.text.trim().isEmpty ? null : _about.text.trim(),
      );

      final savedName = _value(saved['name']);
      widget.onBusinessNameChanged?.call(savedName);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Shop settings saved.')),
      );
      setState(() => _saving = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.toString();
      });
    }
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Text(title, style: Theme.of(context).textTheme.titleLarge),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Shop information')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Shop name',
                    prefixIcon: Icon(Icons.storefront),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _address,
                  textCapitalization: TextCapitalization.words,
                  minLines: 2,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Address',
                    prefixIcon: Icon(Icons.location_on_outlined),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Map pin location',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Optional. Leave empty if we want to determine it from the address later.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _latitude,
                        keyboardType: const TextInputType.numberWithOptions(
                          signed: true,
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[-0-9.]')),
                        ],
                        decoration: const InputDecoration(labelText: 'Latitude'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _longitude,
                        keyboardType: const TextInputType.numberWithOptions(
                          signed: true,
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[-0-9.]')),
                        ],
                        decoration: const InputDecoration(labelText: 'Longitude'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _hours,
                  decoration: const InputDecoration(
                    labelText: 'Operating hours',
                    prefixIcon: Icon(Icons.schedule),
                    helperText: 'Example: Mon-Fri: 8AM-5PM',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  inputFormatters: const [UsPhoneTextInputFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Phone number',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                ),
                _sectionTitle(context, 'Social links'),
                TextField(
                  controller: _googleReviews,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Google Reviews URL',
                    prefixIcon: Icon(Icons.star_outline),
                    helperText: 'Link to the shop Google reviews page',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _facebook,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Facebook Page URL',
                    prefixIcon: Icon(Icons.facebook),
                  ),
                ),
                _sectionTitle(context, 'Customer page content'),
                TextField(
                  controller: _about,
                  textCapitalization: TextCapitalization.sentences,
                  minLines: 4,
                  maxLines: 7,
                  decoration: const InputDecoration(
                    labelText: 'About our service',
                    alignLabelWithHint: true,
                    prefixIcon: Icon(Icons.info_outline),
                    helperText: 'This will appear in the customer-facing app.',
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: Text(_saving ? 'Saving...' : 'Save settings'),
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}
