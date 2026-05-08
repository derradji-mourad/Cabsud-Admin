import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/supabase_config.dart';
import '../../theme/app_colors.dart';

class FareManagementPage extends StatefulWidget {
  const FareManagementPage({Key? key}) : super(key: key);

  @override
  State<FareManagementPage> createState() => _FareManagementPageState();
}

class _FareManagementPageState extends State<FareManagementPage> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> fares = [];
  bool isLoading = true;

  final String edgeFunctionUrl = SupabaseConfig.modifierFareFn;

  final Map<String, IconData> categoryIcons = {
    'standard': Icons.directions_car,
    'premium': Icons.star,
    'van': Icons.airport_shuttle,
    'economy': Icons.local_taxi,
  };

  final Map<String, Color> categoryColors = {
    'standard': AppColors.info,
    'premium': AppColors.gold,
    'van': AppColors.success,
    'economy': AppColors.warning,
  };

  @override
  void initState() {
    super.initState();
    fetchFares();
  }

  Future<void> fetchFares() async {
    final response = await supabase
        .from('fare')
        .select('id, category, base_fare, price_per_km, price_per_minute')
        .order('id');

    setState(() {
      fares = List<Map<String, dynamic>>.from(response);
      isLoading = false;
    });
  }

  Future<void> updateFareOnServer(Map<String, dynamic> updatedFare) async {
    final res = await http.post(
      Uri.parse(edgeFunctionUrl),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(updatedFare),
    );

    if (res.statusCode == 200) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: AppColors.success),
                const SizedBox(width: 12),
                const Text('Fare updated successfully'),
              ],
            ),
            backgroundColor: AppColors.surface,
          ),
        );
      }
      fetchFares();
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Update failed: ${res.body}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void showEditDialog(Map<String, dynamic> fare) {
    showDialog(
      context: context,
      builder: (_) => _FareEditDialog(
        fare: fare,
        onSave: updateFareOnServer,
      ),
    );
  }

  Widget buildFareCard(Map<String, dynamic> fare) {
    final category = fare['category'].toString().toLowerCase();
    final color = categoryColors[category] ?? AppColors.gold;
    final icon = categoryIcons[category] ?? Icons.directions_car;

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 280),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final isVerySmall = width < 400;
          final isSmall = width < 600;

          // Adaptive dimensions
          final cardPadding = isVerySmall ? 12.0 : (isSmall ? 16.0 : 20.0);
          final iconSize = isVerySmall ? 40.0 : 56.0;
          final iconInnerSize = isVerySmall ? 22.0 : 28.0;
          final titleFontSize = isVerySmall ? 15.0 : 18.0;
          final spacing = isVerySmall ? 8.0 : (isSmall ? 12.0 : 16.0);
          final editButtonSize = isVerySmall ? 36.0 : 44.0;
          final editIconSize = isVerySmall ? 16.0 : 20.0;

          return Container(
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
                  // Header
                  Row(
                    children: [
                      Container(
                        width: iconSize,
                        height: iconSize,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(
                            isVerySmall ? 10 : 14,
                          ),
                          border: Border.all(
                            color: color.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Icon(icon, color: color, size: iconInnerSize),
                      ),
                      SizedBox(width: spacing),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              fare['category'].toString().toUpperCase(),
                              style: TextStyle(
                                fontSize: titleFontSize,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                            if (!isVerySmall) ...[
                              const SizedBox(height: 4),
                              const Text(
                                'Vehicle category pricing',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textMuted,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ],
                          ],
                        ),
                      ),
                      SizedBox(width: spacing * 0.5),
                      Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          onTap: () => showEditDialog(fare),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            width: editButtonSize,
                            height: editButtonSize,
                            decoration: BoxDecoration(
                              color: AppColors.gold.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppColors.gold.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Icon(
                              Icons.edit,
                              color: AppColors.gold,
                              size: editIconSize,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  SizedBox(height: isVerySmall ? 16 : 20),

                  // Pricing Grid
                  Container(
                    padding: EdgeInsets.all(isVerySmall ? 12 : 16),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: isVerySmall
                        ? Column(
                            children: [
                              _buildPriceItem(
                                'Base Fare',
                                fare['base_fare'],
                                color,
                                isVerySmall,
                              ),
                              const SizedBox(height: 12),
                              Divider(
                                color: AppColors.border.withValues(alpha: 0.3),
                                height: 1,
                              ),
                              const SizedBox(height: 12),
                              _buildPriceItem(
                                'Per KM',
                                fare['price_per_km'],
                                color,
                                isVerySmall,
                              ),
                              const SizedBox(height: 12),
                              Divider(
                                color: AppColors.border.withValues(alpha: 0.3),
                                height: 1,
                              ),
                              const SizedBox(height: 12),
                              _buildPriceItem(
                                'Per Min',
                                fare['price_per_minute'],
                                color,
                                isVerySmall,
                              ),
                            ],
                          )
                        : Row(
                            children: [
                              Expanded(
                                child: _buildPriceItem(
                                  'Base Fare',
                                  fare['base_fare'],
                                  color,
                                  isVerySmall,
                                ),
                              ),
                              Container(
                                width: 1,
                                height: 50,
                                color: AppColors.border.withValues(alpha: 0.3),
                              ),
                              Expanded(
                                child: _buildPriceItem(
                                  'Per KM',
                                  fare['price_per_km'],
                                  color,
                                  isVerySmall,
                                ),
                              ),
                              Container(
                                width: 1,
                                height: 50,
                                color: AppColors.border.withValues(alpha: 0.3),
                              ),
                              Expanded(
                                child: _buildPriceItem(
                                  'Per Min',
                                  fare['price_per_minute'],
                                  color,
                                  isVerySmall,
                                ),
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPriceItem(
    String label,
    dynamic value,
    Color color,
    bool isVerySmall,
  ) {
    return Column(
      children: [
        Text(
          '€${value.toStringAsFixed(2)}',
          style: TextStyle(
            fontSize: isVerySmall ? 16 : 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: isVerySmall ? 10 : 12,
            color: AppColors.textMuted,
          ),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.gold),
      );
    }

    if (fares.isEmpty) {
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
                Icons.attach_money,
                size: 64,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'No fare configurations found',
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

    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: fares.length,
      itemBuilder: (context, index) {
        return buildFareCard(fares[index]);
      },
    );
  }
}

class _FareEditDialog extends StatefulWidget {
  final Map<String, dynamic> fare;
  final Future<void> Function(Map<String, dynamic>) onSave;

  const _FareEditDialog({required this.fare, required this.onSave});

  @override
  State<_FareEditDialog> createState() => _FareEditDialogState();
}

class _FareEditDialogState extends State<_FareEditDialog> {
  late final TextEditingController baseFareCtrl;
  late final TextEditingController perKmCtrl;
  late final TextEditingController perMinCtrl;

  @override
  void initState() {
    super.initState();
    baseFareCtrl = TextEditingController(
      text: widget.fare['base_fare'].toString(),
    );
    perKmCtrl = TextEditingController(
      text: widget.fare['price_per_km'].toString(),
    );
    perMinCtrl = TextEditingController(
      text: widget.fare['price_per_minute'].toString(),
    );
  }

  @override
  void dispose() {
    baseFareCtrl.dispose();
    perKmCtrl.dispose();
    perMinCtrl.dispose();
    super.dispose();
  }

  Widget _buildField(
    TextEditingController controller,
    String label,
    IconData icon,
  ) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: AppColors.surface,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.secondary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.edit, color: AppColors.gold),
          ),
          const SizedBox(width: 14),
          Text('Edit ${widget.fare['category'].toString().toUpperCase()}'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildField(baseFareCtrl, 'Base Fare', Icons.attach_money),
            const SizedBox(height: 16),
            _buildField(perKmCtrl, 'Price per KM', Icons.straighten),
            const SizedBox(height: 16),
            _buildField(perMinCtrl, 'Price per Minute', Icons.timer),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final updated = {
              'id': widget.fare['id'],
              'base_fare': double.tryParse(baseFareCtrl.text) ?? 0.0,
              'price_per_km': double.tryParse(perKmCtrl.text) ?? 0.0,
              'price_per_minute': double.tryParse(perMinCtrl.text) ?? 0.0,
            };
            Navigator.pop(context);
            widget.onSave(updated);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
