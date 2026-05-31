import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class ScreenerResultsTable extends StatelessWidget {
  const ScreenerResultsTable({
    super.key,
    required this.rows,
    required this.isLoading,
    this.error,
    this.onTapRow,
  });

  final List<Map<String, dynamic>> rows;
  final bool isLoading;
  final String? error;
  final ValueChanged<Map<String, dynamic>>? onTapRow;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(),
        const SizedBox(height: 8),
        Expanded(child: _body()),
      ],
    );
  }

  Widget _header() {
    return Row(
      children: [
        const Text(
          '筛选结果',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            fontFamily: 'MiSans',
          ),
        ),
        const SizedBox(width: 8),
        if (!isLoading && error == null && rows.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.brand.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '${rows.length} 条',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.brand,
              ),
            ),
          ),
      ],
    );
  }

  Widget _body() {
    if (isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(height: 10),
            Text('正在执行筛选...', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          ],
        ),
      );
    }

    if (error != null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.rise.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.rise.withValues(alpha: 0.2)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: AppColors.rise, size: 24),
            const SizedBox(height: 8),
            Text(error!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: AppColors.rise)),
          ],
        ),
      );
    }

    if (rows.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 36, color: AppColors.textMuted),
            SizedBox(height: 10),
            Text('暂无结果', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary, fontFamily: 'MiSans')),
            SizedBox(height: 4),
            Text('配置条件后点击运行', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ],
        ),
      );
    }

    final columns = _buildColumns();
    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(AppColors.surfaceMuted),
          dataRowMinHeight: 34,
          dataRowMaxHeight: 34,
          headingRowHeight: 34,
          columnSpacing: 14,
          columns: columns.map((c) => DataColumn(label: Text(c, style: _headerStyle))).toList(),
          rows: rows.map((row) {
            return DataRow(
              onSelectChanged: onTapRow != null ? (_) => onTapRow!(row) : null,
              cells: columns.map((col) {
                final val = row[col];
                return DataCell(Text(_formatValue(val), style: const TextStyle(fontSize: 12)));
              }).toList(),
            );
          }).toList(),
        ),
      ),
    );
  }

  List<String> _buildColumns() {
    if (rows.isEmpty) return const ['symbol', 'close', 'volume'];
    final allKeys = <String>{};
    for (final row in rows) {
      allKeys.addAll(row.keys);
    }
    // Prefer common columns first
    final priority = ['symbol', 'code', 'name', 'close', 'pct_change', 'volume', 'amount', 'open', 'high', 'low'];
    final result = <String>[];
    for (final p in priority) {
      if (allKeys.contains(p)) {
        result.add(p);
        allKeys.remove(p);
      }
    }
    result.addAll(allKeys.toList()..sort());
    return result;
  }

  String _formatValue(dynamic val) {
    if (val == null) return '--';
    if (val is double) return val.toStringAsFixed(2);
    if (val is int) return val.toString();
    return val.toString();
  }

  static const _headerStyle = TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary, fontFamily: 'MiSans');
}
