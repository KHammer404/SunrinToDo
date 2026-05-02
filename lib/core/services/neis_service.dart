import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:sunrintodo/core/constants/app_constants.dart';

class NeisException implements Exception {
  final String message;

  const NeisException(this.message);

  @override
  String toString() => message;
}

class NeisConfigurationException extends NeisException {
  const NeisConfigurationException(super.message);
}

class NeisApiException extends NeisException {
  const NeisApiException(super.message);
}

String neisErrorMessage(Object error) {
  if (error is NeisException) {
    return error.message;
  }
  return '데이터를 불러올 수 없어요';
}

class MealInfo {
  final String date;
  final String mealName;
  final List<String> dishes;
  final String calories;
  final List<String> allergyInfo;

  MealInfo({
    required this.date,
    required this.mealName,
    required this.dishes,
    required this.calories,
    required this.allergyInfo,
  });
}

class TimetableEntry {
  final int period;
  final String subject;
  final String date;
  String? teacher; // NEIS에 없어서 직접 입력

  TimetableEntry({required this.period, required this.subject, required this.date, this.teacher});
}

class SchoolSchedule {
  final String date;
  final String eventName;
  final String? eventContent;
  final String? dayType;

  SchoolSchedule({
    required this.date,
    required this.eventName,
    this.eventContent,
    this.dayType,
  });
}

class NeisService {
  static String _requireApiKey() {
    if (!AppConstants.hasNeisApiKey) {
      throw const NeisConfigurationException(
        'NEIS_API_KEY가 설정되지 않았어요.\n앱 실행 시 --dart-define=NEIS_API_KEY=... 를 추가해주세요.',
      );
    }
    return AppConstants.neisApiKey;
  }

  static Future<Map<String, List<TimetableEntry>>> getWeekTimetable({
    required int grade,
    required int classNum,
    required DateTime weekStart,
  }) async {
    final apiKey = _requireApiKey();
    final from =
        '${weekStart.year}${weekStart.month.toString().padLeft(2, '0')}${weekStart.day.toString().padLeft(2, '0')}';
    final to = weekStart.add(const Duration(days: 4));
    final toStr =
        '${to.year}${to.month.toString().padLeft(2, '0')}${to.day.toString().padLeft(2, '0')}';

    final uri = Uri.parse(
      '${AppConstants.neisBaseUrl}/hisTimetable'
      '?KEY=$apiKey'
      '&Type=json'
      '&ATPT_OFCDC_SC_CODE=${AppConstants.officeCode}'
      '&SD_SCHUL_CODE=${AppConstants.schoolCode}'
      '&AY=${weekStart.year}'
      '&SEM=1'
      '&TI_FROM_YMD=$from'
      '&TI_TO_YMD=$toStr'
      '&GRADE=$grade'
      '&CLASS_NM=$classNum',
    );

    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw NeisApiException(
        '시간표 정보를 불러오지 못했어요. (HTTP ${response.statusCode})',
      );
    }

    final data = jsonDecode(response.body);
    if (data['RESULT'] != null) return {};

    if (data['hisTimetable'] is! List || (data['hisTimetable'] as List).length < 2) {
      throw const NeisApiException('시간표 응답 형식을 확인할 수 없어요.');
    }

    final rows = data['hisTimetable'][1]['row'] as List;
    final Map<String, List<TimetableEntry>> result = {};

    for (final row in rows) {
      final date = row['ALL_TI_YMD'] as String;
      result.putIfAbsent(date, () => []);
      result[date]!.add(TimetableEntry(
        period: int.parse(row['PERIO'].toString()),
        subject: row['ITRT_CNTNT'] as String,
        date: date,
      ));
    }

    for (final entries in result.values) {
      entries.sort((a, b) => a.period.compareTo(b.period));
    }

    return result;
  }

  static Future<List<SchoolSchedule>> getMonthSchedule(int year, int month) async {
    final apiKey = _requireApiKey();
    final from =
        '$year${month.toString().padLeft(2, '0')}01';
    final lastDay = DateTime(year, month + 1, 0).day;
    final to =
        '$year${month.toString().padLeft(2, '0')}${lastDay.toString().padLeft(2, '0')}';

    final uri = Uri.parse(
      '${AppConstants.neisBaseUrl}/SchoolSchedule'
      '?KEY=$apiKey'
      '&Type=json'
      '&pIndex=1'
      '&pSize=1000'
      '&ATPT_OFCDC_SC_CODE=${AppConstants.officeCode}'
      '&SD_SCHUL_CODE=${AppConstants.schoolCode}'
      '&AA_FROM_YMD=$from'
      '&AA_TO_YMD=$to',
    );

    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw NeisApiException(
        '학사일정 정보를 불러오지 못했어요. (HTTP ${response.statusCode})',
      );
    }

    final data = jsonDecode(response.body);
    if (data['RESULT'] != null) return [];

    if (data['SchoolSchedule'] is! List || (data['SchoolSchedule'] as List).length < 2) {
      throw const NeisApiException('학사일정 응답 형식을 확인할 수 없어요.');
    }

    final rows = data['SchoolSchedule'][1]['row'] as List;
    return rows
        .map((row) => SchoolSchedule(
              date: row['AA_YMD'] as String,
              eventName: row['EVENT_NM'] as String,
              eventContent: row['EVENT_CNTNT'] as String?,
              dayType: row['SBTR_DD_SC_NM'] as String?,
            ))
        .toList();
  }

  static Future<List<MealInfo>> getMeals(DateTime date) async {
    final apiKey = _requireApiKey();
    final dateStr =
        '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';

    final uri = Uri.parse(
      '${AppConstants.neisBaseUrl}/mealServiceDietInfo'
      '?KEY=$apiKey'
      '&Type=json'
      '&ATPT_OFCDC_SC_CODE=${AppConstants.officeCode}'
      '&SD_SCHUL_CODE=${AppConstants.schoolCode}'
      '&MLSV_YMD=$dateStr',
    );

    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw NeisApiException(
        '급식 정보를 불러오지 못했어요. (HTTP ${response.statusCode})',
      );
    }

    final data = jsonDecode(response.body);

    // 데이터 없는 날 처리
    if (data['RESULT'] != null) return [];

    if (data['mealServiceDietInfo'] is! List ||
        (data['mealServiceDietInfo'] as List).length < 2) {
      throw const NeisApiException('급식 응답 형식을 확인할 수 없어요.');
    }

    final rows = data['mealServiceDietInfo'][1]['row'] as List;
    return rows.map((row) {
      final dishStr = (row['DDISH_NM'] as String)
          .replaceAll(RegExp(r'<br/>'), '\n')
          .replaceAll(RegExp(r'\d+\.'), '');
      final dishes =
          dishStr.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

      // 알레르기 정보 파싱
      final allergyNums = RegExp(r'\d+').allMatches(row['DDISH_NM'] as String)
          .map((m) => m.group(0)!)
          .toSet()
          .toList();

      return MealInfo(
        date: row['MLSV_YMD'] as String,
        mealName: row['MMEAL_SC_NM'] as String,
        dishes: dishes,
        calories: row['CAL_INFO'] as String,
        allergyInfo: allergyNums,
      );
    }).toList();
  }
}
