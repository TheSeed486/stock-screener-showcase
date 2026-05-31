// Stage tab bar — horizontal tabs for each stage, plus add button.

import 'package:flutter/material.dart';
import '../../../theme/app_colors.dart';
import '../screener_view_model.dart';

class StageTabBar extends StatelessWidget {
  final ScreenerViewModel vm;
  const StageTabBar({super.key, required this.vm});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ...vm.program.stages.asMap().entries.map((e) => _tab(e.key, e.value.name)),
        const SizedBox(width: 6),
        InkWell(
          onTap: vm.addStage,
          borderRadius: BorderRadius.circular(5),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
              borderRadius: BorderRadius.circular(5),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add, size: 14, color: AppColors.textSecondary),
                SizedBox(width: 2),
                Text('添加阶段', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _tab(int index, String name) {
    final selected = index == vm.selectedStageIndex;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: InkWell(
        onTap: () => vm.selectedStageIndex = index,
        borderRadius: BorderRadius.circular(5),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: selected ? AppColors.brand.withValues(alpha: 0.12) : Colors.transparent,
            border: Border.all(color: selected ? AppColors.brand : AppColors.border),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(name, style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                color: selected ? AppColors.brand : AppColors.textSecondary,
              )),
              if (vm.program.stages.length > 1) ...[
                const SizedBox(width: 6),
                InkWell(
                  onTap: () => vm.removeStage(index),
                  borderRadius: BorderRadius.circular(3),
                  child: const Icon(Icons.close, size: 12, color: AppColors.textMuted),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
