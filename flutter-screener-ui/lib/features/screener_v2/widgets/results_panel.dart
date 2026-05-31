// Results panel — shows screening results or JSON debug view.

import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../theme/app_colors.dart';
import '../screener_view_model.dart';

String _fmtMs(int ms) {
  if (ms < 1000) return '${ms}ms';
  if (ms < 60000) return '${(ms / 1000).toStringAsFixed(1)}s';
  return '${(ms ~/ 60000)}m${((ms % 60000) / 1000).toStringAsFixed(0)}s';
}

class ResultsPanel extends StatelessWidget {
  final ScreenerViewModel vm;
  const ResultsPanel({super.key, required this.vm});

  @override
  Widget build(BuildContext context) {
    if (vm.resultRows.isNotEmpty) {
      return _resultsTable();
    }
    if (vm.pipelineJson != null) {
      return _jsonViewer();
    }
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.tune, size: 32, color: AppColors.textMuted),
          SizedBox(height: 8),
          Text('添加条件后点击 [校验] 查看 Pipeline JSON\n点击 [运行] 执行筛选',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _resultsTable() {
    final rows = vm.resultRows;
    if (rows.isEmpty) return const SizedBox.shrink();

    // Collect all column names from results
    final columns = <String>{};
    for (final row in rows) {
      columns.addAll(row.keys);
    }
    final colList = columns.toList();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: [
                Text('筛选结果: ${rows.length} 条 | 通过: ${vm.passedCount}/${vm.totalCount} | 耗时 ${_fmtMs(vm.elapsedMs)}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                if (vm.error != null) ...[
                  const SizedBox(width: 12),
                  Flexible(child: Text(vm.error!,
                    style: const TextStyle(fontSize: 11, color: AppColors.rise),
                    overflow: TextOverflow.ellipsis)),
                ],
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SingleChildScrollView(
                child: DataTable(
                  columns: colList.map((c) => DataColumn(
                    label: Text(c, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                  )).toList(),
                  rows: rows.take(200).map((row) => DataRow(
                    cells: colList.map((c) => DataCell(
                      Text(_fmtCell(row[c]), style: const TextStyle(fontSize: 11)),
                    )).toList(),
                  )).toList(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _jsonViewer() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Pipeline JSON', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              const Spacer(),
              if (vm.error != null)
                Flexible(child: Text(vm.error!,
                  style: const TextStyle(fontSize: 11, color: AppColors.rise),
                  overflow: TextOverflow.ellipsis)),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              child: SelectableText(
                _formatJson(vm.pipelineJson!),
                style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: AppColors.textSecondary, height: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatJson(String json) {
    try {
      return const JsonEncoder.withIndent('  ').convert(jsonDecode(json));
    } catch (_) {
      return json;
    }
  }

  String _fmtCell(dynamic v) {
    if (v == null) return '-';
    if (v is double) return v.toStringAsFixed(2);
    return v.toString();
  }
}
