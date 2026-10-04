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
        child: SizedBox(
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
                    const Align(
                      alignment: Alignment.centerRight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.wb_sunny_outlined,
                            size: 20,
                            color: Color(0xFFF4B400),
                          ),
                          SizedBox(width: 5),
                          Text(
                            'Weather',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
