import 'package:flutter/material.dart';
import '../../core/constants/app_text_styles.dart';
import 'app_back_button.dart';

class AppPageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onBack;

  const AppPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          AppBackButton(onTap: onBack),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: AppTextStyles.pageTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: AppTextStyles.pageSubtitle,
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
          trailing ?? const SizedBox(width: 38),
        ],
      ),
    );
  }
}
