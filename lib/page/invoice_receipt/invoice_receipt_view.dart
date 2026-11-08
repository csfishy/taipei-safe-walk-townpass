import 'package:town_pass/gen/assets.gen.dart';
import 'package:town_pass/util/tp_app_bar.dart';
import 'package:town_pass/util/tp_card.dart';
import 'package:town_pass/util/tp_colors.dart';
import 'package:town_pass/util/tp_text.dart';
import 'package:flutter/material.dart';

class InvoiceReceiptView extends StatelessWidget {
  const InvoiceReceiptView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const TPAppBar(
        title: '發票收據',
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        children: [
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: TPCard(
              child: Stack(
                children: [
                  const Positioned(
                    top: -20.0,
                    left: -20.0,
                    child: CircleAvatar(
                      radius: 50.0,
                      backgroundColor: TPColors.primary100,
                    ),
                  ),
                  Positioned(
                    top: 18.0,
                    left: 22.0,
                    child: Assets.svg.iconProtect.svg(),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      children: [
                        const TPText(
                          '發票收據',
                          style: TPTextStyles.h2SemiBold,
                          color: TPColors.primary500,
                        ),
                        const SizedBox(height: 4.0),
                        TPText(
                          '服務狀態',
                          style: TPTextStyles.h3Regular,
                          color: TPColors.grayscale700,
                        ),
                        const SizedBox(height: 32.0),
                        TPText(
                          '發票收據服務尚未配置，暫時無法查詢。',
                          style: TPTextStyles.h3Regular,
                          color: TPColors.grayscale700,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
