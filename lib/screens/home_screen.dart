import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/briskers_colors.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 18) return 'Good Afternoon';
    return 'Good Evening';
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    return ColoredBox(
      color: Colors.white,
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            SizedBox(
          height: 158,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned(
                right: -12,
                top: 22,
                width: 230,
                child: Opacity(
                  opacity: 0.20,
                  child: Image.asset(
                    'assets/home_car.png',
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 14, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Image.asset(
                          'assets/briskers_header_logo.png',
                          width: 176,
                          fit: BoxFit.contain,
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: 'Notifications',
                          onPressed: () {},
                          icon: const Badge(
                            smallSize: 8,
                            child: Icon(Icons.notifications_none, size: 28),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Profile',
                          onPressed: () {},
                          icon: const Icon(
                            Icons.account_circle_outlined,
                            size: 31,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${_greeting()}, Raz',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      DateFormat('EEEE, MMM d, yyyy').format(now),
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF667085),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Row(
                      children: [
                        Icon(
                          Icons.wb_sunny_outlined,
                          size: 19,
                          color: Color(0xFFF4B400),
                        ),
                        SizedBox(width: 5),
                        Text(
                          'Weather',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Spacer(),
                        // Reserved for operational weather messages such as
                        // "Rain expected after 3 PM".
                        SizedBox.shrink(),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
            ),
            const SizedBox(height: 8),
            const _NeedsAttentionPanel(),
            const SizedBox(height: 12),
            const _HomeTiles(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _NeedsAttentionPanel extends StatelessWidget {
  const _NeedsAttentionPanel();

  @override
  Widget build(BuildContext context) {
    Widget item(IconData icon, String count, String label) => Expanded(
          child: Column(
            children: [
              Icon(icon, size: 24, color: const Color(0xFF344054)),
              const SizedBox(height: 3),
              Text(count, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: Color(0xFF475467))),
            ],
          ),
        );

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F7FB),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Text('Needs Attention', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const Spacer(),
              TextButton(onPressed: () {}, child: const Text('View All')),
            ],
          ),
          Row(
            children: [
              item(Icons.calendar_month_outlined, '0', 'Appointment\nRequests'),
              const SizedBox(height: 58, child: VerticalDivider(width: 1)),
              item(Icons.receipt_long_outlined, '0', 'Pending Close\nInvoices'),
              const SizedBox(height: 58, child: VerticalDivider(width: 1)),
              item(Icons.build_outlined, '0', 'Unassigned\nJobs'),
              const SizedBox(height: 58, child: VerticalDivider(width: 1)),
              item(Icons.chat_bubble_outline, '0', 'Unread\nMessages'),
            ],
          ),
        ],
      ),
    );
  }
}


class _HomeTiles extends StatelessWidget {
  const _HomeTiles();

  Widget _tile(
    String label,
    String subtitle,
    IconData icon,
    Color color,
  ) {
    return Container(
      height: 78,
      padding: const EdgeInsets.fromLTRB(12, 8, 9, 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            softWrap: false,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: Color(0xFF101828),
            ),
          ),
          const Spacer(),
          Row(
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFF667085),
                  ),
                ),
              ),
              Icon(Icons.chevron_right, color: color, size: 23),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget row(Widget left, Widget right) => Row(
          children: [
            Expanded(child: left),
            const SizedBox(width: 10),
            Expanded(child: right),
          ],
        );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          row(
            _tile('Customers', '0 Total', Icons.people_outline,
                BriskersColors.customers),
            _tile('Appointments', '0 Today', Icons.calendar_month_outlined,
                BriskersColors.appointments),
          ),
          const SizedBox(height: 7),
          row(
            _tile('Estimates', '0 Open', Icons.request_quote_outlined,
                BriskersColors.estimates),
            _tile('Invoices', '0 Open', Icons.receipt_long_outlined,
                BriskersColors.invoices),
          ),
          const SizedBox(height: 7),
          row(
            _tile('Jobs', '0 In Progress', Icons.build_outlined,
                BriskersColors.jobs),
            _tile('Expenses', '0 Today', Icons.payments_outlined,
                BriskersColors.expenses),
          ),
          const SizedBox(height: 7),
          row(
            _tile('Reports', 'View Reports', Icons.bar_chart_outlined,
                BriskersColors.reports),
            _tile('Chat', '0 Unread', Icons.chat_bubble_outline,
                BriskersColors.chat),
          ),
        ],
      ),
    );
  }
}
