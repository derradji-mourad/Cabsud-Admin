import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class SidebarMenu extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onItemSelected;
  final bool isExpanded;
  final VoidCallback onToggleExpand;

  const SidebarMenu({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
    required this.isExpanded,
    required this.onToggleExpand,
  });

  final List<SidebarMenuItem> menuItems = const [
    SidebarMenuItem(
      icon: Icons.notifications_active_outlined,
      activeIcon: Icons.notifications_active,
      title: "Live Requests",
    ),
    SidebarMenuItem(
      icon: Icons.history_outlined,
      activeIcon: Icons.history,
      title: "Request History",
    ),
    SidebarMenuItem(
      icon: Icons.person_add_outlined,
      activeIcon: Icons.person_add,
      title: "Add Driver",
    ),
    SidebarMenuItem(
      icon: Icons.payments_outlined,
      activeIcon: Icons.payments,
      title: "Fare Management",
    ),
    SidebarMenuItem(
      icon: Icons.people_outlined,
      activeIcon: Icons.people,
      title: "All Drivers",
    ),
    SidebarMenuItem(
      icon: Icons.map_outlined,
      activeIcon: Icons.map,
      title: "Map Request",
    ),
    SidebarMenuItem(
      icon: Icons.flash_on_outlined,
      activeIcon: Icons.flash_on,
      title: "Quick Trips",
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      width: isExpanded ? 260 : 80,
      decoration: const BoxDecoration(
        gradient: AppColors.sidebarGradient,
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 10,
            offset: Offset(2, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          const SizedBox(height: 24),

          // Logo Section
          _buildLogo(),

          const SizedBox(height: 32),

          // Divider
          Padding(
            padding: EdgeInsets.symmetric(horizontal: isExpanded ? 24 : 16),
            child: Divider(
              color: AppColors.border.withValues(alpha: 0.5),
              height: 1,
            ),
          ),

          const SizedBox(height: 16),

          // Menu Items
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: menuItems.length,
              itemBuilder: (context, index) {
                return _buildMenuItem(index);
              },
            ),
          ),

          // Toggle Button
          _buildToggleButton(),

          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildLogo() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: EdgeInsets.symmetric(horizontal: isExpanded ? 24 : 16),
      child: Row(
        mainAxisAlignment: isExpanded
            ? MainAxisAlignment.start
            : MainAxisAlignment.center,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: AppColors.goldGradient,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: AppColors.gold.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.local_taxi,
              color: AppColors.primary,
              size: 26,
            ),
          ),
          if (isExpanded) ...[
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CABSUD',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                      letterSpacing: 1.2,
                    ),
                  ),
                  Text(
                    'Admin Panel',
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMenuItem(int index) {
    final item = menuItems[index];
    final isSelected = index == selectedIndex;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () => onItemSelected(index),
          borderRadius: BorderRadius.circular(12),
          hoverColor: AppColors.gold.withValues(alpha: 0.08),
          splashColor: AppColors.gold.withValues(alpha: 0.12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: EdgeInsets.symmetric(
              horizontal: isExpanded ? 16 : 0,
              vertical: 14,
            ),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.gold.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected
                    ? AppColors.gold.withValues(alpha: 0.3)
                    : Colors.transparent,
                width: 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: isExpanded
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.center,
              children: [
                // Gold indicator bar
                if (isExpanded)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 3,
                    height: 24,
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.gold : Colors.transparent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),

                // Icon
                Icon(
                  isSelected ? item.activeIcon : item.icon,
                  color: isSelected ? AppColors.gold : AppColors.textSecondary,
                  size: 22,
                ),

                // Title
                if (isExpanded) ...[
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      item.title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.normal,
                        color: isSelected
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],

                // Notification badge for Live Requests
                if (index == 0 && isExpanded)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.error,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'NEW',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildToggleButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onToggleExpand,
          borderRadius: BorderRadius.circular(12),
          hoverColor: AppColors.surface.withValues(alpha: 0.5),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surface.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.border.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedRotation(
                  turns: isExpanded ? 0 : 0.5,
                  duration: const Duration(milliseconds: 300),
                  child: const Icon(
                    Icons.keyboard_double_arrow_left,
                    color: AppColors.textSecondary,
                    size: 20,
                  ),
                ),
                if (isExpanded) ...[
                  const SizedBox(width: 8),
                  const Text(
                    'Collapse',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SidebarMenuItem {
  final IconData icon;
  final IconData activeIcon;
  final String title;

  const SidebarMenuItem({
    required this.icon,
    required this.activeIcon,
    required this.title,
  });
}
