// PathRef editor — reusable widget for editing PathRef (stock.anchor[offset].field).

import 'package:flutter/material.dart';
import '../../../theme/app_colors.dart';
import '../models/path_ref.dart';

class PathRefEditor extends StatelessWidget {
  final PathRef value;
  final ValueChanged<PathRef> onChanged;

  const PathRefEditor({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.4)),
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _stockDropdown(),
          _anchorDropdown(),
          _offsetInput(),
          _fieldDropdown(),
        ],
      ),
    );
  }

  Widget _stockDropdown() {
    final currentVal = value.stock.stockType;

    return SizedBox(
      width: 90,
      child: DropdownButtonFormField<String>(
        value: currentVal == 'named' || currentVal == 'marketNamed' ? 'current' : currentVal,
        decoration: _inputDec(null),
        isDense: true,
        style: const TextStyle(fontSize: 11, color: AppColors.textPrimary),
        items: const [
          DropdownMenuItem(value: 'current', child: Text('当前', style: TextStyle(fontSize: 11))),
          DropdownMenuItem(value: 'market', child: Text('大盘', style: TextStyle(fontSize: 11))),
        ],
        onChanged: (v) {
          if (v == 'current') onChanged(value.copyWith(stock: StockRef.current));
          else if (v == 'market') onChanged(value.copyWith(stock: StockRef.market));
        },
      ),
    );
  }

  Widget _anchorDropdown() {
    final currentVal = value.anchor.anchorType;

    return SizedBox(
      width: 90,
      child: DropdownButtonFormField<String>(
        value: currentVal == 'point' ? 'windowEnd' : currentVal,
        decoration: _inputDec(null),
        isDense: true,
        style: const TextStyle(fontSize: 11, color: AppColors.textPrimary),
        items: const [
          DropdownMenuItem(value: 'windowEnd', child: Text('最新', style: TextStyle(fontSize: 11))),
          DropdownMenuItem(value: 'windowStart', child: Text('窗口起点', style: TextStyle(fontSize: 11))),
          DropdownMenuItem(value: 'eachBar', child: Text('逐根', style: TextStyle(fontSize: 11))),
        ],
        onChanged: (v) {
          if (v == 'windowEnd') onChanged(value.copyWith(anchor: AnchorKind.windowEnd));
          else if (v == 'windowStart') onChanged(value.copyWith(anchor: AnchorKind.windowStart));
          else if (v == 'eachBar') onChanged(value.copyWith(anchor: AnchorKind.eachBar));
        },
      ),
    );
  }

  Widget _offsetInput() {
    return SizedBox(
      width: 55,
      child: TextFormField(
        initialValue: value.offset.toString(),
        decoration: _inputDec('偏移'),
        style: const TextStyle(fontSize: 11),
        keyboardType: TextInputType.number,
        onChanged: (v) {
          final n = int.tryParse(v);
          if (n != null) onChanged(value.copyWith(offset: n));
        },
      ),
    );
  }

  Widget _fieldDropdown() {
    final fields = ['close', 'open', 'high', 'low', 'volume', 'amount'];
    final currentValue = value.field;
    final isValid = currentValue == null || fields.contains(currentValue);

    return SizedBox(
      width: 80,
      child: DropdownButtonFormField<String>(
        value: isValid ? currentValue : null,
        decoration: _inputDec('字段'),
        isDense: true,
        style: const TextStyle(fontSize: 11, color: AppColors.textPrimary),
        items: [
          const DropdownMenuItem(value: null, child: Text('--', style: TextStyle(fontSize: 11))),
          ...fields.map((f) => DropdownMenuItem(value: f, child: Text(f, style: const TextStyle(fontSize: 11)))),
        ],
        onChanged: (v) => onChanged(value.copyWith(field: v, clearField: v == null)),
      ),
    );
  }

  InputDecoration _inputDec(String? hint) => InputDecoration(
    hintText: hint,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: AppColors.border)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: AppColors.border)),
  );
}
