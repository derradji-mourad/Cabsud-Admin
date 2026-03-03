import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/live_requests/request_details_page.dart';
import '../theme/app_colors.dart';
import 'sidebar_menu.dart';
import '../features/live_requests/live_requests_page.dart';
import '../features/request_history/request_history_page.dart';
import '../features/add_driver/add_driver_page.dart';
import '../features/fare_management/fare_management_page.dart';
import '../features/all_drivers/all_drivers_page.dart';
import '../features/quick_trips/quick_trips_page.dart';
import '../main.dart'; // navigatorKey

class DashboardLayout extends StatefulWidget {
  const DashboardLayout({Key? key}) : super(key: key);

  @override
  State<DashboardLayout> createState() => _DashboardLayoutState();
}

class _DashboardLayoutState extends State<DashboardLayout> {
  int selectedIndex = 0;
  bool _dialogShown = false;
  RealtimeChannel? _channel;

  final List<String> pageTitles = const [
    "Live Requests",
    "Request History",
    "Add Driver",
    "Fare Management",
    "All Drivers",
    "All Drivers",
    "Map Request",
    "Quick Trips",
  ];

  final List<Widget> pages = [
    const ServicesPage(),
    const RequestHistoryPage(),
    const AddDriverPage(),
    const FareManagementPage(),
    const DriversPage(),
    const DriversPage(),
    const LiveDriverMapPage(),
    const QuickTripsPage(),
  ];

  @override
  void initState() {
    super.initState();
    _subscribeToDriverDeclines();
  }

  void _subscribeToDriverDeclines() {
    final supabase = Supabase.instance.client;

    _channel = supabase
        .channel('admin')
        .onBroadcast(
          event: 'driver_declined',
          callback: (payload, [ref]) {
            if (!_dialogShown && payload['payload'] != null) {
              _dialogShown = true;

              final data = payload['payload'];
              final String driverName = data['driver_name'] ?? 'Unknown';
              final String pickup = data['pickup'] ?? 'Unknown';
              final String dropoff = data['dropoff'] ?? 'Unknown';

              _showDeclinedDialog(
                driverName: driverName,
                tripInfo: 'From $pickup to $dropoff',
              );

              Future.delayed(const Duration(seconds: 10), () {
                _dialogShown = false;
              });
            }
          },
        )
        .subscribe();
  }

  void _showDeclinedDialog({
    required String driverName,
    required String tripInfo,
  }) {
    final context = navigatorKey.currentContext;
    if (context == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.secondary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.warning_amber_rounded,
                color: AppColors.warning,
              ),
            ),
            const SizedBox(width: 12),
            const Text('Driver Declined Trip'),
          ],
        ),
        content: Text(
          '$driverName has declined the trip.\n\nTrip: $tripInfo',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  bool _isSidebarExpanded = true;

  void _toggleSidebar() {
    setState(() => _isSidebarExpanded = !_isSidebarExpanded);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isSmallScreen = constraints.maxWidth < 800;

          if (isSmallScreen) {
            // Mobile/Tablet Layout (Stack with Overlay)
            return Stack(
              children: [
                // Main Content (Full Width)
                Column(
                  children: [
                    // Mobile Header with Menu Button
                    _buildMobileHeader(),

                    // Page Content
                    Expanded(child: _buildPageContent(isSmall: true)),
                  ],
                ),

                // Backdrop for Sidebar (only when expanded)
                if (_isSidebarExpanded)
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: _toggleSidebar,
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.5),
                      ),
                    ),
                  ),

                // Floating Sidebar
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 300),
                  left: _isSidebarExpanded ? 0 : -260,
                  top: 0,
                  bottom: 0,
                  width: 260,
                  child: SidebarMenu(
                    selectedIndex: selectedIndex,
                    isExpanded: true, // Always expanded when visible in mobile
                    onItemSelected: (index) {
                      setState(() => selectedIndex = index);
                      if (isSmallScreen) _toggleSidebar(); // Close on select
                    },
                    onToggleExpand: _toggleSidebar,
                  ),
                ),
              ],
            );
          } else {
            // Desktop Layout (Row)
            return Row(
              children: [
                // Sidebar
                SidebarMenu(
                  selectedIndex: selectedIndex,
                  onItemSelected: (index) {
                    setState(() {
                      selectedIndex = index;
                    });
                  },
                  isExpanded: _isSidebarExpanded,
                  onToggleExpand: _toggleSidebar,
                ),

                // Main Content Area
                Expanded(
                  child: Column(
                    children: [
                      // Header Bar
                      _buildHeader(),

                      // Page Content
                      Expanded(child: _buildPageContent(isSmall: false)),
                    ],
                  ),
                ),
              ],
            );
          }
        },
      ),
    );
  }

  Widget _buildPageContent({required bool isSmall}) {
    final margin = isSmall ? 8.0 : 24.0;

    return Container(
      margin: EdgeInsets.fromLTRB(margin, 0, margin, margin),
      decoration: BoxDecoration(
        color: AppColors.secondary.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(isSmall ? 16 : 24),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.3)),
      ),
      clipBehavior: Clip.antiAlias,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: pages[selectedIndex],
      ),
    );
  }

  Widget _buildMobileHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.menu, color: AppColors.textPrimary),
            onPressed: _toggleSidebar,
          ),
          const SizedBox(width: 8),
          Text(
            pageTitles[selectedIndex],
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const Spacer(),
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: AppColors.goldGradient,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.person, size: 20, color: AppColors.primary),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isSmallScreen = constraints.maxWidth < 600;

        return Container(
          padding: EdgeInsets.fromLTRB(
            isSmallScreen ? 16 : 32,
            20,
            isSmallScreen ? 16 : 24,
            16,
          ),
          child: Row(
            children: [
              // Page Title
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pageTitles[selectedIndex],
                      style: TextStyle(
                        fontSize: isSmallScreen ? 20 : 28,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (!isSmallScreen) ...[
                      const SizedBox(height: 4),
                      Text(
                        _getPageSubtitle(),
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.textMuted,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(width: 16),

              // Search (hide on small screens)
              if (!isSmallScreen)
                Container(
                  width: 200,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.surface.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.border.withValues(alpha: 0.3),
                    ),
                  ),
                  child: const Row(
                    children: [
                      SizedBox(width: 14),
                      Icon(Icons.search, color: AppColors.textMuted, size: 20),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Search...',
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              if (!isSmallScreen) const SizedBox(width: 16),

              // Notification Bell
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.surface.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.border.withValues(alpha: 0.3),
                  ),
                ),
                child: Stack(
                  children: [
                    const Center(
                      child: Icon(
                        Icons.notifications_outlined,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: AppColors.error,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 12),

              // User Avatar
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: AppColors.goldGradient,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.person, color: AppColors.primary),
              ),
            ],
          ),
        );
      },
    );
  }

  String _getPageSubtitle() {
    switch (selectedIndex) {
      case 0:
        return 'Monitor and manage incoming ride requests';
      case 1:
        return 'View completed and past requests';
      case 2:
        return 'Register a new driver to the fleet';
      case 3:
        return 'Configure pricing for different vehicle types';
      case 4:
        return 'View and manage all registered drivers';
      case 5:
        return 'Track drivers on the map in real-time';
      default:
        return '';
    }
  }
}
