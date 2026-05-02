import 'package:flutter/material.dart';

class AppColors {
  // 카테고리 색상
  static const Color performance = Color(0x993B82F6); // 수행평가 - 파랑 (반투명)
  static const Color exam = Color(0x99EF4444);        // 시험 - 빨강 (반투명)
  static const Color assignment = Color(0x9922C55E);  // 과제 - 초록 (반투명)
  static const Color notice = Color(0x99EAB308);      // 공지 - 노랑 (반투명)
  static const Color other = Color(0x996B7280);       // 기타 - 회색 (반투명)
}

ThemeData buildAppTheme() {
  return ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF3B82F6),
      brightness: Brightness.light,
    ),
    useMaterial3: true,
    appBarTheme: const AppBarTheme(
      elevation: 0,
      centerTitle: true,
    ),
  );
}
