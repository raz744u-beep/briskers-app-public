import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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
