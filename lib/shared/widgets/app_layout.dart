import 'package:flutter/material.dart';

import '../../services/booking_watcher.dart';
import '../../services/session_storage.dart';
import '../../services/sync_watcher.dart';
import '../../services/timer_expiry_watcher.dart';
import '../../services/topup_watcher.dart';
import 'app_header.dart';
import 'app_sidebar.dart';

class AppLayout extends StatefulWidget {
  final Widget child;
  final String title;
  final String? subtitle;
  final bool showSearch;
  final String activeMenuKey;
  final ValueChanged<String> onMenuSelect;
  final VoidCallback? onRefresh;

  const AppLayout({
    super.key,
    required this.child,
    required this.title,
    this.subtitle,
    this.showSearch = true,
    required this.activeMenuKey,
    required this.onMenuSelect,
    this.onRefresh,
  });

  @override
  State<AppLayout> createState() => _AppLayoutState();
}

class _AppLayoutState extends State<AppLayout> {
  // Null shows every sidebar item, which is also the correct look while
  // permissions are still loading (SessionStorage caches after the first
  // read, so this only actually awaits once per app run).
  Set<String>? _allowedMenuKeys;

  // Static: every page route builds its own AppLayout instance (see
  // app_router.dart), so instance state would reset the sidebar to
  // expanded on every navigation. This keeps the collapsed/expanded
  // choice consistent across pages for the rest of the app run.
  static bool _sidebarCollapsed = false;

  @override
  void initState() {
    super.initState();
    _loadAllowedMenuKeys();
    // Idempotent — every page mounts its own AppLayout (see app_router.dart),
    // so this just no-ops after the first page of the session starts it.
    // Runs until logout (see navigateToMenu), independent of page navigation.
    TimerExpiryWatcher.instance.start();
    TopupWatcher.instance.start();
    BookingWatcher.instance.start();
    SyncWatcher.instance.start();
  }

  Future<void> _loadAllowedMenuKeys() async {
    final keys = await SessionStorage().getAllowedMenuKeys();
    if (mounted) setState(() => _allowedMenuKeys = keys);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          AppSidebar(
            activeKey: widget.activeMenuKey,
            onSelect: widget.onMenuSelect,
            allowedMenuKeys: _allowedMenuKeys,
            collapsed: _sidebarCollapsed,
            onToggleCollapse: () {
              setState(() => _sidebarCollapsed = !_sidebarCollapsed);
            },
          ),

          Expanded(
            child: Column(
              children: [
                AppHeader(
                  title: widget.title,
                  subtitle: widget.subtitle,
                  showSearch: widget.showSearch,
                  onRefresh: widget.onRefresh,
                ),

                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: widget.child,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
