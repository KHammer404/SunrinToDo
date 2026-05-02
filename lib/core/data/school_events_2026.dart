class SchoolEventEntry {
  final String date; // YYYYMMDD
  final String title;
  const SchoolEventEntry({required this.date, required this.title});
}

/// 2026학년도 선린인터넷고등학교 학사일정 (PDF 기준)
const List<SchoolEventEntry> schoolEvents2026 = [
  // ── 3월 ─────────────────────────────────────────────────────────
  SchoolEventEntry(date: '20260302', title: '대체휴일(삼일절)'),
  SchoolEventEntry(date: '20260303', title: '시업식/입학식'),
  SchoolEventEntry(date: '20260304', title: '학과 오리엔테이션'),
  SchoolEventEntry(date: '20260305', title: '동아리 시연회'),
  SchoolEventEntry(date: '20260311', title: '학생상담주간 시작(~3.31)'),
  SchoolEventEntry(date: '20260313', title: '1학기 정부회장 선출'),
  SchoolEventEntry(date: '20260316', title: '학부모상담주간(~3/20)'),
  SchoolEventEntry(date: '20260320', title: '학부모총회 및 수업공개'),
  SchoolEventEntry(date: '20260324', title: '학력평가(1,2,3)'),
  SchoolEventEntry(date: '20260327', title: '다문화교육'),

  // ── 4월 ─────────────────────────────────────────────────────────
  SchoolEventEntry(date: '20260403', title: '학교폭력예방교육'),
  SchoolEventEntry(date: '20260406', title: '지방기능경기대회(~4/10)'),
  SchoolEventEntry(date: '20260410', title: '봉사활동교육'),
  SchoolEventEntry(date: '20260417', title: '학급별 진로활동'),
  SchoolEventEntry(date: '20260423', title: '중간고사(1,2,3)'),
  SchoolEventEntry(date: '20260424', title: '중간고사(1,2,3)'),
  SchoolEventEntry(date: '20260427', title: '중간고사(1,2,3)'),
  SchoolEventEntry(date: '20260428', title: '중간고사(1,2,3)'),
  SchoolEventEntry(date: '20260430', title: '노동절 재량휴업일'),

  // ── 5월 ─────────────────────────────────────────────────────────
  SchoolEventEntry(date: '20260504', title: '재량휴업일'),
  SchoolEventEntry(date: '20260507', title: '학력평가(3)'),
  SchoolEventEntry(date: '20260508', title: '성폭력예방교육'),
  SchoolEventEntry(date: '20260514', title: '창업아이템발표대회'),
  SchoolEventEntry(date: '20260515', title: '성매매예방교육'),
  SchoolEventEntry(date: '20260518', title: '수련회(1학년)/체험활동(2학년)'),
  SchoolEventEntry(date: '20260519', title: '수련회(1학년)/체험활동(2학년)'),
  SchoolEventEntry(date: '20260520', title: '수련회(1학년)/체험활동(2학년)'),
  SchoolEventEntry(date: '20260521', title: '서울지역상업경진대회(예정)'),
  SchoolEventEntry(date: '20260527', title: '졸업전시회(콘텐츠3)'),
  SchoolEventEntry(date: '20260529', title: '약물오남용·감염병예방교육'),

  // ── 6월 ─────────────────────────────────────────────────────────
  SchoolEventEntry(date: '20260603', title: '휴업일(지방선거일)'),
  SchoolEventEntry(date: '20260604', title: '학력평가(1,2,3)'),
  SchoolEventEntry(date: '20260605', title: '한마음건강체육행사'),
  SchoolEventEntry(date: '20260612', title: '1차 입학설명회'),
  SchoolEventEntry(date: '20260619', title: '학급별 진로활동'),
  SchoolEventEntry(date: '20260626', title: '학급자치'),

  // ── 7월 ─────────────────────────────────────────────────────────
  SchoolEventEntry(date: '20260701', title: '기말고사(1,2,3)'),
  SchoolEventEntry(date: '20260702', title: '기말고사(1,2,3)'),
  SchoolEventEntry(date: '20260703', title: '기말고사(1,2,3)'),
  SchoolEventEntry(date: '20260706', title: '기말고사(1,2,3)'),
  SchoolEventEntry(date: '20260707', title: '해커톤 OT'),
  SchoolEventEntry(date: '20260708', title: '학력평가(3)'),
  SchoolEventEntry(date: '20260709', title: '직업기초능력평가(3)'),
  SchoolEventEntry(date: '20260710', title: '전교회장/2학기정부회장 선출'),
  SchoolEventEntry(date: '20260713', title: '1학년 신체검진'),
  SchoolEventEntry(date: '20260714', title: '알고리즘 페스티벌'),
  SchoolEventEntry(date: '20260715', title: '포트폴리오발표회(콘2,3)'),
  SchoolEventEntry(date: '20260721', title: '방학식/해커톤'),

  // ── 8월 ─────────────────────────────────────────────────────────
  SchoolEventEntry(date: '20260818', title: '개학식'),
  SchoolEventEntry(date: '20260822', title: '전국기능경기대회(~8/28)'),
  SchoolEventEntry(date: '20260828', title: '봉사활동교육'),

  // ── 9월 ─────────────────────────────────────────────────────────
  SchoolEventEntry(date: '20260902', title: '학력평가(1,2,3)'),
  SchoolEventEntry(date: '20260903', title: '전국상업경진대회(예정)'),
  SchoolEventEntry(date: '20260904', title: '학교폭력예방교육'),
  SchoolEventEntry(date: '20260911', title: '소프트웨어나눔축제(~9/12)'),
  SchoolEventEntry(date: '20260917', title: '프로그래밍챌린지'),
  SchoolEventEntry(date: '20260918', title: '학급별 진로활동'),
  SchoolEventEntry(date: '20261002', title: '선린축제'),

  // ── 10월 ────────────────────────────────────────────────────────
  SchoolEventEntry(date: '20261014', title: '중간고사(1,2)/졸업고사(3)'),
  SchoolEventEntry(date: '20261015', title: '중간고사(1,2)/졸업고사(3)'),
  SchoolEventEntry(date: '20261016', title: '중간고사(1,2)/졸업고사(3)'),
  SchoolEventEntry(date: '20261019', title: '중간고사(1,2)/졸업고사(3)'),
  SchoolEventEntry(date: '20261020', title: '학력평가(1,2,3)'),
  SchoolEventEntry(date: '20261023', title: '2차 입학설명회'),
  SchoolEventEntry(date: '20261029', title: 'IT활용능력경진대회'),
  SchoolEventEntry(date: '20261030', title: '학급별 진로활동'),

  // ── 11월 ────────────────────────────────────────────────────────
  SchoolEventEntry(date: '20261105', title: '네트워킹캠프'),
  SchoolEventEntry(date: '20261106', title: '장애인식개선교육'),
  SchoolEventEntry(date: '20261110', title: '회계실무경진대회'),
  SchoolEventEntry(date: '20261113', title: '디지털콘텐츠개발대회'),
  SchoolEventEntry(date: '20261119', title: '수능(3) / 재량휴업일(1,2)'),
  SchoolEventEntry(date: '20261120', title: '소방 안전교육'),
  SchoolEventEntry(date: '20261126', title: '신입생 특별전형 / 학생 휴업일'),
  SchoolEventEntry(date: '20261127', title: '다문화교육'),

  // ── 12월 ────────────────────────────────────────────────────────
  SchoolEventEntry(date: '20261209', title: '기말고사(1,2)'),
  SchoolEventEntry(date: '20261210', title: '기말고사(1,2)'),
  SchoolEventEntry(date: '20261211', title: '기말고사(1,2)'),
  SchoolEventEntry(date: '20261214', title: '기말고사(1,2)'),
  SchoolEventEntry(date: '20261218', title: '학급별 진로활동'),
  SchoolEventEntry(date: '20261221', title: '학과발표회'),
  SchoolEventEntry(date: '20261222', title: '학과발표회/해커페스티벌'),
  SchoolEventEntry(date: '20261223', title: '학과종합발표회'),
  SchoolEventEntry(date: '20261228', title: '학과종합발표회'),
  SchoolEventEntry(date: '20261229', title: 'AI컨퍼런스'),
  SchoolEventEntry(date: '20261231', title: '방학식'),

  // ── 2월 (2027) ──────────────────────────────────────────────────
  SchoolEventEntry(date: '20270201', title: '개학식'),
  SchoolEventEntry(date: '20270204', title: '졸업식/종업식'),
];
