import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/briskers_colors.dart';
import '../../widgets/briskers_page_header.dart';

enum ShopNavigationSection {
  home('Home', Icons.home_outlined, BriskersColors.today),
  customers('Customers', Icons.people_outline, BriskersColors.customers),
  jobs('Jobs', Icons.build_outlined, BriskersColors.jobs),
  estimates('Estimates', Icons.description_outlined, BriskersColors.estimates),
  invoices('Invoices', Icons.receipt_long_outlined, BriskersColors.invoices),
  schedule('Schedule', Icons.calendar_month_outlined, BriskersColors.schedule),
  expenses(
    'Expenses',
    Icons.account_balance_wallet_outlined,
    BriskersColors.expenses,
  ),
  more('More', Icons.more_horiz, BriskersColors.more),
  tasks('Tasks', Icons.checklist, BriskersColors.jobs),
  payroll('Payroll', Icons.payments_outlined, BriskersColors.invoices),
  employees('Employees', Icons.badge_outlined, BriskersColors.customers),
  reports('Reports', Icons.analytics_outlined, BriskersColors.reports),
  settings('Settings', Icons.settings_outlined, BriskersColors.settings);

  const ShopNavigationSection(this.label, this.icon, this.color);

  final String label;
  final IconData icon;
  final Color color;
}

typedef ShopNavigationItem = ({ShopNavigationSection section, bool visible});

class ShopNavigationPreferences {
  const ShopNavigationPreferences(this.businessId);

  final String businessId;
  static final changes = ValueNotifier<String?>(null);

  String get _key => 'briskers_dock_order_v1_$businessId';

  static List<ShopNavigationItem> get defaults => [
    for (final section in ShopNavigationSection.values)
      (section: section, visible: true),
  ];

  Future<List<ShopNavigationItem>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_key) ?? const [];
    final missing = {
      for (final section in ShopNavigationSection.values) section.name: section,
    };
    return [
      for (final value in stored)
        if (missing.remove(value.startsWith('-') ? value.substring(1) : value)
            case final ShopNavigationSection section)
          (
            section: section,
            visible:
                section == ShopNavigationSection.settings ||
                !value.startsWith('-'),
          ),
      for (final section in missing.values) (section: section, visible: true),
    ];
  }

  Future<void> save(List<ShopNavigationItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = await prefs.setStringList(_key, [
      for (final item in items)
        '${item.visible ? '' : '-'}${item.section.name}',
    ]);
    if (!saved) throw StateError('Could not save navigation preferences.');
    // Emit even if the same shop saved twice.
    changes.value = null;
    changes.value = businessId;
  }
}

class NavigationSettingsScreen extends StatefulWidget {
  const NavigationSettingsScreen({super.key, required this.businessId});

  final String businessId;

  @override
  State<NavigationSettingsScreen> createState() =>
      _NavigationSettingsScreenState();
}

class _NavigationSettingsScreenState extends State<NavigationSettingsScreen> {
  late final _preferences = ShopNavigationPreferences(widget.businessId);
  List<ShopNavigationItem>? _items;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await _preferences.load();
      if (mounted) {
        setState(() {
          _items = items;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not open saved navigation settings.');
      }
    }
  }

  Future<void> _save(List<ShopNavigationItem> next) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await _preferences.save(next);
      if (mounted) setState(() => _items = next);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save navigation settings.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      appBar: AppBar(title: const BriskersPageTitle(title: 'Navigation')),
      body: items == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : TextButton(onPressed: _load, child: Text('$_error Retry')),
            )
          : ReorderableListView.builder(
              buildDefaultDragHandles: false,
              header: const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Drag to reorder the bottom navigation. Settings is always available.',
                ),
              ),
              itemCount: items.length,
              onReorderItem: (from, to) {
                final next = [...items];
                next.insert(to, next.removeAt(from));
                _save(next);
              },
              itemBuilder: (context, index) {
                final item = items[index];
                final section = item.section;
                return ListTile(
                  key: ValueKey(section),
                  leading: Icon(section.icon, color: section.color),
                  title: Text(section.label),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: item.visible,
                        activeThumbColor: BriskersColors.confirm,
                        onChanged:
                            _saving || section == ShopNavigationSection.settings
                            ? null
                            : (value) {
                                final next = [...items];
                                next[index] = (
                                  section: section,
                                  visible: value,
                                );
                                _save(next);
                              },
                      ),
                      ReorderableDragStartListener(
                        index: index,
                        enabled: !_saving,
                        child: const Padding(
                          padding: EdgeInsets.only(left: 12),
                          child: Icon(
                            Icons.drag_handle,
                            semanticLabel: 'Reorder section',
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
