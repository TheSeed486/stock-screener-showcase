// Condition card — displays a single condition with edit/delete actions.

import 'package:flutter/material.dart';
import '../../../theme/app_colors.dart';
import '../models/stage_model.dart';

class ConditionCard extends StatelessWidget {
  final ConditionModel condition;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const ConditionCard({
    super.key,
    required this.condition,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(condition.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text(condition.expr.displayLabel,
                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: onEdit,
            borderRadius: BorderRadius.circular(4),
            child: const Padding(padding: EdgeInsets.all(3), child: Icon(Icons.edit, size: 14, color: AppColors.textMuted)),
          ),
          InkWell(
            onTap: onDelete,
            borderRadius: BorderRadius.circular(4),
            child: const Padding(padding: EdgeInsets.all(3), child: Icon(Icons.close, size: 14, color: AppColors.textMuted)),
          ),
        ],
      ),
    );
  }
}
