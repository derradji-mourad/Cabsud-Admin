import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../config/supabase_config.dart';
import '../../theme/app_colors.dart';

class DriversPage extends StatefulWidget {
  const DriversPage({Key? key}) : super(key: key);

  @override
  State<DriversPage> createState() => _DriversPageState();
}

class _DriversPageState extends State<DriversPage> {
  List<dynamic> drivers = [];
  bool isLoading = true;
  String? error;

  final String supabaseEdgeUrl = SupabaseConfig.getDriversFn;
  final String supabaseAnonKey = SupabaseConfig.anonKey;

  @override
  void initState() {
    super.initState();
    fetchDrivers();
  }

  Future<void> fetchDrivers() async {
    try {
      final response = await http.get(
        Uri.parse(supabaseEdgeUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $supabaseAnonKey',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (mounted) {
          setState(() {
            drivers = data['drivers'];
            isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            error = 'Failed to load drivers (${response.statusCode})';
            isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = 'Error: $e';
          isLoading = false;
        });
      }
    }
  }

  Widget buildDriverCard(
    Map<String, dynamic> driver,
    int index, {
    required bool isVerySmall,
    required double cardPadding,
    required double avatarSize,
    required double nameFontSize,
    required double spacing,
  }) {
    final isAvailable = driver['isavailable'] == true;

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 280),
      child: Container(
        margin: EdgeInsets.only(bottom: isVerySmall ? 12 : 16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(isVerySmall ? 12 : 16),
          border: Border.all(
            color: AppColors.border.withValues(alpha: 0.3),
          ),
        ),
        child: Padding(
          padding: EdgeInsets.all(cardPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header Row
                  Row(
                    children: [
                      Container(
                        width: avatarSize,
                        height: avatarSize,
                        decoration: BoxDecoration(
                          gradient: AppColors.goldGradient,
                          borderRadius: BorderRadius.circular(
                            isVerySmall ? 10 : 14,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            _getInitials(
                              driver['firstname'],
                              driver['lastname'],
                            ),
                            style: TextStyle(
                              fontSize: isVerySmall ? 16 : 20,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: spacing),

                      // Name & ID
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${driver['firstname'] ?? ''} ${driver['lastname'] ?? ''}',
                              style: TextStyle(
                                fontSize: nameFontSize,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'ID: ${driver['identifier'] ?? 'N/A'}',
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.textMuted,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ],
                        ),
                      ),

                      SizedBox(width: spacing * 0.5),

                      // Status Badge
                      Flexible(
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: isVerySmall ? 8 : 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: isAvailable
                                ? AppColors.success.withValues(alpha: 0.15)
                                : AppColors.error.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isAvailable
                                  ? AppColors.success.withValues(alpha: 0.3)
                                  : AppColors.error.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: isAvailable
                                      ? AppColors.success
                                      : AppColors.error,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  isAvailable ? 'Available' : 'Busy',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: isAvailable
                                        ? AppColors.success
                                        : AppColors.error,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                  SizedBox(height: isVerySmall ? 16 : 20),

                  // Info Grid
                  Container(
                    padding: EdgeInsets.all(isVerySmall ? 12 : 16),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        _buildInfoRow(
                          Icons.email_outlined,
                          'Email',
                          driver['email'] ?? 'N/A',
                        ),
                        const SizedBox(height: 12),
                        _buildInfoRow(
                          Icons.phone_outlined,
                          'Phone',
                          driver['phonenumber'] ?? 'N/A',
                        ),
                        if (driver['address'] != null) ...[
                          const SizedBox(height: 12),
                          _buildInfoRow(
                            Icons.location_on_outlined,
                            'Address',
                            driver['address'],
                          ),
                        ],
                        if (driver['drivinglicencenumber'] != null) ...[
                          const SizedBox(height: 12),
                          _buildInfoRow(
                            Icons.badge_outlined,
                            'License',
                            driver['drivinglicencenumber'],
                          ),
                        ],
                      ],
                    ),
                  ),

                  SizedBox(height: isVerySmall ? 12 : 16),

                  // Action Buttons
                  Row(
                    children: [
                      Expanded(
                        child: _buildActionButton(
                          'Call',
                          Icons.phone,
                          AppColors.success,
                          () {},
                          isVerySmall,
                        ),
                      ),
                      SizedBox(width: isVerySmall ? 6 : 10),
                      Expanded(
                        child: _buildActionButton(
                          'Message',
                          Icons.message,
                          AppColors.info,
                          () {},
                          isVerySmall,
                        ),
                      ),
                      SizedBox(width: isVerySmall ? 6 : 10),
                      Expanded(
                        child: _buildActionButton(
                          'Details',
                          Icons.info_outline,
                          AppColors.gold,
                          () {},
                          isVerySmall,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.textMuted),
        const SizedBox(width: 12),
        Flexible(
          flex: 2,
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          flex: 3,
          child: Text(
            value,
            style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton(
    String label,
    IconData icon,
    Color color,
    VoidCallback onPressed,
    bool iconOnly,
  ) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: EdgeInsets.symmetric(
            vertical: iconOnly ? 10 : 12,
            horizontal: iconOnly ? 0 : 4,
          ),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: iconOnly ? 20 : 18),
              if (!iconOnly) ...[
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _getInitials(String? firstName, String? lastName) {
    final first = firstName?.isNotEmpty == true
        ? firstName![0].toUpperCase()
        : '';
    final last = lastName?.isNotEmpty == true ? lastName![0].toUpperCase() : '';
    return '$first$last';
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.gold),
      );
    }

    if (error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.error_outline,
                size: 48,
                color: AppColors.error,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              error!,
              style: const TextStyle(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  isLoading = true;
                  error = null;
                });
                fetchDrivers();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (drivers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.surface.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.people_outline,
                size: 64,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'No drivers found',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = screenWidth - 40;
    final isVerySmall = cardWidth < 400;
    final isSmall = cardWidth < 600;
    final cardPadding = isVerySmall ? 12.0 : (isSmall ? 16.0 : 20.0);
    final avatarSize = isVerySmall ? 44.0 : 56.0;
    final nameFontSize = isVerySmall ? 16.0 : 18.0;
    final spacing = isVerySmall ? 8.0 : (isSmall ? 12.0 : 16.0);

    return RefreshIndicator(
      onRefresh: fetchDrivers,
      color: AppColors.gold,
      backgroundColor: AppColors.surface,
      child: ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: drivers.length,
        itemBuilder: (context, index) {
          return buildDriverCard(
            drivers[index],
            index,
            isVerySmall: isVerySmall,
            cardPadding: cardPadding,
            avatarSize: avatarSize,
            nameFontSize: nameFontSize,
            spacing: spacing,
          );
        },
      ),
    );
  }
}
