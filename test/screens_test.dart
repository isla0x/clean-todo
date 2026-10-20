// 화면 사진 뽑기: 실제 앱 코드로 화면을 그려서 PNG로 저장해요. (저장 위치: 환경변수 SHOT_DIR)
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:clean_todo/main.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final String outDir = Platform.environment['SHOT_DIR'] ?? 'build/shots';
final GlobalKey shotKey = GlobalKey();

Future<void> loadFonts() async {
  final l = FontLoader('Pretendard');
  for (final f in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    final b = File('assets/fonts/Pretendard-$f.otf').readAsBytesSync();
    l.addFont(Future.value(ByteData.sublistView(b)));
  }
  await l.load();
}

String key(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// 지금 날짜 기준 예시 데이터
String demoJson() {
  final now = DateTime.now();
  final today = key(now);
  final yest = key(now.subtract(const Duration(days: 1)));
  final tomorrow = key(now.add(const Duration(days: 1)));
  String ago(int n) => key(now.subtract(Duration(days: n)));
  final items = <Item>[
    Item(id: 'r1', title: '물 2L 마시기', isRoutine: true, created: ago(12), doneDates: {for (var i = 1; i < 6; i++) ago(i), ago(8), ago(9), ago(10)}),
    Item(id: 'r2', title: '영양제 먹기', isRoutine: true, time: '09:00', created: ago(12), doneDates: {today, ago(1), ago(2), ago(4), ago(5)}),
    Item(id: 'r3', title: '스트레칭 10분', isRoutine: true, time: '22:30', notify: true, created: ago(9), doneDates: {ago(1), ago(2), ago(3)}),
    Item(id: 't1', title: '팀 회의 준비', isRoutine: false, date: today, time: '23:50', notify: true, created: today),
    Item(id: 't2', title: '장보기', isRoutine: false, date: today, created: today),
    Item(id: 't3', title: '은행 다녀오기', isRoutine: false, date: today, time: '08:00', done: true, doneOn: today, created: today),
    Item(id: 't4', title: '치과 예약', isRoutine: false, date: tomorrow, time: '15:00', notify: true, created: today),
    Item(id: 't5', title: '택배 보내기', isRoutine: false, date: yest, done: true, doneOn: yest, created: ago(2)),
    Item(id: 't6', title: '세탁소 맡기기', isRoutine: false, date: yest, done: true, doneOn: yest, created: ago(2)),
    Item(id: 't7', title: '도서관 책 반납', isRoutine: false, date: ago(3), done: true, doneOn: ago(3), created: ago(5)),
  ];
  return jsonEncode(items.map((e) => e.toJson()).toList());
}

Future<void> setup(WidgetTester tester, {double keyboard = 0}) async {
  tester.view.physicalSize = const Size(780, 1688);
  tester.view.devicePixelRatio = 2.0;
  const pad = FakeViewPadding(top: 94, bottom: 68);
  tester.view.padding = pad;
  tester.view.viewPadding = pad;
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard * 2);
  debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  debugDisableShadows = false;
  addTearDown(() {
    tester.view.reset();
  });
}

Future<void> launch(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({'items_v1': demoJson()});
  await tester.pumpWidget(RepaintBoundary(key: shotKey, child: const TodoApp()));
  await settle(tester);
}

Future<void> settle(WidgetTester tester, {int rounds = 4}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 120)));
    await tester.pump(const Duration(milliseconds: 120));
  }
}

Future<void> shot(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(shotKey));
    final img = await boundary.toImage(pixelRatio: 2);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final f = File('$outDir/$name.png')..createSync(recursive: true);
    f.writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

Future<void> finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

Future<void> tapTab(WidgetTester tester, String label) async {
  await tester.tap(find.descendant(of: find.byType(CupertinoTabBar), matching: find.text(label)));
  await settle(tester);
}

void shotTest(String name, Future<void> Function(WidgetTester tester) body) {
  testWidgets(name, (tester) async {
    try {
      await body(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
      debugDisableShadows = true;
    }
  });
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadFonts();
  });

  shotTest('오늘', (tester) async {
    await setup(tester);
    await launch(tester);
    await shot(tester, 'Today');
    await finish(tester);
  });

  shotTest('오늘 입력 중', (tester) async {
    await setup(tester);
    await launch(tester);
    await tester.enterText(find.byType(CupertinoTextField).first, '내일 오후 3시 치과 예약');
    await settle(tester);
    await shot(tester, 'Today_input');
    await finish(tester);
  });

  shotTest('캘린더', (tester) async {
    await setup(tester);
    await launch(tester);
    await tapTab(tester, '캘린더');
    await shot(tester, 'Calendar');
    await finish(tester);
  });

  shotTest('기록', (tester) async {
    await setup(tester);
    await launch(tester);
    await tapTab(tester, '기록');
    await shot(tester, 'Stats');
    await finish(tester);
  });

  shotTest('PRO 화면', (tester) async {
    await setup(tester);
    await launch(tester);
    final ctx = tester.element(find.byType(TodayPage));
    unawaited(showProSheet(ctx));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await settle(tester);
    await shot(tester, 'Pro');
    await finish(tester);
  });
}
