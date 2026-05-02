class AppConstants {
  static const String schoolDomain = 'sunrint.hs.kr';
  static const String neisBaseUrl = 'https://open.neis.go.kr/hub';
  static const String neisApiKey = String.fromEnvironment(
    'NEIS_API_KEY',
    defaultValue: '',
  );
  static const String schoolCode = '7010536'; // 선린인터넷고등학교
  static const String officeCode = 'B10'; // 서울특별시교육청

  static bool get hasNeisApiKey => neisApiKey.isNotEmpty;
}
