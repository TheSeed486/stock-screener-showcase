// Settings bar — strategy name, universe, action buttons.

import 'package:flutter/material.dart';
import '../../../theme/app_colors.dart';
import '../screener_view_model.dart';

class ScreenerSettingsBar extends StatefulWidget {
  final ScreenerViewModel vm;
  final VoidCallback? onShowResults;
  const ScreenerSettingsBar({super.key, required this.vm, this.onShowResults});

  @override
  State<ScreenerSettingsBar> createState() => _ScreenerSettingsBarState();
}

class _ScreenerSettingsBarState extends State<ScreenerSettingsBar> {
  late final TextEditingController _nameCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.vm.program.name);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.filter_alt_outlined, size: 18, color: AppColors.brand),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 32,
              child: TextField(
                controller: _nameCtrl,
                decoration: _inputDec('策略名称'),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                onChanged: widget.vm.updateName,
              ),
            ),
          ),
          const SizedBox(width: 10),
          _actionBtn('校验', widget.vm.running ? null : () async {
            final ok = await widget.vm.validate();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(ok ? '校验通过' : widget.vm.error ?? '校验失败'), duration: const Duration(seconds: 2)),
              );
            }
          }),
          const SizedBox(width: 6),
          _actionBtn('运行', widget.vm.running ? null : () => widget.vm.run(), primary: true),
          const SizedBox(width: 6),
          _actionBtn('保存策略', widget.vm.running ? null : () async {
            await widget.vm.saveStrategy();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已保存'), duration: Duration(seconds: 2)),
              );
            }
          }),
          if (widget.vm.running)
            const Padding(
              padding: EdgeInsets.only(left: 8),
              child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          if (widget.vm.resultRows.isNotEmpty) ...[
            const SizedBox(width: 6),
            _actionBtn('查看结果 (${widget.vm.resultRows.length})', widget.onShowResults, primary: true),
          ],
          if (widget.vm.pipelineJson != null && widget.vm.resultRows.isEmpty) ...[
            const SizedBox(width: 6),
            _actionBtn('查看JSON', () => widget.onShowResults?.call()),
          ],
          const Spacer(),
          Icon(Icons.storage, size: 14, color: AppColors.textMuted),
          const SizedBox(width: 4),
          Text('${widget.vm.availableSymbols.length} 只股票',
            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _actionBtn(String label, VoidCallback? onTap, {bool primary = false}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: primary ? AppColors.brand : null,
          border: primary ? null : Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(label, style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: primary ? Colors.white : AppColors.textSecondary,
          fontFamily: 'MiSans',
        )),
      ),
    );
  }

  InputDecoration _inputDec(String? hint) => InputDecoration(
    hintText: hint,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(7), borderSide: const BorderSide(color: AppColors.border)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(7), borderSide: const BorderSide(color: AppColors.border)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(7), borderSide: const BorderSide(color: AppColors.brand)),
  );
}
