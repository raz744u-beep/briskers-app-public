import 'package:flutter/material.dart';

typedef BriskersTab = ({String label, Color color, IconData icon});

class BriskersCurvedTabs extends StatelessWidget {
  const BriskersCurvedTabs({
    super.key,
    required this.entries,
    this.controller,
    this.onTap,
  });

  final List<BriskersTab> entries;
  final TabController? controller;
  final ValueChanged<int>? onTap;

  @override
  Widget build(BuildContext context) {
    final activeController = controller ?? DefaultTabController.of(context);
    return AnimatedBuilder(
      animation: activeController,
      builder: (context, _) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TabBar(
            controller: activeController,
            onTap: onTap,
            indicatorSize: TabBarIndicatorSize.tab,
            indicatorWeight: 0,
            // The shared stripe below the tab row is the only selection indicator.
            indicator: const BoxDecoration(),
            labelPadding: EdgeInsets.zero,
            dividerHeight: 0,
            labelColor: Colors.white,
            unselectedLabelColor: const Color(0xFF111820),
            tabs: [
              for (final (i, entry) in entries.indexed)
                Tab(
                  height: 40,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipPath(
                        clipper: _ProfileTabClip(),
                        child: Container(
                          key: ValueKey('profile-tab-${entry.label}'),
                          alignment: Alignment.center,
                          decoration: activeController.index == i
                              ? BoxDecoration(color: entry.color)
                              : const BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Color(0xFFEAEDF3),
                                      Color(0xFFDCE2EB),
                                    ],
                                  ),
                                ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 9),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Row(
                                children: [
                                  Icon(entry.icon, size: 16),
                                  const SizedBox(width: 3),
                                  Text(
                                    entry.label,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          SizedBox(
            width: double.infinity,
            height: 3,
            child: ColoredBox(
              key: const ValueKey('profile-tabs-stripe'),
              // Use the same theme value as the selected tab background.
              color: entries[activeController.index].color,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileTabClip extends CustomClipper<Path> {
  @override
  Path getClip(Size s) => Path()
    ..moveTo(0, s.height)
    ..lineTo(8, 10)
    ..quadraticBezierTo(11, 0, 21, 0)
    ..lineTo(s.width - 21, 0)
    ..quadraticBezierTo(s.width - 11, 0, s.width - 8, 10)
    ..lineTo(s.width, s.height)
    ..close();
  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class BriskersControlledTabs extends StatefulWidget {
  const BriskersControlledTabs({
    super.key,
    required this.entries,
    required this.selected,
    required this.onSelected,
  });

  final List<BriskersTab> entries;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  State<BriskersControlledTabs> createState() => _BriskersControlledTabsState();
}

class _BriskersControlledTabsState extends State<BriskersControlledTabs>
    with SingleTickerProviderStateMixin {
  late final _controller = TabController(
    length: widget.entries.length,
    initialIndex: widget.selected,
    vsync: this,
  );

  @override
  void didUpdateWidget(BriskersControlledTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller.index != widget.selected) {
      _controller.index = widget.selected;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BriskersCurvedTabs(
    entries: widget.entries,
    controller: _controller,
    onTap: widget.onSelected,
  );
}
