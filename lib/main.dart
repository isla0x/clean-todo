import 'dart:async';
import 'dart:convert';
import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform, kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Notifier.instance.init();
  runApp(const TodoApp());
}

/// 앱 전체 포인트 컬러. 바꾸고 싶으면 여기만 수정하면 돼요.
const Color kAccent = Color(0xFF55A0FA);

/// 연한 파란 배경(알약·칩)과 진한 파란 글자. 다크 모드 색도 따로 정했어요.
const CupertinoDynamicColor kAccentSoft = CupertinoDynamicColor.withBrightness(
  color: Color(0xFFE3EEFD),
  darkColor: Color(0xFF1B2B45),
);
const CupertinoDynamicColor kAccentDeep = CupertinoDynamicColor.withBrightness(
  color: Color(0xFF1F63C4),
  darkColor: Color(0xFF8CBBFA),
);

/// 글자 크기를 한꺼번에 키우는 배율. 폰에서 작게 느껴지면 이 숫자만 올리면 돼요.
/// (1.0이면 원래 크기, 1.2면 20% 크게)
const double kTextBoost = 1.2;

/// 영문·숫자는 Plus Jakarta Sans, 한글은 Pretendard(폰트를 넣었을 때) 또는
/// iOS 기본 한글 폰트로 자동 대체돼요.
TextStyle _font(
  double size,
  FontWeight weight, {
  double letterSpacing = 0,
}) {
  return GoogleFonts.plusJakartaSans(
    fontSize: size,
    fontWeight: weight,
    letterSpacing: letterSpacing,
    color: CupertinoColors.label,
  ).copyWith(fontFamilyFallback: const ['Pretendard']);
}

class TodoApp extends StatelessWidget {
  const TodoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      title: '하루링',
      debugShowCheckedModeBanner: false,
      theme: CupertinoThemeData(
        primaryColor: kAccent,
        textTheme: CupertinoTextThemeData(
          textStyle: _font(15, FontWeight.w500, letterSpacing: -0.2),
          navLargeTitleTextStyle:
              _font(28, FontWeight.w700, letterSpacing: -0.4),
          navTitleTextStyle: _font(16, FontWeight.w600),
          tabLabelTextStyle: _font(10, FontWeight.w500, letterSpacing: -0.1),
        ),
      ),
      // 아이폰 설정의 글자 크기는 그대로 반영하면서 앱 전체 글자를 조금 키워요.
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        final scale =
            (mq.textScaler.scale(1.0) * kTextBoost).clamp(1.0, 1.6).toDouble();
        return MediaQuery(
          data: mq.copyWith(textScaler: TextScaler.linear(scale)),
          // 빈 배경을 누르면 키보드가 내려가요. (목록·버튼은 원래대로 눌려요)
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
            child: child!,
          ),
        );
      },
      home: const RootPage(),
    );
  }
}

// ───────────────────────── 데이터 ─────────────────────────

class Item {
  Item({
    required this.id,
    required this.title,
    required this.isRoutine,
    this.done = false,
    Set<String>? doneDates,
    this.date,
    this.time,
    this.notify = false,
    this.alert = AlertKind.at,
    this.created,
    this.doneOn,
  }) : doneDates = doneDates ?? <String>{};

  final String id;
  String title;
  final bool isRoutine;

  /// 투두 완료 여부 (루틴은 사용 안 함)
  bool done;

  /// 항목을 만든 날 ('yyyy-MM-dd'). 예전에 만든 항목은 비어 있어요.
  final String? created;

  /// 투두를 끝낸 날 ('yyyy-MM-dd'). 기록 화면의 "이번 달 완료"에 쓰여요.
  String? doneOn;

  /// 루틴을 완료한 날짜들 ('yyyy-MM-dd')
  final Set<String> doneDates;

  /// 투두의 날짜 ('yyyy-MM-dd'). null이면 날짜 없음(항상 오늘 목록에 보여요).
  /// 루틴은 사용 안 함.
  final String? date;

  /// 시간 ('HH:mm'). null이면 시간 없음. 루틴은 "매일 이 시간"이에요.
  final String? time;

  /// 알림을 보낼지 (종 아이콘)
  bool notify;

  /// 알림을 언제 보낼지 (정각 / 10분 전 / 1시간 전 / 당일 아침 / 전날 저녁)
  AlertKind alert;

  bool isDoneOn(String day) => isRoutine ? doneDates.contains(day) : done;

  /// 루틴 기록이 시작된 날. 만든 날과 가장 이른 완료 날짜 중 더 이른 날이에요.
  String? get startDay {
    String? start = created;
    for (final d in doneDates) {
      if (start == null || d.compareTo(start) < 0) start = d;
    }
    return start;
  }

  /// 그 날의 목록·달력에 나타나는 항목인지.
  /// 투두는 날짜가 그 날일 때, 루틴은 기록 시작일부터 오늘까지 매일이에요.
  bool scheduledOn(String day, String today) {
    if (!isRoutine) return date == day;
    if (day.compareTo(today) > 0) return false;
    if (day == today) return true;
    final s = startDay;
    return s != null && day.compareTo(s) >= 0;
  }

  /// 자정부터 몇 분째인지 (시간이 없으면 null)
  int? get minutes {
    final t = time;
    if (t == null) return null;
    final parts = t.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  /// 날짜와 시간이 모두 있는 투두의 예정 시각
  DateTime? get dueAt {
    final d = parseDayKey(date);
    final m = minutes;
    if (d == null || m == null) return null;
    return DateTime(d.year, d.month, d.day, m ~/ 60, m % 60);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'isRoutine': isRoutine,
        'done': done,
        'doneDates': doneDates.toList(),
        'date': date,
        'time': time,
        'notify': notify,
        'alert': alert.name,
        'created': created,
        'doneOn': doneOn,
      };

  // 예전에 저장한 데이터(date·time·notify 없음)도 그대로 읽혀요.
  factory Item.fromJson(Map<String, dynamic> json) => Item(
        id: json['id'] as String,
        title: json['title'] as String,
        isRoutine: json['isRoutine'] as bool,
        done: (json['done'] as bool?) ?? false,
        doneDates: ((json['doneDates'] as List?) ?? const <dynamic>[])
            .cast<String>()
            .toSet(),
        date: json['date'] as String?,
        time: json['time'] as String?,
        notify: (json['notify'] as bool?) ?? false,
        alert: alertFromName(json['alert'] as String?),
        created: json['created'] as String?,
        doneOn: json['doneOn'] as String?,
      );
}

String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

DateTime? parseDayKey(String? key) {
  if (key == null) return null;
  final p = key.split('-');
  if (p.length != 3) return null;
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

String hhmm(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
    '${(minutes % 60).toString().padLeft(2, '0')}';

/// 오늘(또는 오늘 안 했다면 어제)부터 거꾸로 이어진 연속 달성 일수
int streakOf(Item item, DateTime now) {
  var cursor = DateTime(now.year, now.month, now.day);
  if (!item.doneDates.contains(dayKey(cursor))) {
    cursor = DateTime(cursor.year, cursor.month, cursor.day - 1);
  }
  var count = 0;
  while (item.doneDates.contains(dayKey(cursor))) {
    count++;
    cursor = DateTime(cursor.year, cursor.month, cursor.day - 1);
  }
  return count;
}

// ───────────────────────── 날짜·시간 표시 ─────────────────────────

const List<String> kWeekdays = ['월', '화', '수', '목', '금', '토', '일'];

/// 600 → "오전 10:00", 840 → "오후 2:00"
String clockLabel(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  final period = h < 12 ? '오전' : '오후';
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$period $h12:${m.toString().padLeft(2, '0')}';
}

/// 오늘 기준으로 "오늘 / 내일 / 모레 / 어제 / 9월 18일 (금)"
String dateLabel(DateTime d, DateTime now) {
  final diff = DateTime.utc(d.year, d.month, d.day)
      .difference(DateTime.utc(now.year, now.month, now.day))
      .inDays;
  switch (diff) {
    case 0:
      return '오늘';
    case 1:
      return '내일';
    case 2:
      return '모레';
    case -1:
      return '어제';
  }
  return '${d.month}월 ${d.day}일 (${kWeekdays[d.weekday - 1]})';
}

/// "2시간 40분 후 시작" / "15분 지남"
String untilLabel(DateTime due, DateTime now) {
  final mins = due.difference(now).inMinutes;
  if (mins == 0) return '지금 시작';
  final abs = mins.abs();
  final h = abs ~/ 60;
  final m = abs % 60;
  final span = h > 0 ? (m > 0 ? '$h시간 $m분' : '$h시간') : '$m분';
  return mins > 0 ? '$span 후 시작' : '$span 지남';
}

// ───────────────────────── 한 줄 입력 해석 ─────────────────────────
//
//  14:00 점심약속            → 오늘 14:00
//  260918 14:00 점심약속     → 2026-09-18 14:00
//  260918 점심약속           → 2026-09-18 (시간 없음, 종일)
//  내일 오후 3:30 치과       → 내일 15:30   (오늘·내일·모레, 오전/오후 지원)
//  점심약속                  → 날짜·시간 없는 평범한 투두
//
// 맨 앞에 붙은 날짜·시간만 읽고, 나머지는 전부 제목이에요.

class ParsedInput {
  const ParsedInput({required this.title, this.date, this.minutes});

  final String title;

  /// 날짜(자정 기준). 없으면 null
  final DateTime? date;

  /// 자정부터 몇 분째인지. 없으면 null
  final int? minutes;

  bool get hasTime => minutes != null;
}

final RegExp _clockPattern = RegExp(r'^(\d{1,2}):([0-5]\d)$');
final RegExp _hourPattern = RegExp(r'^(\d{1,2})시$');

/// "14:00", "14시" → 분 단위 값. 형식이 아니면 null.
/// [bare]가 true(앞에 오전/오후가 없음)이면 "3시"처럼 애매한 1~12시는
/// 시간으로 보지 않고 제목으로 둬요. ("14:00"은 24시간제로 그대로 읽어요.)
int? _parseClock(String token, {required bool bare}) {
  final colon = _clockPattern.firstMatch(token);
  if (colon != null) {
    final h = int.parse(colon.group(1)!);
    final m = int.parse(colon.group(2)!);
    if (h > 23) return null;
    return h * 60 + m;
  }
  final hour = _hourPattern.firstMatch(token);
  if (hour != null) {
    final h = int.parse(hour.group(1)!);
    if (h > 23) return null;
    if (bare && h >= 1 && h <= 12) return null;
    return h * 60;
  }
  return null;
}

DateTime? _validDate(int y, int m, int d) {
  final date = DateTime(y, m, d);
  // 260931처럼 없는 날짜는 DateTime이 다음 달로 넘겨버리니 되돌려 확인해요.
  if (date.year != y || date.month != m || date.day != d) return null;
  return date;
}

DateTime? _parseDateToken(String token, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  if (token == '오늘') return today;
  if (token == '내일') return DateTime(today.year, today.month, today.day + 1);
  if (token == '모레') return DateTime(today.year, today.month, today.day + 2);
  if (RegExp(r'^\d{6}$').hasMatch(token)) {
    return _validDate(
      2000 + int.parse(token.substring(0, 2)),
      int.parse(token.substring(2, 4)),
      int.parse(token.substring(4, 6)),
    );
  }
  if (RegExp(r'^\d{8}$').hasMatch(token)) {
    return _validDate(
      int.parse(token.substring(0, 4)),
      int.parse(token.substring(4, 6)),
      int.parse(token.substring(6, 8)),
    );
  }
  return null;
}

/// 제목이 비어 있으면 null (추가할 수 없는 입력)
ParsedInput? parseInput(String raw, DateTime now) {
  final tokens = raw
      .trim()
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty)
      .toList();

  DateTime? date;
  int? minutes;
  var i = 0;

  while (i < tokens.length) {
    final token = tokens[i];

    if (date == null) {
      final d = _parseDateToken(token, now);
      if (d != null) {
        date = d;
        i += 1;
        continue;
      }
    }

    if (minutes == null) {
      if ((token == '오전' || token == '오후') && i + 1 < tokens.length) {
        final meridiemClock = _parseClock(tokens[i + 1], bare: false);
        if (meridiemClock != null) {
          final h = meridiemClock ~/ 60;
          if (h >= 1 && h <= 12) {
            var h24 = h % 12;
            if (token == '오후') h24 += 12;
            minutes = h24 * 60 + meridiemClock % 60;
            i += 2;
            continue;
          }
        }
      }
      final clock = _parseClock(token, bare: true);
      if (clock != null) {
        minutes = clock;
        i += 1;
        continue;
      }
    }

    break;
  }

  final title = tokens.sublist(i).join(' ');
  if (title.isEmpty) return null;
  return ParsedInput(title: title, date: date, minutes: minutes);
}

/// 입력창에서 "추가"를 눌렀을 때 오늘 화면으로 넘기는 값
class NewItemRequest {
  const NewItemRequest({
    required this.parsed,
    required this.isRoutine,
    required this.notify,
    required this.alert,
  });

  final ParsedInput parsed;
  final bool isRoutine;
  final bool notify;
  final AlertKind alert;
}

// ───────────────────────── 항목 저장소 ─────────────────────────

/// 모든 항목과 저장을 한곳에서 맡아요. 오늘·캘린더·기록 화면이 같은 데이터를 봐요.
class ItemStore extends ChangeNotifier {
  static const _storageKey = 'items_v1';

  final List<Item> items = [];
  bool loaded = false;
  bool _disposed = false;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw != null) {
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      items
        ..clear()
        ..addAll(list.map(Item.fromJson));
    }
    if (_disposed) return;
    loaded = true;
    notifyListeners();
    // 앱을 켤 때마다 예약 목록을 현재 항목에 맞게 다시 만들어요.
    Notifier.instance.rescheduleAll(items);
    // 위젯에서 체크해 둔 내용을 가져오고, 위젯에도 최신 목록을 알려줘요.
    await pullFromWidgets();
    unawaited(WidgetBridge.push(items));
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      jsonEncode(items.map((e) => e.toJson()).toList()),
    );
    // 위젯이 같은 목록을 보도록 아이폰 공유 저장소에도 적어둬요.
    unawaited(WidgetBridge.push(items));
  }

  /// 위젯에서 체크한 내용을 앱 데이터에 반영해요. 바뀐 게 있으면 true
  Future<bool> pullFromWidgets() async {
    final toggles = await WidgetBridge.takeToggles();
    if (toggles.isEmpty) return false;
    var changed = false;
    for (final t in toggles) {
      final id = t['id'];
      final day = t['day'];
      final done = t['done'] == true;
      if (id is! String || day is! String) continue;
      final found = items.where((e) => e.id == id);
      if (found.isEmpty) continue;
      final item = found.first;
      if (item.isDoneOn(day) == done) continue;
      changed = true;
      if (item.isRoutine) {
        if (done) {
          item.doneDates.add(day);
        } else {
          item.doneDates.remove(day);
        }
      } else {
        item.done = done;
        item.doneOn = done ? day : null;
        if (item.notify) {
          if (done) {
            Notifier.instance.cancel(item);
          } else {
            Notifier.instance.schedule(item);
          }
        }
      }
    }
    if (changed) {
      if (!_disposed) notifyListeners();
      await _save();
    }
    return changed;
  }

  /// 항목 내용을 바꾼 뒤 화면을 다시 그리고 저장해요.
  void update(VoidCallback change) {
    change();
    notifyListeners();
    _save();
  }

  /// 시간이 흘렀을 때(몇 분 후 문구, 자정 넘김) 화면만 다시 그려요.
  void touch() {
    if (!_disposed) notifyListeners();
  }

  /// [day] 날짜의 완료 표시를 뒤집어요. (투두는 날짜와 상관없이 완료 여부 하나뿐이에요)
  void toggle(Item item, String day) {
    HapticFeedback.selectionClick();
    update(() {
      if (item.isRoutine) {
        if (!item.doneDates.remove(day)) item.doneDates.add(day);
      } else {
        item.done = !item.done;
        item.doneOn = item.done ? dayKey(DateTime.now()) : null;
      }
    });
    // 끝낸 투두는 알림을 취소하고, 다시 되돌리면 다시 예약해요.
    if (!item.isRoutine && item.notify) {
      if (item.done) {
        Notifier.instance.cancel(item);
      } else {
        Notifier.instance.schedule(item);
      }
    }
  }

  void add(Item item) => update(() => items.add(item));

  void remove(Item item) {
    update(() => items.remove(item));
    Notifier.instance.cancel(item);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

// ───────────────────────── 아이폰 기능 연결 (위젯·결제) ─────────────────────────
//
// 위젯, 결제(하루링 PRO), 3일 체험 기간은 아이폰 자체 기능이라 Swift 쪽
// (ios/Runner/HaruNative.swift)에서 처리하고, 여기서는 말만 걸어요.

const MethodChannel _native = MethodChannel('haruring/native');

bool get _onIphone => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

class WidgetBridge {
  /// 항목 목록과 PRO 상태를 위젯이 읽는 공유 저장소에 적고, 위젯을 새로 그리게 해요.
  static Future<void> push(List<Item> items) async {
    if (!_onIphone) return;
    try {
      await _native.invokeMethod<void>('widgetSync', {
        'items': jsonEncode(items.map((e) => e.toJson()).toList()),
        'pro': jsonEncode(ProManager.instance.widgetJson()),
      });
    } catch (e) {
      debugPrint('위젯 동기화 실패: $e');
    }
  }

  /// 위젯에서 체크한 기록을 가져와요. (가져가면 비워져요)
  static Future<List<Map<String, dynamic>>> takeToggles() async {
    if (!_onIphone) return const [];
    try {
      final raw = await _native.invokeMethod<String>('takeToggles');
      if (raw == null || raw.isEmpty) return const [];
      return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('위젯 체크 기록 읽기 실패: $e');
      return const [];
    }
  }

  /// 잠긴 위젯을 눌러서 들어온 주소(haruring://pro)를 한 번만 꺼내요.
  static Future<String?> takePendingLink() async {
    if (!_onIphone) return null;
    try {
      return await _native.invokeMethod<String>('takePendingLink');
    } catch (e) {
      return null;
    }
  }
}

/// 하루링 PRO(위젯) 상태: 3일 무료 체험 + 한 번 결제.
/// 체험 시작일은 아이폰 키체인에 남아서 앱을 지웠다 깔아도 다시 체험할 수 없어요.
class ProManager extends ChangeNotifier {
  ProManager._();

  static final ProManager instance = ProManager._();

  static const int trialDays = 3;
  static const String fallbackPrice = '₩3,300';

  DateTime? trialStart;
  bool purchased = false;
  String price = fallbackPrice;
  bool busy = false;

  DateTime? get trialEnd => trialStart?.add(const Duration(days: trialDays));
  bool get trialStarted => trialStart != null;
  bool get trialActive {
    final end = trialEnd;
    return end != null && DateTime.now().isBefore(end);
  }

  bool get isPro => purchased || trialActive;

  Map<String, dynamic> widgetJson() => {
        'purchased': purchased,
        'trialStart': trialStart?.millisecondsSinceEpoch ?? 0,
        'trialEnd': trialEnd?.millisecondsSinceEpoch ?? 0,
        'price': price,
      };

  /// 구입 여부·체험 시작일을 아이폰에서 다시 읽어와요.
  Future<void> load() async {
    if (!_onIphone) return;
    try {
      final m = await _native.invokeMapMethod<String, dynamic>('proStatus');
      if (m == null) return;
      // 구입·체험 시작은 한 번 켜지면 꺼지지 않으니, 늦게 도착한 옛 응답이 덮어쓰지 못하게 해요.
      purchased = purchased || m['purchased'] == true;
      final start = m['trialStart'];
      if (start is int) trialStart = DateTime.fromMillisecondsSinceEpoch(start);
      notifyListeners();
      _loadPrice();
    } catch (e) {
      debugPrint('PRO 상태 읽기 실패: $e');
    }
  }

  /// 앱스토어에 등록된 가격을 받아와요. (상품이 없거나 느려도 화면은 기다리지 않아요)
  Future<void> _loadPrice() async {
    try {
      final p = await _native.invokeMethod<String>('productPrice');
      if (p != null && p.isNotEmpty && p != price) {
        price = p;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('가격 읽기 실패: $e');
    }
  }

  Future<void> startTrial() async {
    if (trialStarted) return;
    if (_onIphone) {
      try {
        final ms = await _native.invokeMethod<int>('startTrial');
        if (ms != null) trialStart = DateTime.fromMillisecondsSinceEpoch(ms);
      } catch (e) {
        debugPrint('체험 시작 실패: $e');
      }
    } else {
      trialStart = DateTime.now();
    }
    notifyListeners();
  }

  /// "purchased" / "cancelled" / "pending" / "error:이유"
  Future<String> buy() async {
    if (!_onIphone) return 'error:iphone';
    busy = true;
    notifyListeners();
    try {
      final r = await _native.invokeMethod<String>('purchase') ?? 'error:empty';
      if (r == 'purchased') purchased = true;
      return r;
    } on PlatformException catch (e) {
      return 'error:${e.message}';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// 예전에 한 결제를 되살려요. 복원할 구입이 있으면 true
  Future<bool> restore() async {
    if (!_onIphone) return false;
    busy = true;
    notifyListeners();
    try {
      final ok = await _native.invokeMethod<bool>('restore') ?? false;
      if (ok) purchased = true;
      return ok;
    } on PlatformException {
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}

// ───────────────────────── 항목 메뉴·추가 ─────────────────────────
//
// 오늘 화면과 캘린더 화면이 똑같이 쓰는 동작들이에요.

/// 항목을 길게 눌렀을 때 뜨는 메뉴
Future<void> showItemMenu(
  BuildContext context,
  ItemStore store,
  Item item,
) async {
  HapticFeedback.mediumImpact();
  final summary = itemSummary(item, DateTime.now());
  final hasTime = item.minutes != null;

  final action = await showCupertinoModalPopup<String>(
    context: context,
    builder: (ctx) => CupertinoActionSheet(
      title: Text(item.title),
      message: summary.isEmpty ? null : Text(summary),
      actions: [
        if (hasTime)
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(ctx, 'alert'),
            child: Text(item.notify ? '알림 시점 변경' : '알림 켜기'),
          ),
        if (hasTime && item.notify)
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(ctx, 'off'),
            child: const Text('알림 끄기'),
          ),
        CupertinoActionSheetAction(
          isDestructiveAction: true,
          onPressed: () => Navigator.pop(ctx, 'delete'),
          child: const Text('삭제'),
        ),
      ],
      cancelButton: CupertinoActionSheetAction(
        onPressed: () => Navigator.pop(ctx),
        child: const Text('취소'),
      ),
    ),
  );
  if (!context.mounted || action == null) return;

  switch (action) {
    case 'alert':
      await changeItemAlert(context, store, item);
    case 'off':
      store.update(() => item.notify = false);
      Notifier.instance.cancel(item);
    case 'delete':
      store.remove(item);
  }
}

/// 이미 만든 항목의 알림 시점 바꾸기 (처음 켤 때도 같은 시트)
Future<void> changeItemAlert(
  BuildContext context,
  ItemStore store,
  Item item,
) async {
  final minutes = item.minutes;
  if (minutes == null) return;
  final now = DateTime.now();

  final picked = await showAlertSheet(
    context,
    routine: item.isRoutine,
    minutes: minutes,
    due: item.dueAt,
    selected: item.notify ? item.alert : null,
    message: '${itemSummary(item, now, withAlert: false)} · ${item.title}',
    now: now,
  );
  if (picked == null || !context.mounted) return;

  final granted = await Notifier.instance.ensurePermission();
  if (!context.mounted) return;
  if (!granted) {
    showPermissionHelp(context);
    return;
  }

  store.update(() {
    item.alert = picked;
    item.notify = true;
  });
  Notifier.instance.schedule(item);
}

void showPermissionHelp(BuildContext context) {
  showCupertinoDialog<void>(
    context: context,
    builder: (ctx) => CupertinoAlertDialog(
      title: const Text('알림이 꺼져 있어요'),
      content: const Padding(
        padding: EdgeInsets.only(top: 6),
        child: Text('설정 > 알림에서 이 앱의 알림을 허용하면 받을 수 있어요.'),
      ),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('확인'),
        ),
      ],
    ),
  );
}

/// 아래 입력창에서 넘어온 새 항목 저장
Future<void> addItemFromInput(
  BuildContext context,
  ItemStore store,
  NewItemRequest req,
) async {
  final now = DateTime.now();
  final p = req.parsed;

  String? date;
  if (!req.isRoutine) {
    // 시간만 적었으면 오늘, 날짜도 시간도 없으면 날짜 없는 투두
    final d =
        p.date ?? (p.hasTime ? DateTime(now.year, now.month, now.day) : null);
    date = d == null ? null : dayKey(d);
  }
  final time = p.hasTime ? hhmm(p.minutes!) : null;

  // 알림을 켠 항목이면 먼저 권한을 확인해요. (처음 한 번만 iOS가 허용 여부를 물어봐요)
  var notify = req.notify && time != null;
  var denied = false;
  if (notify) {
    final granted = await Notifier.instance.ensurePermission();
    if (!granted) {
      notify = false;
      denied = true;
    }
  }
  if (!context.mounted) return;

  final item = Item(
    id: now.microsecondsSinceEpoch.toString(),
    title: p.title,
    isRoutine: req.isRoutine,
    date: date,
    time: time,
    notify: notify,
    alert: req.alert,
    created: dayKey(now),
  );
  store.add(item);
  if (notify) Notifier.instance.schedule(item);
  if (denied) showPermissionHelp(context);
}

// ───────────────────────── 앱 뼈대 (하단 탭) ─────────────────────────

class RootPage extends StatefulWidget {
  const RootPage({super.key});

  @override
  State<RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<RootPage> with WidgetsBindingObserver {
  final ItemStore _store = ItemStore();
  Timer? _ticker;
  bool _proSheetOpen = false;

  // 체험·구입 상태가 바뀌면 위젯에도 바로 알려줘요.
  void _syncWidgets() => WidgetBridge.push(_store.items);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // "2시간 40분 후" 같은 문구를 계속 맞추려고 30초마다 다시 그려요.
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) _store.touch();
    });
    ProManager.instance.addListener(_syncWidgets);
    if (_onIphone) {
      _native.setMethodCallHandler((call) async {
        switch (call.method) {
          case 'linkAvailable':
            await _checkLink();
          case 'proChanged':
            await ProManager.instance.load();
        }
        return null;
      });
    }
    // 체험 상태를 먼저 읽고, 그다음 목록을 불러와요(위젯에 둘 다 알려야 해서).
    ProManager.instance.load().then((_) => _store.load());
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkLink());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    ProManager.instance.removeListener(_syncWidgets);
    WidgetsBinding.instance.removeObserver(this);
    _store.dispose();
    super.dispose();
  }

  // 자정이 지나 앱으로 돌아왔을 때 "오늘" 기준으로 다시 그리기.
  // 위젯에서 체크한 것과 체험·결제 상태도 이때 새로 읽어요.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _store.touch();
      _store.pullFromWidgets();
      ProManager.instance.load();
      _checkLink();
    }
  }

  /// 잠긴 위젯을 눌러서 들어왔으면 PRO 화면을 열어요.
  Future<void> _checkLink() async {
    final link = await WidgetBridge.takePendingLink();
    if (link == null || !mounted) return;
    if (Uri.tryParse(link)?.host == 'pro') await _openPro();
  }

  Future<void> _openPro() async {
    if (_proSheetOpen || !mounted) return;
    _proSheetOpen = true;
    await showProSheet(context);
    _proSheetOpen = false;
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoTabScaffold(
      tabBar: CupertinoTabBar(
        // 투명하면 아래 입력창이 가려질 수 있어서 불투명한 배경을 써요.
        backgroundColor: const CupertinoDynamicColor.withBrightness(
          color: Color(0xFFF9F9F9),
          darkColor: Color(0xFF1D1D1D),
        ),
        activeColor: kAccent,
        inactiveColor: CupertinoColors.secondaryLabel,
        iconSize: 26,
        height: 56, // 기본 50보다 조금 높여서 아이콘 위쪽 여백을 만들어요.
        items: const [
          BottomNavigationBarItem(
            icon: _TabIcon(_TabGlyph.today),
            label: '오늘',
          ),
          BottomNavigationBarItem(
            icon: _TabIcon(_TabGlyph.calendar),
            label: '캘린더',
          ),
          BottomNavigationBarItem(
            icon: _TabIcon(_TabGlyph.stats),
            label: '기록',
          ),
        ],
      ),
      tabBuilder: (context, index) {
        return CupertinoTabView(
          builder: (_) => switch (index) {
            0 => TodayPage(store: _store),
            1 => CalendarPage(store: _store),
            _ => StatsPage(store: _store),
          },
        );
      },
    );
  }
}

// ───────────────────────── 탭 아이콘 ─────────────────────────

enum _TabGlyph { today, calendar, stats }

/// 탭바 아이콘. 시안과 똑같은 가는 선(1.8) 모양으로 직접 그려요.
/// 색과 크기는 탭바가 정해주는 값(선택됨 = 파랑, 아님 = 회색)을 그대로 따라가요.
class _TabIcon extends StatelessWidget {
  const _TabIcon(this.glyph);

  final _TabGlyph glyph;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    return Padding(
      // 아이콘이 탭바 윗선에 붙어 보이지 않게 위쪽 여백을 더해요.
      padding: const EdgeInsets.only(top: 4),
      child: CustomPaint(
        size: Size.square(theme.size ?? 26),
        painter: _TabIconPainter(glyph, theme.color ?? kAccent),
      ),
    );
  }
}

class _TabIconPainter extends CustomPainter {
  _TabIconPainter(this.glyph, this.color);

  final _TabGlyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24); // 24x24 도화지에 그린 걸 늘리거나 줄여요.
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    switch (glyph) {
      case _TabGlyph.today:
        canvas.drawCircle(const Offset(12, 12), 9, paint);
        canvas.drawPath(
          Path()
            ..moveTo(8, 12.5)
            ..lineTo(10.7, 15.2)
            ..lineTo(16, 9.8),
          paint,
        );
      case _TabGlyph.calendar:
        canvas.drawRRect(
          RRect.fromLTRBR(3.5, 5, 20.5, 20.5, const Radius.circular(3)),
          paint,
        );
        canvas.drawLine(const Offset(3.5, 10), const Offset(20.5, 10), paint);
        canvas.drawLine(const Offset(8, 3), const Offset(8, 7), paint);
        canvas.drawLine(const Offset(16, 3), const Offset(16, 7), paint);
      case _TabGlyph.stats:
        canvas.drawLine(const Offset(6, 20), const Offset(6, 13), paint);
        canvas.drawLine(const Offset(12, 20), const Offset(12, 5), paint);
        canvas.drawLine(const Offset(18, 20), const Offset(18, 9), paint);
    }
  }

  @override
  bool shouldRepaint(_TabIconPainter old) =>
      old.glyph != glyph || old.color != color;
}

// ───────────────────────── 오늘 화면 ─────────────────────────

class TodayPage extends StatelessWidget {
  const TodayPage({super.key, required this.store});

  final ItemStore store;

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      child: ListenableBuilder(
        listenable: store,
        builder: _buildBody,
      ),
    );
  }

  Widget _buildBody(BuildContext context, Widget? _) {
    final items = store.items;
    final now = DateTime.now();
    final today = dayKey(now);
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);

    final routines = items.where((e) => e.isRoutine).toList();

    // 오늘 시간이 정해진 투두 → 타임라인 카드
    final timed = items
        .where((e) => !e.isRoutine && e.date == today && e.time != null)
        .toList()
      ..sort((a, b) => a.minutes!.compareTo(b.minutes!));

    // 앞으로 예정된 투두
    final upcoming = items
        .where((e) =>
            !e.isRoutine && e.date != null && e.date!.compareTo(today) > 0)
        .toList()
      ..sort((a, b) => '${a.date} ${a.time ?? '00:00'}'
          .compareTo('${b.date} ${b.time ?? '00:00'}'));

    // 그 외 투두: 날짜 없음 + 오늘(시간 없음) + 못 끝낸 지난 날짜
    // (지난 날짜에 끝낸 일은 오늘 화면에 안 나오고 캘린더에서만 봐요)
    final todos = items
        .where((e) =>
            !e.isRoutine &&
            !(e.date == today && e.time != null) &&
            (e.date == null ||
                e.date == today ||
                (e.date!.compareTo(today) < 0 && !e.done)))
        .toList();

    final routineDone = routines.where((e) => e.isDoneOn(today)).length;
    final todoDone = todos.where((e) => e.isDoneOn(today)).length;

    return Column(
      children: [
        Expanded(
          child: CustomScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              CupertinoSliverNavigationBar(
                largeTitle: const Text('오늘'),
                trailing: const _ProNavButton(),
                backgroundColor: CupertinoColors.systemGroupedBackground,
              ),
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 2, 20, 12),
                      child: Text(
                        '${now.month}월 ${now.day}일 ${kWeekdays[now.weekday - 1]}요일',
                        style: TextStyle(fontSize: 12, color: secondary),
                      ),
                    ),
                    if (!store.loaded)
                      const Padding(
                        padding: EdgeInsets.only(top: 80),
                        child: Center(child: CupertinoActivityIndicator()),
                      )
                    else if (items.isEmpty)
                      _buildEmpty(context)
                    else ...[
                      if (timed.isNotEmpty)
                        _TimelineCard(
                          timed: timed,
                          now: now,
                          onToggle: (item) => store.toggle(item, today),
                          onMenu: (item) => showItemMenu(context, store, item),
                        ),
                      if (routines.isNotEmpty)
                        _Section(
                          header: '루틴 · $routineDone/${routines.length}',
                          children: [
                            for (final item in routines)
                              _ItemRow(store: store, item: item, now: now),
                          ],
                        ),
                      if (todos.isNotEmpty)
                        _Section(
                          header: '투두 · $todoDone/${todos.length}',
                          children: [
                            for (final item in todos)
                              _ItemRow(store: store, item: item, now: now),
                          ],
                        ),
                      if (upcoming.isNotEmpty)
                        _Section(
                          header: '예정 · ${upcoming.length}',
                          children: [
                            for (final item in upcoming)
                              _ItemRow(store: store, item: item, now: now),
                          ],
                        ),
                    ],
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
        ),
        // 아래 탭바가 이미 화면 아래 여백을 차지하고 있어서 입력창은 여백을 또 넣지 않아요.
        MediaQuery.removePadding(
          context: context,
          removeBottom: true,
          child: _InputBar(
            onSubmit: (req) => addItemFromInput(context, store, req),
          ),
        ),
      ],
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 32),
      child: Center(
        child: Column(
          children: [
            Icon(
              CupertinoIcons.checkmark_circle,
              size: 56,
              color: CupertinoColors.systemGrey3.resolveFrom(context),
            ),
            const SizedBox(height: 14),
            const Text(
              '아직 비어 있어요',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              '아래 입력창에 한 줄로 적어보세요\n예) 14:00 점심약속',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: secondary),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── 목록 한 줄 ─────────────────────────

/// 오늘 화면과 캘린더 화면의 목록에 쓰는 한 줄.
/// 탭하면 완료, 길게 누르면 메뉴, 왼쪽으로 밀면 삭제예요.
class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.store,
    required this.item,
    required this.now,
    this.day,
    this.inCalendar = false,
  });

  final ItemStore store;
  final Item item;
  final DateTime now;

  /// 보고 있는 날짜 ('yyyy-MM-dd'). 비우면 오늘이에요.
  final String? day;

  /// 캘린더 목록에서는 날짜·연속 일수 없이 시간만 보여줘요.
  final bool inCalendar;

  @override
  Widget build(BuildContext context) {
    final today = dayKey(now);
    final shown = day ?? today;
    final done = item.isDoneOn(shown);
    final streak = (item.isRoutine && !inCalendar) ? streakOf(item, now) : 0;
    final doneColor = CupertinoColors.secondaryLabel.resolveFrom(context);
    final deep = CupertinoDynamicColor.resolve(kAccentDeep, context);

    // 보조 문구: 루틴은 "오후 9:00 · 3일 연속",
    // 다른 날짜 투두는 "9월 18일 (금) · 오후 2:00"
    final parts = <String>[];
    if (item.isRoutine) {
      if (item.minutes != null) parts.add(clockLabel(item.minutes!));
      if (streak > 0) parts.add('$streak일 연속');
    } else {
      final d = parseDayKey(item.date);
      if (!inCalendar && d != null && item.date != today) {
        parts.add(dateLabel(d, now));
      }
      if (item.minutes != null) parts.add(clockLabel(item.minutes!));
    }

    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: CupertinoColors.systemRed,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 22),
        child: const Icon(CupertinoIcons.delete, color: CupertinoColors.white),
      ),
      onDismissed: (_) {
        HapticFeedback.mediumImpact();
        store.remove(item);
      },
      child: GestureDetector(
        onLongPress: () => showItemMenu(context, store, item),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 46),
          child: CupertinoListTile(
            onTap: () => store.toggle(item, shown),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            leadingSize: 18,
            leadingToTitle: 14,
            leading: _CheckCircle(checked: done),
            title: Row(
              children: [
                // 루틴은 매일 반복된다는 표시를 제목 맨 앞에 붙여요
                if (item.isRoutine) ...[
                  Icon(CupertinoIcons.repeat, size: 14, color: deep),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(
                    item.title,
                    overflow: TextOverflow.ellipsis,
                    style: _font(14, FontWeight.w400, letterSpacing: -0.2)
                        .copyWith(
                      decoration: done ? TextDecoration.lineThrough : null,
                      color: done
                          ? doneColor
                          : CupertinoColors.label.resolveFrom(context),
                    ),
                  ),
                ),
              ],
            ),
            // 보조 문구(연속 일수, 날짜·시간)는 모두 오른쪽에 12px로 붙여요.
            additionalInfo: parts.isNotEmpty
                ? Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (streak >= kFlameStreak) ...[
                          const _FlameIcon(size: 14),
                          const SizedBox(width: 3),
                        ],
                        Text(
                          parts.join(' · '),
                          style: _font(12, FontWeight.w400)
                              .copyWith(color: doneColor),
                        ),
                      ],
                    ),
                  )
                : null,
            trailing: item.notify
                ? Icon(CupertinoIcons.bell_fill, size: 13, color: deep)
                : null,
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── 연속 달성 불꽃 ─────────────────────────

/// 이 일수 이상 연속이면 루틴 줄에 불꽃이 붙어요. 바꾸고 싶으면 여기만 수정하면 돼요.
const int kFlameStreak = 7;

/// 7일 이상 연속일 때 붙는 작은 불꽃. 다홍 몸통 + 노란 속불꽃.
class _FlameIcon extends StatelessWidget {
  const _FlameIcon({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: const CustomPaint(painter: _FlamePainter()),
    );
  }
}

class _FlamePainter extends CustomPainter {
  const _FlamePainter();

  static const Color _body = Color(0xFFFF4A2E);
  static const Color _core = Color(0xFFFFBE55);

  @override
  void paint(Canvas canvas, Size size) {
    // 24 x 24 도화지에 그린 모양을 크기에 맞게 늘이고 줄여요.
    canvas.scale(size.width / 24);

    final outer = Path()
      ..moveTo(13, 3)
      ..cubicTo(13.3, 5.6, 18.6, 8.4, 18.6, 14.2)
      ..cubicTo(18.6, 18.2, 15.8, 21.2, 12, 21.2)
      ..cubicTo(8.2, 21.2, 5.4, 18.4, 5.4, 14.8)
      ..cubicTo(5.4, 12.6, 6.4, 11, 7.8, 9.9)
      ..cubicTo(8, 11.4, 8.7, 12.3, 9.6, 12.6)
      ..cubicTo(9.4, 8.8, 10.6, 5.2, 13, 3)
      ..close();

    final core = Path()
      ..moveTo(12.1, 12.4)
      ..cubicTo(13.3, 14, 14.7, 15.2, 14.7, 17)
      ..cubicTo(14.7, 18.6, 13.6, 19.7, 12.1, 19.7)
      ..cubicTo(10.6, 19.7, 9.5, 18.6, 9.5, 17.1)
      ..cubicTo(9.5, 15.4, 11, 14.2, 12.1, 12.4)
      ..close();

    _paintRounded(canvas, outer, _body, 1.8);
    _paintRounded(canvas, core, _core, 1.0);
  }

  /// 채우고 같은 색으로 테두리를 둘러서 뾰족한 끝을 동글게 만들어요.
  void _paintRounded(Canvas canvas, Path path, Color color, double stroke) {
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ───────────────────────── 체크 원형 버튼 ─────────────────────────

class _CheckCircle extends StatelessWidget {
  const _CheckCircle({required this.checked});

  final bool checked;

  @override
  Widget build(BuildContext context) {
    final accent = CupertinoDynamicColor.resolve(
      CupertinoTheme.of(context).primaryColor,
      context,
    );
    final idle = CupertinoColors.systemGrey.resolveFrom(context);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: checked ? accent : const Color(0x00000000),
        border: Border.all(color: checked ? accent : idle, width: 1.5),
      ),
      child: checked
          ? const Icon(
              CupertinoIcons.check_mark,
              size: 11,
              color: CupertinoColors.white,
            )
          : null,
    );
  }
}

// ───────────────────────── 타임라인 카드 ─────────────────────────

enum _DotState { done, next, later }

class _TimelineCard extends StatelessWidget {
  const _TimelineCard({
    required this.timed,
    required this.now,
    required this.onToggle,
    required this.onMenu,
  });

  final List<Item> timed;
  final DateTime now;
  final void Function(Item) onToggle;
  final void Function(Item) onMenu;

  @override
  Widget build(BuildContext context) {
    final cardColor =
        CupertinoColors.secondarySystemGroupedBackground.resolveFrom(context);
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final deep = CupertinoDynamicColor.resolve(kAccentDeep, context);
    final soft = CupertinoDynamicColor.resolve(kAccentSoft, context);

    // 다음 일정 = 아직 안 한 것 중 가장 이른 것 (시간이 지났어도 "N분 지남"으로 보여줘요)
    Item? next;
    for (final it in timed) {
      if (!it.done) {
        next = it;
        break;
      }
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(kCardRadius),
        boxShadow: kCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: soft,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              next == null ? '오늘 일정 끝' : '다음 일정',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: deep,
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (next != null) ...[
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: const BoxDecoration(
                    color: kAccent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    next.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _font(17, FontWeight.w700, letterSpacing: -0.3)
                        .copyWith(
                      color: CupertinoColors.label.resolveFrom(context),
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 22, top: 2),
              child: Text(
                untilLabel(next.dueAt!, now),
                style: TextStyle(fontSize: 12, color: secondary),
              ),
            ),
          ] else
            Text(
              '시간이 정해진 일정을 모두 끝냈어요',
              style: TextStyle(fontSize: 12, color: secondary),
            ),
          const SizedBox(height: 12),
          for (var i = 0; i < timed.length; i++)
            _TimelineRow(
              item: timed[i],
              isFirst: i == 0,
              isLast: i == timed.length - 1,
              isNext: identical(timed[i], next),
              onTap: () => onToggle(timed[i]),
              onLongPress: () => onMenu(timed[i]),
            ),
        ],
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.item,
    required this.isFirst,
    required this.isLast,
    required this.isNext,
    required this.onTap,
    required this.onLongPress,
  });

  final Item item;
  final bool isFirst;
  final bool isLast;
  final bool isNext;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  static const double _rowHeight = 38;
  static const double _dot = 18;

  @override
  Widget build(BuildContext context) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final deep = CupertinoDynamicColor.resolve(kAccentDeep, context);
    final line = CupertinoColors.separator.resolveFrom(context);
    final done = item.done;
    final highlight = isNext && !done;

    final state = done
        ? _DotState.done
        : (isNext ? _DotState.next : _DotState.later);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
      child: SizedBox(
        height: _rowHeight,
        child: Stack(
          alignment: Alignment.centerLeft,
          children: [
            // 점과 점을 잇는 세로선 (첫 줄은 점 아래부터, 마지막 줄은 점 위까지)
            Positioned(
              left: _dot / 2 - 1,
              width: 2,
              top: isFirst ? _rowHeight / 2 : 0,
              bottom: isLast ? _rowHeight / 2 : 0,
              child: ColoredBox(color: line),
            ),
            Row(
              children: [
                _TimelineDot(state: state),
                const SizedBox(width: 12),
                SizedBox(
                  width: 62,
                  child: Text(
                    clockLabel(item.minutes!),
                    style: _font(
                      12,
                      highlight ? FontWeight.w600 : FontWeight.w400,
                    ).copyWith(color: highlight ? deep : secondary),
                  ),
                ),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _font(
                            14,
                            highlight ? FontWeight.w700 : FontWeight.w400,
                            letterSpacing: -0.2,
                          ).copyWith(
                            color: done
                                ? secondary
                                : (highlight
                                    ? deep
                                    : CupertinoColors.label.resolveFrom(context)),
                            decoration: done ? TextDecoration.lineThrough : null,
                          ),
                        ),
                      ),
                      if (item.notify) ...[
                        const SizedBox(width: 6),
                        Icon(CupertinoIcons.bell_fill, size: 12, color: deep),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TimelineDot extends StatelessWidget {
  const _TimelineDot({required this.state});

  final _DotState state;

  @override
  Widget build(BuildContext context) {
    final bg =
        CupertinoColors.secondarySystemGroupedBackground.resolveFrom(context);
    final idle = CupertinoColors.systemGrey.resolveFrom(context);

    if (state == _DotState.done) {
      return Container(
        width: 18,
        height: 18,
        decoration: const BoxDecoration(
          color: kAccent,
          shape: BoxShape.circle,
        ),
        child: const Icon(
          CupertinoIcons.check_mark,
          size: 11,
          color: CupertinoColors.white,
        ),
      );
    }
    if (state == _DotState.next) {
      return Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color: bg,
          shape: BoxShape.circle,
          border: Border.all(color: kAccent, width: 2),
        ),
      );
    }
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: Border.all(color: idle, width: 1.5),
      ),
    );
  }
}

// ───────────────────────── 아래 한 줄 입력창 ─────────────────────────
//
//  [종] [투두/루틴] [ 14:00 점심약속        ] [↑]
//
//  · 종: 시간이 들어가면 자동으로 켜지고, 눌러서 끌 수 있어요. (알림 예약은 다음 단계)
//  · 칩: 눌러서 투두 ↔ 루틴 전환
//  · 입력창 위 미리보기: 어떻게 해석됐는지 바로 보여줘요.

class _InputBar extends StatefulWidget {
  const _InputBar({required this.onSubmit});

  final void Function(NewItemRequest) onSubmit;

  @override
  State<_InputBar> createState() => _InputBarState();
}

class _AlertState {
  const _AlertState(this.on, this.kind);

  /// 지금 입력에 알림이 켜져 있는지
  final bool on;

  /// 실제로 쓰이는 알림 시점 (쓸 수 있는 시점이 없으면 null)
  final AlertKind? kind;
}

class _InputBarState extends State<_InputBar> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();

  bool _routine = false;

  /// null = 자동(시간이 있으면 켜짐), false = 직접 끔, true = 직접 켬
  bool? _bellOverride;

  /// 사용자가 고른 알림 시점 (그 시점을 쓸 수 없으면 정각으로 대신해요)
  AlertKind _alert = AlertKind.at;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// 입력 내용과 지금 시각으로 알림 상태를 계산해요.
  _AlertState _alertFor(ParsedInput? parsed, DateTime now) {
    if (parsed == null || !parsed.hasTime) return const _AlertState(false, null);

    final due = dueOf(parsed, now);
    bool usable(AlertKind k) => alertAvailable(
          k,
          routine: _routine,
          minutes: parsed.minutes,
          due: due,
          now: now,
        );

    AlertKind? kind;
    if (usable(_alert)) {
      kind = _alert;
    } else if (usable(AlertKind.at)) {
      kind = AlertKind.at;
    }
    return _AlertState(kind != null && _bellOverride != false, kind);
  }

  void _toggleBell(ParsedInput? parsed) {
    final state = _alertFor(parsed, DateTime.now());
    // 시간이 없거나 쓸 수 있는 시점이 없으면 알림도 없어요.
    if (state.kind == null) return;
    HapticFeedback.selectionClick();
    setState(() => _bellOverride = !state.on);
  }

  String _sheetMessage(ParsedInput p, DateTime now) {
    final String when;
    if (_routine) {
      when = '매일 · ${clockLabel(p.minutes!)}';
    } else {
      final d = p.date;
      when = '${d == null ? '오늘' : dateLabel(d, now)} · ${clockLabel(p.minutes!)}';
    }
    return '$when · ${p.title}';
  }

  /// 종을 길게 누르거나 칩의 시점 버튼을 누르면 뜨는 시트
  Future<void> _pickAlert(ParsedInput? parsed) async {
    if (parsed == null || !parsed.hasTime) return;
    final now = DateTime.now();
    final state = _alertFor(parsed, now);
    HapticFeedback.mediumImpact();

    final picked = await showAlertSheet(
      context,
      routine: _routine,
      minutes: parsed.minutes!,
      due: dueOf(parsed, now),
      selected: state.on ? state.kind : null,
      message: _sheetMessage(parsed, now),
      now: now,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _alert = picked;
      _bellOverride = true;
    });
  }

  void _toggleMode() {
    HapticFeedback.selectionClick();
    setState(() => _routine = !_routine);
  }

  void _submit() {
    final now = DateTime.now();
    final parsed = parseInput(_controller.text, now);
    if (parsed == null) return;
    final state = _alertFor(parsed, now);
    widget.onSubmit(NewItemRequest(
      parsed: parsed,
      isRoutine: _routine,
      notify: state.on,
      alert: state.kind ?? AlertKind.at,
    ));
    HapticFeedback.lightImpact();
    _controller.clear();
    setState(() {
      _bellOverride = null;
      _alert = AlertKind.at;
    });
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final text = _controller.text;
    final parsed = parseInput(text, now);
    final state = _alertFor(parsed, now);

    // 미리보기는 날짜·시간이 들어갔거나 루틴 모드일 때만 보여줘요.
    final chipParsed =
        (parsed != null && (_routine || parsed.date != null || parsed.hasTime))
            ? parsed
            : null;

    final bg = CupertinoColors.systemGroupedBackground.resolveFrom(context);
    final pillColor =
        CupertinoColors.secondarySystemGroupedBackground.resolveFrom(context);
    final separator = CupertinoColors.separator.resolveFrom(context);

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: bg.withAlpha(240),
            border: Border(top: BorderSide(color: separator, width: 0.5)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedSize(
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOut,
                    alignment: Alignment.bottomLeft,
                    child: (chipParsed == null)
                        ? const SizedBox(width: double.infinity)
                        : Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _PreviewChip(
                              parsed: chipParsed,
                              routine: _routine,
                              alertLabel: state.on
                                  ? state.kind!.labelFor(_routine)
                                  : null,
                              onAlertTap: () => _pickAlert(parsed),
                              now: now,
                            ),
                          ),
                  ),
                  Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 7),
                    decoration: BoxDecoration(
                      color: pillColor,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: separator, width: 0.5),
                    ),
                    child: Row(
                      children: [
                        _BellButton(
                          on: state.on,
                          onTap: () => _toggleBell(parsed),
                          onLongPress: () => _pickAlert(parsed),
                        ),
                        const SizedBox(width: 8),
                        _ModeChip(routine: _routine, onTap: _toggleMode),
                        const SizedBox(width: 8),
                        Expanded(
                          child: CupertinoTextField(
                            controller: _controller,
                            focusNode: _focus,
                            placeholder:
                                _routine ? '예: 21:00 책 10쪽 읽기' : '예: 14:00 점심약속',
                            decoration: null,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            textInputAction: TextInputAction.done,
                            // 기본 동작은 키보드를 내려버려서, 직접 처리해 계속 입력할 수 있게 해요.
                            onEditingComplete: _submit,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _SendButton(enabled: parsed != null, onTap: _submit),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PreviewChip extends StatelessWidget {
  const _PreviewChip({
    required this.parsed,
    required this.routine,
    required this.alertLabel,
    required this.onAlertTap,
    required this.now,
  });

  final ParsedInput parsed;
  final bool routine;

  /// 알림이 켜져 있으면 "정각", "1시간 전" 같은 시점 이름. 꺼져 있으면 null
  final String? alertLabel;
  final VoidCallback onAlertTap;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final deep = CupertinoDynamicColor.resolve(kAccentDeep, context);
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final cardColor =
        CupertinoColors.secondarySystemGroupedBackground.resolveFrom(context);
    final warnColor = CupertinoColors.systemOrange.resolveFrom(context);

    String when;
    var warn = false;
    if (routine) {
      when = parsed.hasTime ? '매일 · ${clockLabel(parsed.minutes!)}' : '매일';
    } else {
      final today = DateTime(now.year, now.month, now.day);
      final d = parsed.date;
      final timeText = parsed.hasTime
          ? clockLabel(parsed.minutes!)
          : (d == null ? '시간 없음' : '종일');
      if (d == null) {
        when = '오늘 · $timeText';
      } else {
        warn = d.isBefore(today);
        final label = dateLabel(d, now);
        when = warn ? '지난 날짜 · $label · $timeText' : '$label · $timeText';
      }
    }

    final color = warn ? warnColor : deep;
    final hasPill = alertLabel != null;

    return Container(
      padding: hasPill
          ? const EdgeInsets.fromLTRB(14, 6, 6, 6)
          : const EdgeInsets.fromLTRB(14, 9, 14, 9),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F1E3250),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            routine ? CupertinoIcons.repeat : CupertinoIcons.clock,
            size: 15,
            color: color,
          ),
          const SizedBox(width: 8),
          Text(
            when,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              parsed.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: secondary),
            ),
          ),
          if (alertLabel != null) ...[
            const SizedBox(width: 8),
            _AlertPill(label: alertLabel!, onTap: onAlertTap),
          ],
        ],
      ),
    );
  }
}

/// 칩 끝의 "🔔 정각 ⌄" 버튼. 누르면 알림 시점 시트가 떠요.
class _AlertPill extends StatelessWidget {
  const _AlertPill({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final deep = CupertinoDynamicColor.resolve(kAccentDeep, context);
    final soft = CupertinoDynamicColor.resolve(kAccentSoft, context);

    return Semantics(
      button: true,
      label: '알림 시점 $label, 눌러서 바꾸기',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 24,
          padding: const EdgeInsets.fromLTRB(8, 0, 6, 0),
          decoration: BoxDecoration(
            color: soft,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(CupertinoIcons.bell_fill, size: 12, color: deep),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: deep,
                ),
              ),
              const SizedBox(width: 3),
              Icon(CupertinoIcons.chevron_down, size: 10, color: deep),
            ],
          ),
        ),
      ),
    );
  }
}

class _BellButton extends StatelessWidget {
  const _BellButton({
    required this.on,
    required this.onTap,
    required this.onLongPress,
  });

  final bool on;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final deep = CupertinoDynamicColor.resolve(kAccentDeep, context);
    final soft = CupertinoDynamicColor.resolve(kAccentSoft, context);
    final off = CupertinoColors.secondaryLabel.resolveFrom(context);
    final offBg = CupertinoColors.systemGrey6.resolveFrom(context);

    return Semantics(
      button: true,
      label: on ? '알림 켜짐, 눌러서 끄기, 길게 눌러서 시점 바꾸기' : '알림 꺼짐',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: on ? soft : offBg,
          ),
          child: Icon(
            on ? CupertinoIcons.bell_fill : CupertinoIcons.bell_slash,
            size: 16,
            color: on ? deep : off,
          ),
        ),
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({required this.routine, required this.onTap});

  final bool routine;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final deep = CupertinoDynamicColor.resolve(kAccentDeep, context);
    final soft = CupertinoDynamicColor.resolve(kAccentSoft, context);
    final fg = routine ? CupertinoColors.white : deep;

    return Semantics(
      button: true,
      label: routine ? '루틴, 눌러서 투두로 바꾸기' : '투두, 눌러서 루틴으로 바꾸기',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 30,
          padding: const EdgeInsets.fromLTRB(12, 0, 9, 0),
          decoration: BoxDecoration(
            color: routine ? deep : soft,
            borderRadius: BorderRadius.circular(15),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                routine ? '루틴' : '투두',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
              const SizedBox(width: 4),
              Icon(CupertinoIcons.chevron_up_chevron_down, size: 11, color: fg),
            ],
          ),
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: '추가',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: enabled ? kAccent : kAccent.withAlpha(90),
          ),
          child: const Icon(
            CupertinoIcons.arrow_up,
            size: 16,
            color: CupertinoColors.white,
          ),
        ),
      ),
    );
  }
}


// ───────────────────────── 알림 시점 ─────────────────────────
//
//  정각 · 10분 전 · 1시간 전 · 당일 아침(8시) · 전날 저녁(8시)
//
//  · 투두는 "그 일정의 시각"을 기준으로 한 번만 울려요.
//  · 루틴은 "매일 그 시각"을 기준으로 매일 울려요. (전날 저녁은 루틴에선 안 써요)
//  · 이미 지난 시각이거나 일정보다 늦는 시점은 고를 수 없어요.

enum AlertKind { at, min10, hour1, morning, eve }

const int kMorningMinutes = 8 * 60;
const int kEveningMinutes = 20 * 60;

AlertKind alertFromName(String? name) {
  for (final k in AlertKind.values) {
    if (k.name == name) return k;
  }
  return AlertKind.at;
}

extension AlertKindLabel on AlertKind {
  String labelFor(bool routine) {
    return switch (this) {
      AlertKind.at => '정각',
      AlertKind.min10 => '10분 전',
      AlertKind.hour1 => '1시간 전',
      AlertKind.morning => routine ? '매일 아침' : '당일 아침',
      AlertKind.eve => '전날 저녁',
    };
  }
}

/// 투두: 알림이 울릴 시각. 보낼 수 없는 시점(이미 지남 등)이면 null.
DateTime? todoAlertTime(AlertKind kind, DateTime due, DateTime now) {
  final fire = switch (kind) {
    AlertKind.at => due,
    AlertKind.min10 => due.subtract(const Duration(minutes: 10)),
    AlertKind.hour1 => due.subtract(const Duration(hours: 1)),
    AlertKind.morning => DateTime(due.year, due.month, due.day, 8),
    AlertKind.eve => DateTime(due.year, due.month, due.day - 1, 20),
  };
  // 아침 알림은 일정이 아침 8시보다 늦어야 의미가 있어요.
  if (kind == AlertKind.morning && !fire.isBefore(due)) return null;
  if (!fire.isAfter(now)) return null;
  return fire;
}

/// 루틴: 매일 알림이 울릴 시각(자정부터 몇 분째). 쓸 수 없으면 null.
int? routineAlertMinutes(AlertKind kind, int minutes) {
  switch (kind) {
    case AlertKind.at:
      return minutes;
    case AlertKind.min10:
      return (minutes - 10) % 1440;
    case AlertKind.hour1:
      return (minutes - 60) % 1440;
    case AlertKind.morning:
      return minutes > kMorningMinutes ? kMorningMinutes : null;
    case AlertKind.eve:
      return null;
  }
}

bool alertAvailable(
  AlertKind kind, {
  required bool routine,
  required int? minutes,
  required DateTime? due,
  required DateTime now,
}) {
  if (minutes == null) return false;
  if (routine) return routineAlertMinutes(kind, minutes) != null;
  return due != null && todoAlertTime(kind, due, now) != null;
}

/// 입력한 투두의 예정 시각 (시간이 없으면 null)
DateTime? dueOf(ParsedInput p, DateTime now) {
  final m = p.minutes;
  if (m == null) return null;
  final d = p.date ?? DateTime(now.year, now.month, now.day);
  return DateTime(d.year, d.month, d.day, m ~/ 60, m % 60);
}

/// "오늘 · 오후 2:00 · 알림 정각" 같은 한 줄 요약
String itemSummary(Item item, DateTime now, {bool withAlert = true}) {
  final parts = <String>[];
  if (item.isRoutine) {
    parts.add('매일');
  } else {
    final d = parseDayKey(item.date);
    if (d != null) parts.add(dateLabel(d, now));
  }
  final m = item.minutes;
  if (m != null) {
    parts.add(clockLabel(m));
    if (withAlert) {
      parts.add(item.notify ? '알림 ${item.alert.labelFor(item.isRoutine)}' : '알림 없음');
    }
  }
  return parts.join(' · ');
}

String alertBody(Item item) {
  final when = clockLabel(item.minutes!);
  return switch (item.alert) {
    AlertKind.at => '지금 시작할 시간이에요',
    AlertKind.min10 => '10분 뒤 시작해요 · $when',
    AlertKind.hour1 => '1시간 뒤 시작해요 · $when',
    AlertKind.morning => '오늘 $when에 있어요',
    AlertKind.eve => '내일 $when에 있어요',
  };
}

/// 알림 시점을 고르는 시트. 고른 시점을 돌려주고, 취소하면 null.
Future<AlertKind?> showAlertSheet(
  BuildContext context, {
  required bool routine,
  required int minutes,
  required DateTime? due,
  required AlertKind? selected,
  required String message,
  required DateTime now,
}) {
  final kinds = routine
      ? const [
          AlertKind.at,
          AlertKind.min10,
          AlertKind.hour1,
          AlertKind.morning,
        ]
      : AlertKind.values;

  return showCupertinoModalPopup<AlertKind>(
    context: context,
    builder: (ctx) {
      final deep = CupertinoDynamicColor.resolve(kAccentDeep, ctx);
      final primary = CupertinoColors.label.resolveFrom(ctx);
      final secondary = CupertinoColors.secondaryLabel.resolveFrom(ctx);
      final disabledColor = CupertinoColors.tertiaryLabel.resolveFrom(ctx);

      Widget row(AlertKind k) {
        final isSelected = k == selected;

        // 이 시점으로 하면 실제로 울리는 시각 (null이면 선택 불가)
        String? when;
        if (routine) {
          final m = routineAlertMinutes(k, minutes);
          if (m != null) when = '매일 ${clockLabel(m)}';
        } else if (due != null) {
          final fire = todoAlertTime(k, due, now);
          if (fire != null) {
            when =
                '${dateLabel(fire, now)} ${clockLabel(fire.hour * 60 + fire.minute)}';
          }
        }
        final enabled = when != null;

        return CupertinoActionSheetAction(
          onPressed: enabled ? () => Navigator.pop(ctx, k) : () {},
          child: Row(
            children: [
              Expanded(
                child: Text(
                  k.labelFor(routine),
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: !enabled ? disabledColor : (isSelected ? deep : primary),
                  ),
                ),
              ),
              Text(
                when ?? '선택 불가',
                style: TextStyle(
                  fontSize: 15,
                  color: enabled ? secondary : disabledColor,
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 20,
                child: isSelected
                    ? Icon(CupertinoIcons.check_mark, size: 18, color: deep)
                    : null,
              ),
            ],
          ),
        );
      }

      return CupertinoActionSheet(
        title: const Text('알림 시점'),
        message: Text(message),
        actions: [for (final k in kinds) row(k)],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('취소'),
        ),
      );
    },
  );
}

// ───────────────────────── 알림 예약 ─────────────────────────

class Notifier {
  Notifier._();

  static final Notifier instance = Notifier._();

  late final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  Future<void> init() async {
    // 웹 미리보기에서는 알림을 쓰지 않아요. (_ready가 false라서 다른 함수도 그냥 지나가요)
    if (kIsWeb) return;
    try {
      tzdata.initializeTimeZones();
      try {
        final info = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(info.identifier));
      } catch (e) {
        debugPrint('시간대를 못 찾았어요(일회성 알림은 그대로 동작해요): $e');
      }

      // 권한 창은 첫 알림을 켤 때 띄우려고, 시작할 때는 요청하지 않아요.
      final darwin = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      await _plugin.initialize(
        settings: InitializationSettings(iOS: darwin),
      );
      _ready = true;
    } catch (e) {
      debugPrint('알림을 준비하지 못했어요: $e');
    }
  }

  /// 알림 권한이 있는지 확인하고, 아직 안 물어봤다면 iOS 허용 창을 띄워요.
  Future<bool> ensurePermission() async {
    if (!_ready) return false;
    try {
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      if (ios == null) return false; // 지금은 iOS만 지원해요
      final granted = await ios.requestPermissions(
        alert: true,
        badge: false,
        sound: true,
      );
      return granted ?? false;
    } catch (e) {
      debugPrint('알림 권한 확인 실패: $e');
      return false;
    }
  }

  // 알림 id는 32비트 정수여야 해서 항목 id(마이크로초)를 줄여서 써요.
  int _idOf(Item item) =>
      (int.tryParse(item.id) ?? item.id.hashCode) % 2147483647;

  Future<void> cancel(Item item) async {
    if (!_ready) return;
    try {
      await _plugin.cancel(id: _idOf(item));
    } catch (e) {
      debugPrint('알림 취소 실패: $e');
    }
  }

  /// 항목의 알림을 (다시) 예약해요. 알림이 꺼져 있거나 이미 지난 시각이면 예약하지 않아요.
  Future<void> schedule(Item item) async {
    if (!_ready) return;
    await cancel(item);
    if (!item.notify || (!item.isRoutine && item.done)) return;
    final minutes = item.minutes;
    if (minutes == null) return;

    final now = DateTime.now();
    try {
      if (item.isRoutine) {
        final fireMin = routineAlertMinutes(item.alert, minutes);
        if (fireMin == null) return;
        var first = DateTime(
            now.year, now.month, now.day, fireMin ~/ 60, fireMin % 60);
        if (!first.isAfter(now)) {
          first = DateTime(
              now.year, now.month, now.day + 1, fireMin ~/ 60, fireMin % 60);
        }
        await _zoned(item, first, repeatDaily: true);
      } else {
        final due = item.dueAt;
        if (due == null) return;
        final fire = todoAlertTime(item.alert, due, now);
        if (fire == null) return;
        await _zoned(item, fire, repeatDaily: false);
      }
    } catch (e) {
      debugPrint('알림 예약 실패: $e');
    }
  }

  Future<void> _zoned(
    Item item,
    DateTime when, {
    required bool repeatDaily,
  }) {
    return _plugin.zonedSchedule(
      id: _idOf(item),
      scheduledDate: tz.TZDateTime.from(when, tz.local),
      notificationDetails: NotificationDetails(
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      title: item.title,
      body: alertBody(item),
      matchDateTimeComponents: repeatDaily ? DateTimeComponents.time : null,
    );
  }

  /// 예약 목록을 현재 항목에 맞게 처음부터 다시 만들어요.
  Future<void> rescheduleAll(List<Item> items) async {
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
    } catch (e) {
      debugPrint('알림 초기화 실패: $e');
    }
    for (final item in items) {
      if (item.notify) await schedule(item);
    }
  }
}


// ───────────────────────── 카드 공통 ─────────────────────────

/// 타임라인 카드와 목록 카드가 모두 같은 모서리 둥글기를 쓰도록 한곳에 모아뒀어요.
const double kCardRadius = 22;

/// 타임라인 카드와 목록 카드가 모두 같은 그림자를 쓰도록 한곳에 모아뒀어요.
/// 그림자를 없애거나 바꾸고 싶으면 여기만 고치면 돼요.
const List<BoxShadow> kCardShadow = [
  BoxShadow(color: Color(0x0F000000), blurRadius: 2, offset: Offset(0, 1)),
  BoxShadow(color: Color(0x141E3250), blurRadius: 18, offset: Offset(0, 6)),
];

/// 제목 + 둥근 흰 카드 안에 줄이 쌓인 목록 묶음.
/// (CupertinoListSection은 그림자가 카드 밖에서 잘려서 직접 만들었어요.)
class _Section extends StatelessWidget {
  const _Section({
    required this.header,
    required this.children,
    this.indent = 48,
  });

  final String header;
  final List<Widget> children;

  /// 줄 사이 구분선이 시작하는 위치 (기본은 체크 동그라미 오른쪽)
  final double indent;

  @override
  Widget build(BuildContext context) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final card =
        CupertinoColors.secondarySystemGroupedBackground.resolveFrom(context);
    final line = CupertinoColors.separator.resolveFrom(context);

    // 줄 사이 구분선: 체크 동그라미(18) + 간격(14) + 왼쪽 여백(16) = 48부터 시작
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(Container(
          margin: EdgeInsetsDirectional.only(start: indent),
          height: 0.5,
          color: line,
        ));
      }
      rows.add(children[i]);
    }

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 0, 32, 7),
            child: Text(
              header,
              style: TextStyle(fontSize: 12, height: 16 / 12, color: secondary),
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: card,
              borderRadius: BorderRadius.circular(kCardRadius),
              boxShadow: kCardShadow,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(kCardRadius),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: rows,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 카드 모양(배경·둥근 모서리·그림자). 오늘·캘린더·기록 화면이 모두 같은 모양을 써요.
BoxDecoration _cardDecoration(BuildContext context) {
  return BoxDecoration(
    color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(context),
    borderRadius: BorderRadius.circular(kCardRadius),
    boxShadow: kCardShadow,
  );
}

// ───────────────────────── 날짜별 집계 ─────────────────────────

/// [day]에 나타나는 항목: 루틴(기록 시작일~오늘) → 시간 있는 투두(시간순) → 시간 없는 투두
List<Item> itemsOnDay(List<Item> items, String day, String today) {
  final routines =
      items.where((e) => e.isRoutine && e.scheduledOn(day, today)).toList();
  final todos = items.where((e) => !e.isRoutine && e.date == day).toList()
    ..sort((a, b) {
      final am = a.minutes;
      final bm = b.minutes;
      if (am == null && bm == null) return 0;
      if (am == null) return 1;
      if (bm == null) return -1;
      return am.compareTo(bm);
    });
  return [...routines, ...todos];
}

/// [day]에 해야 하는 항목 수와 끝낸 항목 수
({int total, int done}) dayProgress(
  List<Item> items,
  String day,
  String today,
) {
  var total = 0;
  var done = 0;
  for (final e in items) {
    if (!e.scheduledOn(day, today)) continue;
    total++;
    if (e.isDoneOn(day)) done++;
  }
  return (total: total, done: done);
}

/// 루틴을 가장 길게 이어서 한 일수 (지금 이어지는 중이 아니어도 돼요)
int longestRunOf(Item item) {
  final days = item.doneDates.map(parseDayKey).whereType<DateTime>().toList()
    ..sort();
  var best = 0;
  var run = 0;
  DateTime? prev;
  for (final d in days) {
    if (prev != null &&
        DateTime.utc(d.year, d.month, d.day)
                .difference(DateTime.utc(prev.year, prev.month, prev.day))
                .inDays ==
            1) {
      run++;
    } else {
      run = 1;
    }
    if (run > best) best = run;
    prev = d;
  }
  return best;
}

// ───────────────────────── 캘린더 화면 ─────────────────────────

/// 달력에서 빨갛게 보이는 공휴일(2026~2027). 해가 바뀌면 다음 해 날짜를 여기에 더하면 돼요.
const Set<String> kHolidays = {
  // 2026
  '2026-01-01',
  '2026-02-16', '2026-02-17', '2026-02-18', // 설날 연휴
  '2026-03-01', '2026-03-02', // 삼일절, 대체공휴일
  '2026-05-01', // 노동절
  '2026-05-05', // 어린이날
  '2026-05-24', '2026-05-25', // 부처님오신날, 대체공휴일
  '2026-06-03', // 지방선거
  '2026-06-06', // 현충일
  '2026-07-17', // 제헌절
  '2026-08-15', '2026-08-17', // 광복절, 대체공휴일
  '2026-09-24', '2026-09-25', '2026-09-26', // 추석 연휴
  '2026-10-03', '2026-10-05', // 개천절, 대체공휴일
  '2026-10-09', // 한글날
  '2026-12-25',
  // 2027
  '2027-01-01',
  '2027-02-06', '2027-02-07', '2027-02-08', '2027-02-09', // 설날 연휴, 대체공휴일
  '2027-03-01',
  '2027-05-01', '2027-05-03', // 노동절, 대체공휴일
  '2027-05-05',
  '2027-05-13', // 부처님오신날
  '2027-06-06',
  '2027-07-17', '2027-07-19', // 제헌절, 대체공휴일
  '2027-08-15', '2027-08-16', // 광복절, 대체공휴일
  '2027-09-14', '2027-09-15', '2027-09-16', // 추석 연휴
  '2027-10-03', '2027-10-04', // 개천절, 대체공휴일
  '2027-10-09', '2027-10-11', // 한글날, 대체공휴일
  '2027-12-25', '2027-12-27', // 성탄절, 대체공휴일
};

/// 일요일·공휴일 글자색
const CupertinoDynamicColor kHolidayRed = CupertinoDynamicColor.withBrightness(
  color: Color(0xFFD70015),
  darkColor: Color(0xFFFF6961),
);

bool _isRedDay(DateTime d) =>
    d.weekday == DateTime.sunday || kHolidays.contains(dayKey(d));

enum _DayStatus { none, partial, all }

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key, required this.store});

  final ItemStore store;

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  late DateTime _month; // 보고 있는 달의 1일
  late DateTime _selected; // 눌러서 고른 날

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _selected = DateTime(now.year, now.month, now.day);
  }

  void _moveMonth(int delta) {
    final now = DateTime.now();
    final m = DateTime(_month.year, _month.month + delta);
    HapticFeedback.selectionClick();
    setState(() {
      _month = m;
      // 이번 달이면 오늘, 다른 달이면 그 달 1일을 골라 둬요.
      _selected = (m.year == now.year && m.month == now.month)
          ? DateTime(now.year, now.month, now.day)
          : m;
    });
  }

  void _select(DateTime d) {
    HapticFeedback.selectionClick();
    setState(() {
      _selected = d;
      _month = DateTime(d.year, d.month);
    });
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      child: ListenableBuilder(
        listenable: widget.store,
        builder: _buildBody,
      ),
    );
  }

  Widget _buildBody(BuildContext context, Widget? _) {
    final items = widget.store.items;
    final now = DateTime.now();
    final today = dayKey(now);
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final label = CupertinoColors.label.resolveFrom(context);

    // 일요일부터 시작하는 달력 칸
    final first = DateTime(_month.year, _month.month);
    final lead = first.weekday % 7; // 일=0, 월=1 … 토=6
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final weeks = ((lead + daysInMonth) / 7).ceil();

    _DayStatus statusOf(DateTime d) {
      final p = dayProgress(items, dayKey(d), today);
      if (p.total == 0) return _DayStatus.none;
      return p.done == p.total ? _DayStatus.all : _DayStatus.partial;
    }

    final selectedKey = dayKey(_selected);
    final dayItems = itemsOnDay(items, selectedKey, today);
    final header =
        '${_selected.month}월 ${_selected.day}일 ${kWeekdays[_selected.weekday - 1]}요일';

    return CustomScrollView(
      slivers: [
        CupertinoSliverNavigationBar(
          largeTitle: const Text('캘린더'),
          backgroundColor: CupertinoColors.systemGroupedBackground,
        ),
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 2026년 10월  < >
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 8, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_month.year}년 ${_month.month}월',
                        style: _font(17, FontWeight.w600, letterSpacing: -0.3)
                            .copyWith(color: label),
                      ),
                    ),
                    _MonthArrow(
                      icon: CupertinoIcons.chevron_left,
                      semanticLabel: '이전 달',
                      onTap: () => _moveMonth(-1),
                    ),
                    _MonthArrow(
                      icon: CupertinoIcons.chevron_right,
                      semanticLabel: '다음 달',
                      onTap: () => _moveMonth(1),
                    ),
                  ],
                ),
              ),
              // 달력 카드 (좌우로 밀어서 달 넘기기)
              GestureDetector(
                onHorizontalDragEnd: (d) {
                  final v = d.primaryVelocity ?? 0;
                  if (v < -300) {
                    _moveMonth(1);
                  } else if (v > 300) {
                    _moveMonth(-1);
                  }
                },
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
                  decoration: _cardDecoration(context),
                  child: Column(
                    children: [
                      SizedBox(
                        height: 22,
                        child: Row(
                          children: [
                            for (var i = 0; i < 7; i++)
                              Expanded(
                                child: Center(
                                  child: Text(
                                    const ['일', '월', '화', '수', '목', '금', '토'][i],
                                    style: _font(11, FontWeight.w600).copyWith(
                                      color: i == 0
                                          ? CupertinoDynamicColor.resolve(
                                              kHolidayRed, context)
                                          : secondary,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      for (var w = 0; w < weeks; w++)
                        Row(
                          children: [
                            for (var c = 0; c < 7; c++)
                              Builder(builder: (context) {
                                final date = DateTime(
                                  _month.year,
                                  _month.month,
                                  1 - lead + w * 7 + c,
                                );
                                final inMonth = date.month == _month.month;
                                final key = dayKey(date);
                                return _DayCell(
                                  date: date,
                                  inMonth: inMonth,
                                  isToday: key == today,
                                  isSelected: key == selectedKey,
                                  status:
                                      inMonth ? statusOf(date) : _DayStatus.none,
                                  onTap: () => _select(date),
                                );
                              }),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
              // 고른 날의 목록
              if (dayItems.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(32, 0, 32, 7),
                        child: Text(
                          header,
                          style: TextStyle(
                            fontSize: 12,
                            height: 16 / 12,
                            color: secondary,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            '이 날은 일정이 없어요',
                            style: TextStyle(fontSize: 12, color: secondary),
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                _Section(
                  header: header,
                  children: [
                    for (final item in dayItems)
                      _ItemRow(
                        store: widget.store,
                        item: item,
                        now: now,
                        day: selectedKey,
                        inCalendar: true,
                      ),
                  ],
                ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ],
    );
  }
}

class _MonthArrow extends StatelessWidget {
  const _MonthArrow({
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, size: 20, color: kAccent),
        ),
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.inMonth,
    required this.isToday,
    required this.isSelected,
    required this.status,
    required this.onTap,
  });

  final DateTime date;
  final bool inMonth;
  final bool isToday;
  final bool isSelected;
  final _DayStatus status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    var numberColor = !inMonth
        ? CupertinoColors.secondaryLabel.resolveFrom(context)
        : _isRedDay(date)
            ? CupertinoDynamicColor.resolve(kHolidayRed, context)
            : CupertinoColors.label.resolveFrom(context);
    var weight = FontWeight.w400;
    Color? circle;
    if (isToday) {
      circle = kAccent;
      numberColor = CupertinoColors.white;
      weight = FontWeight.w600;
    } else if (isSelected) {
      circle = CupertinoDynamicColor.resolve(kAccentSoft, context);
      numberColor = CupertinoDynamicColor.resolve(kAccentDeep, context);
      weight = FontWeight.w600;
    }

    final dot = switch (status) {
      _DayStatus.none => const SizedBox(width: 6, height: 6),
      _DayStatus.all => Container(
          width: 6,
          height: 6,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: kAccent,
          ),
        ),
      _DayStatus.partial => Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: kAccent, width: 1.4),
          ),
        ),
    };

    return Expanded(
      child: Semantics(
        button: true,
        selected: isSelected,
        label: '${date.month}월 ${date.day}일',
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            height: 46,
            child: Column(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: circle),
                  child: Text(
                    '${date.day}',
                    style: _font(15, weight).copyWith(color: numberColor),
                  ),
                ),
                const SizedBox(height: 2),
                dot,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── 기록 화면 ─────────────────────────

class StatsPage extends StatelessWidget {
  const StatsPage({super.key, required this.store});

  final ItemStore store;

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      child: ListenableBuilder(
        listenable: store,
        builder: _buildBody,
      ),
    );
  }

  Widget _buildBody(BuildContext context, Widget? _) {
    final items = store.items;
    final now = DateTime.now();
    final today = dayKey(now);
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final label = CupertinoColors.label.resolveFrom(context);

    // 이번 주: 월요일 ~ 일요일
    final monday = DateTime(now.year, now.month, now.day - (now.weekday - 1));
    final week = [
      for (var i = 0; i < 7; i++)
        DateTime(monday.year, monday.month, monday.day + i),
    ];
    final sunday = week.last;
    final weekText = monday.month == sunday.month
        ? '이번 주 · ${monday.month}월 ${monday.day}일 – ${sunday.day}일'
        : '이번 주 · ${monday.month}월 ${monday.day}일 – ${sunday.month}월 ${sunday.day}일';

    // 요일별 달성률 (아직 안 온 날, 할 일이 없던 날은 비워 둬요)
    final rates = <double?>[];
    for (final d in week) {
      final key = dayKey(d);
      if (key.compareTo(today) > 0) {
        rates.add(null);
        continue;
      }
      final p = dayProgress(items, key, today);
      rates.add(p.total == 0 ? null : p.done / p.total);
    }
    final known = rates.whereType<double>().toList();
    final average =
        known.isEmpty ? null : known.reduce((a, b) => a + b) / known.length;
    final todayIndex = now.weekday - 1;

    // 이번 달에 끝낸 개수
    final monthPrefix =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-';
    var monthDone = 0;
    for (final e in items) {
      if (e.isRoutine) {
        monthDone += e.doneDates.where((d) => d.startsWith(monthPrefix)).length;
      } else if (e.done) {
        final key = e.doneOn ?? e.date;
        if (key != null && key.startsWith(monthPrefix)) monthDone++;
      }
    }

    // 가장 길게 이어간 루틴
    final routines = items.where((e) => e.isRoutine).toList();
    var longest = 0;
    for (final e in routines) {
      final run = longestRunOf(e);
      if (run > longest) longest = run;
    }

    // 지금 이어지는 연속 일수가 긴 순서
    final streaks = {for (final e in routines) e: streakOf(e, now)};
    routines.sort((a, b) {
      final c = streaks[b]!.compareTo(streaks[a]!);
      return c != 0 ? c : a.title.compareTo(b.title);
    });

    final barText = [
      for (var i = 0; i < 7; i++)
        '${kWeekdays[i]} ${rates[i] == null ? '기록 없음' : '${(rates[i]! * 100).round()}%'}',
    ].join(', ');

    return CustomScrollView(
      slivers: [
        CupertinoSliverNavigationBar(
          largeTitle: const Text('기록'),
          backgroundColor: CupertinoColors.systemGroupedBackground,
        ),
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 2, 20, 0),
                child: Text(
                  weekText,
                  style: TextStyle(fontSize: 12, color: secondary),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: _StatCard(
                        label: '최장 연속',
                        value: '$longest',
                        unit: '일',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _StatCard(
                        label: '이번 달 완료',
                        value: '$monthDone',
                        unit: '개',
                      ),
                    ),
                  ],
                ),
              ),
              // 평균 달성률 + 요일별 막대
              Container(
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                padding: const EdgeInsets.all(16),
                decoration: _cardDecoration(context),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          average == null ? '–' : '${(average * 100).round()}%',
                          style: _font(22, FontWeight.w700, letterSpacing: -0.3)
                              .copyWith(color: label, height: 28 / 22),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '평균 달성률',
                          style: _font(12, FontWeight.w400)
                              .copyWith(color: secondary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Semantics(
                      label: '요일별 달성률: $barText',
                      excludeSemantics: true,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var i = 0; i < 7; i++) ...[
                            if (i > 0) const SizedBox(width: 10),
                            Expanded(
                              child: _WeekBar(
                                label: kWeekdays[i],
                                rate: rates[i],
                                isToday: i == todayIndex,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (routines.isNotEmpty)
                _Section(
                  header: '연속 달성',
                  indent: 16,
                  children: [
                    for (final e in routines)
                      _StreakRow(
                        item: e,
                        streak: streaks[e]!,
                        week: week,
                        today: today,
                      ),
                  ],
                ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.unit,
  });

  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: _cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: _font(12, FontWeight.w400)
                .copyWith(color: secondary, height: 16 / 12),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: _font(22, FontWeight.w700, letterSpacing: -0.3).copyWith(
                  color: CupertinoColors.label.resolveFrom(context),
                  height: 28 / 22,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                unit,
                style: _font(15, FontWeight.w400).copyWith(color: secondary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WeekBar extends StatelessWidget {
  const _WeekBar({
    required this.label,
    required this.rate,
    required this.isToday,
  });

  final String label;
  final double? rate;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final track = CupertinoColors.systemGroupedBackground.resolveFrom(context);
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final labelColor = CupertinoColors.label.resolveFrom(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: 100,
            color: track,
            alignment: Alignment.bottomCenter,
            child: FractionallySizedBox(
              widthFactor: 1,
              heightFactor: (rate ?? 0).clamp(0.0, 1.0),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: kAccent,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          textAlign: TextAlign.center,
          style: _font(12, isToday ? FontWeight.w600 : FontWeight.w400).copyWith(
            color: isToday ? labelColor : secondary,
            height: 16 / 12,
          ),
        ),
      ],
    );
  }
}

class _StreakRow extends StatelessWidget {
  const _StreakRow({
    required this.item,
    required this.streak,
    required this.week,
    required this.today,
  });

  final Item item;
  final int streak;
  final List<DateTime> week;
  final String today;

  @override
  Widget build(BuildContext context) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final missed = CupertinoColors.systemGrey.resolveFrom(context);
    final idle = CupertinoColors.systemGrey4.resolveFrom(context);

    var doneCount = 0;
    final dots = <Widget>[];
    for (var i = 0; i < week.length; i++) {
      final key = dayKey(week[i]);
      final done = item.doneDates.contains(key);
      if (done) doneCount++;
      // 끝냄 = 파란 채움, 놓침 = 진한 회색 테두리, 아직 안 온 날·기록 전 날 = 연한 테두리
      final scheduled = key.compareTo(today) <= 0 && item.scheduledOn(key, today);
      dots.add(
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done ? kAccent : null,
            border: done
                ? null
                : Border.all(color: scheduled ? missed : idle, width: 1.5),
          ),
        ),
      );
    }

    return Semantics(
      label: '${item.title}, 이번 주 7일 중 $doneCount일 완료',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.title,
                    style: _font(15, FontWeight.w400, letterSpacing: -0.2)
                        .copyWith(
                      color: CupertinoColors.label.resolveFrom(context),
                      height: 20 / 15,
                    ),
                  ),
                ),
                if (streak >= kFlameStreak) ...[
                  const _FlameIcon(size: 14),
                  const SizedBox(width: 3),
                ],
                if (streak > 0)
                  Text(
                    '$streak일 연속',
                    style: _font(12, FontWeight.w400).copyWith(color: secondary),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (var i = 0; i < dots.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  dots[i],
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── PRO 화면 ─────────────────────────
//
// 위젯은 하루링 PRO 기능이에요. 3일 무료 체험이 끝나면 위젯이 잠기고,
// ₩3,300을 한 번 결제하면 계속 쓸 수 있어요. (구독 아님)

/// 오늘 화면 위쪽의 작은 PRO 버튼
class _ProNavButton extends StatelessWidget {
  const _ProNavButton();

  @override
  Widget build(BuildContext context) {
    final deep = CupertinoDynamicColor.resolve(kAccentDeep, context);
    final soft = CupertinoDynamicColor.resolve(kAccentSoft, context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        showProSheet(context);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: soft,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _GridGlyph(size: 13, color: deep),
            const SizedBox(width: 5),
            Text(
              'PRO',
              style: _font(12, FontWeight.w700, letterSpacing: 0.3)
                  .copyWith(color: deep),
            ),
          ],
        ),
      ),
    );
  }
}

/// 네모 네 개 모양 (PRO 아이콘)
class _GridGlyph extends StatelessWidget {
  const _GridGlyph({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _GridGlyphPainter(color),
    );
  }
}

class _GridGlyphPainter extends CustomPainter {
  _GridGlyphPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final u = size.width / 38;
    void box(double x, double y, double opacity) {
      final paint = Paint()..color = color.withValues(alpha: opacity);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x * u, y * u, 12.5 * u, 12.5 * u),
          Radius.circular(3.6 * u),
        ),
        paint,
      );
    }

    box(5, 5, 1);
    box(20.5, 5, 0.7);
    box(5, 20.5, 0.7);
    box(20.5, 20.5, 1);
  }

  @override
  bool shouldRepaint(_GridGlyphPainter old) => old.color != color;
}

Future<void> showProSheet(BuildContext context) {
  return showCupertinoModalPopup<void>(
    context: context,
    builder: (_) => const _ProSheet(),
  );
}

enum _ProView { intro, trial, ended, purchased }

class _ProSheet extends StatefulWidget {
  const _ProSheet();

  @override
  State<_ProSheet> createState() => _ProSheetState();
}

class _ProSheetState extends State<_ProSheet> {
  final ProManager pro = ProManager.instance;
  double _pull = 0; // 맨 위에서 아래로 당긴 최대 거리 (일정 이상이면 닫아요)
  double _handleDrag = 0;

  @override
  void initState() {
    super.initState();
    pro.load();
  }

  _ProView get _view {
    if (pro.purchased) return _ProView.purchased;
    if (pro.trialActive) return _ProView.trial;
    if (pro.trialStarted) return _ProView.ended;
    return _ProView.intro;
  }

  Future<void> _notice(String title, [String? message]) {
    return showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(title),
        content: message == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(message),
              ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  Future<void> _startTrial() async {
    HapticFeedback.mediumImpact();
    await pro.startTrial();
  }

  Future<void> _buy() async {
    HapticFeedback.mediumImpact();
    final result = await pro.buy();
    if (!mounted) return;
    switch (result) {
      case 'purchased':
        await _notice('하루링 PRO가 열렸어요', '위젯을 계속 쓸 수 있어요. 고마워요!');
      case 'cancelled':
        break;
      case 'pending':
        await _notice('결제 승인을 기다리고 있어요', '승인되면 자동으로 PRO가 열려요.');
      case 'error:iphone':
        await _notice('아이폰에서만 결제할 수 있어요');
      case 'error:product':
        await _notice('상품 정보를 불러오지 못했어요', '잠시 뒤에 다시 시도해 주세요.');
      default:
        await _notice('결제를 끝내지 못했어요', '잠시 뒤에 다시 시도해 주세요.');
    }
  }

  Future<void> _restore() async {
    final ok = await pro.restore();
    if (!mounted) return;
    if (ok) {
      await _notice('구입을 복원했어요', '하루링 PRO가 다시 열렸어요.');
    } else {
      await _notice('복원할 구입 내역이 없어요', '같은 Apple 계정으로 결제한 적이 있는지 확인해 주세요.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final bg = CupertinoColors.systemGroupedBackground.resolveFrom(context);
    final label = CupertinoColors.label.resolveFrom(context);

    return ListenableBuilder(
      listenable: pro,
      builder: (context, _) {
        final view = _view;
        return Container(
          height: mq.size.height - mq.padding.top - 6,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x2E000000),
                blurRadius: 24,
                offset: Offset(0, -2),
              ),
            ],
          ),
          child: DefaultTextStyle(
            style: _font(15, FontWeight.w400).copyWith(color: label),
            child: Stack(
              children: [
                Column(
                  children: [
                    Expanded(
                      child: NotificationListener<ScrollNotification>(
                        onNotification: (n) {
                          if (n.metrics.pixels < 0) {
                            if (-n.metrics.pixels > _pull) {
                              _pull = -n.metrics.pixels;
                            }
                          }
                          if (n is ScrollEndNotification) {
                            final close = _pull > 70;
                            _pull = 0;
                            if (close && mounted) Navigator.pop(context);
                          }
                          return false;
                        },
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(
                            parent: AlwaysScrollableScrollPhysics(),
                          ),
                          padding: const EdgeInsets.only(top: 26, bottom: 16),
                          child: _buildContent(context, view),
                        ),
                      ),
                    ),
                    if (view != _ProView.purchased)
                      _buildBottom(context, view, mq.padding.bottom),
                    if (view == _ProView.purchased)
                      SizedBox(height: mq.padding.bottom + 8),
                  ],
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 64,
                  height: 36,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onVerticalDragStart: (_) => _handleDrag = 0,
                    onVerticalDragUpdate: (d) => _handleDrag += d.delta.dy,
                    onVerticalDragEnd: (d) {
                      if (_handleDrag > 40 ||
                          (d.primaryVelocity ?? 0) > 500) {
                        Navigator.pop(context);
                      }
                    },
                  ),
                ),
                Positioned(
                  top: 7,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(child: Center(
                    child: Container(
                      width: 36,
                      height: 5,
                      decoration: BoxDecoration(
                        color: CupertinoColors.systemGrey4.resolveFrom(context),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  )),
                ),
                Positioned(
                  top: 14,
                  right: 16,
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: CupertinoColors.systemGrey5.resolveFrom(context),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        CupertinoIcons.xmark,
                        size: 13,
                        color:
                            CupertinoColors.secondaryLabel.resolveFrom(context),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildContent(BuildContext context, _ProView view) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final subtitle = switch (view) {
      _ProView.intro => '아래 위젯을 3일 동안 무료로 써보세요',
      _ProView.trial => null,
      _ProView.ended => '체험이 끝났어요. 계속 쓰려면 한 번만 결제하세요',
      _ProView.purchased => '위젯을 마음껏 쓰세요. 고마워요!',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: kAccent,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x5955A0FA),
                  blurRadius: 16,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: const _GridGlyph(size: 30, color: CupertinoColors.white),
          ),
        ),
        const SizedBox(height: 10),
        Center(
          child: Text(
            '하루링 PRO',
            style: _font(26, FontWeight.w700, letterSpacing: 0.3).copyWith(
              color: CupertinoColors.label.resolveFrom(context),
            ),
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              style: _font(15, FontWeight.w400).copyWith(color: secondary),
            ),
          ),
        ],
        if (view != _ProView.intro) ...[
          const SizedBox(height: 16),
          _buildStatusCard(context, view),
          if (view != _ProView.ended)
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 10, 32, 0),
              child: Text(
                '홈 화면을 길게 누르고 왼쪽 위 + 버튼을 눌러 "하루링"을 찾아 추가해 보세요. '
                '잠금화면은 시계 아래 칸을 눌러 추가해요.',
                textAlign: TextAlign.center,
                style: _font(12, FontWeight.w400).copyWith(color: secondary),
              ),
            ),
        ],
        const SizedBox(height: 16),
        _sectionLabel(context, '홈 화면 위젯'),
        const _HomePreviewRow(),
        const SizedBox(height: 14),
        _sectionLabel(context, '잠금화면 위젯 · 5종'),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: _LockPreview(),
        ),
      ],
    );
  }

  Widget _sectionLabel(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 0, 16, 7),
      child: Text(
        text,
        style: _font(12, FontWeight.w400).copyWith(
          color: CupertinoColors.secondaryLabel.resolveFrom(context),
        ),
      ),
    );
  }

  Widget _buildStatusCard(BuildContext context, _ProView view) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final deep = CupertinoDynamicColor.resolve(kAccentDeep, context);
    final soft = CupertinoDynamicColor.resolve(kAccentSoft, context);
    final grey = CupertinoColors.systemGrey5.resolveFrom(context);

    var chip = '무료 체험 중';
    var headline = '';
    var detail = '';
    var filled = 0;
    var chipColor = deep;
    var chipBg = soft;

    if (view == _ProView.trial) {
      final end = pro.trialEnd!;
      final rem = end.difference(DateTime.now());
      final days =
          (rem.inMinutes / 1440).ceil().clamp(1, ProManager.trialDays).toInt();
      if (rem.inHours >= 24) {
        headline = '$days일 남았어요';
      } else if (rem.inHours >= 1) {
        headline = '${rem.inHours}시간 남았어요';
      } else {
        headline = '${rem.inMinutes.clamp(1, 59)}분 남았어요';
      }
      filled = rem.inHours >= 24
          ? ProManager.trialDays - days
          : ProManager.trialDays - 1;
      detail =
          '${end.month}월 ${end.day}일 ${clockLabel(end.hour * 60 + end.minute)}에 끝나요';
    } else if (view == _ProView.ended) {
      chip = '체험 종료';
      chipColor = secondary;
      chipBg = grey;
      headline = '위젯이 잠겼어요';
      detail = '할 일·루틴 기록은 그대로예요. 결제하면 위젯이 다시 열려요.';
      filled = ProManager.trialDays;
    } else {
      chip = 'PRO 이용 중';
      headline = '결제 완료';
      detail = '구독이 아니라서 다시 결제할 일이 없어요.';
      filled = ProManager.trialDays;
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: _cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: chipBg,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  chip,
                  style: _font(13, FontWeight.w600).copyWith(color: chipColor),
                ),
              ),
              const Spacer(),
              Text(
                headline,
                style: _font(18, FontWeight.w700).copyWith(
                  color: CupertinoColors.label.resolveFrom(context),
                ),
              ),
            ],
          ),
          if (view != _ProView.purchased) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                for (var i = 0; i < ProManager.trialDays; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(
                    child: Container(
                      height: 5,
                      decoration: BoxDecoration(
                        color: i < filled
                            ? (view == _ProView.ended ? secondary : kAccent)
                            : soft,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
          const SizedBox(height: 10),
          Text(
            detail,
            style: _font(13, FontWeight.w400).copyWith(color: secondary),
          ),
        ],
      ),
    );
  }

  Widget _buildBottom(BuildContext context, _ProView view, double safeBottom) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final deep = CupertinoDynamicColor.resolve(kAccentDeep, context);
    final intro = view == _ProView.intro;
    final price = pro.price;

    final buttonText =
        intro ? '3일 무료 체험 시작' : '$price · 한 번 결제하고 계속 쓰기';
    final note = intro
        ? '3일이 지나면 위젯이 잠겨요. 계속 쓰려면 $price을 한 번만 결제하세요.\n구독도, 자동 결제도 없어요.'
        : '구독도, 자동 결제도 없어요.\n한 번 결제하면 계속 쓸 수 있어요.';

    TextStyle link() => _font(14, FontWeight.w500).copyWith(color: deep);

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 4, 16, safeBottom + 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: pro.busy ? null : (intro ? _startTrial : _buy),
            child: Container(
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: deep,
                borderRadius: BorderRadius.circular(14),
              ),
              child: pro.busy
                  ? const CupertinoActivityIndicator(color: CupertinoColors.white)
                  : Text(
                      buttonText,
                      style: _font(17, FontWeight.w700)
                          .copyWith(color: CupertinoColors.white),
                    ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            note,
            textAlign: TextAlign.center,
            style: _font(12, FontWeight.w400).copyWith(color: secondary),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (intro) ...[
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: pro.busy ? null : _buy,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text('바로 구입하기 · $price', style: link()),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text('·', style: link().copyWith(color: secondary)),
                ),
              ],
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: pro.busy ? null : _restore,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text('구입 복원', style: link()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── 위젯 미리보기 (확정한 위젯 시안을 줄여서 보여줘요) ──

/// 홈 화면 위젯 한 장. 158칸 기준으로 그린 뒤 0.7배로 줄여요.
class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.width, required this.child});

  final double width;
  final Widget child;

  static const double _scale = 0.7;
  static const double _height = 158;

  @override
  Widget build(BuildContext context) {
    final card = CupertinoColors.secondarySystemGroupedBackground
        .resolveFrom(context);
    return SizedBox(
      width: width * _scale,
      height: _height * _scale,
      child: FittedBox(
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
          child: Container(
            width: width,
            height: _height,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: card,
              borderRadius: BorderRadius.circular(22),
              boxShadow: kCardShadow,
            ),
            child: DefaultTextStyle(
              style: _font(12, FontWeight.w400).copyWith(
                color: CupertinoColors.label.resolveFrom(context),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class _HomePreviewRow extends StatelessWidget {
  const _HomePreviewRow();

  @override
  Widget build(BuildContext context) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final deep = CupertinoDynamicColor.resolve(kAccentDeep, context);
    final soft = CupertinoDynamicColor.resolve(kAccentSoft, context);
    final label = CupertinoColors.label.resolveFrom(context);
    final now = DateTime.now();

    Widget miniRow(String title, bool done, String streak, {bool flame = false}) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          children: [
            _CheckCircle(checked: done),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _font(15, FontWeight.w400).copyWith(color: label),
              ),
            ),
            if (flame) ...[
              const _FlameIcon(size: 13),
              const SizedBox(width: 3),
            ],
            Text(streak, style: _font(12, FontWeight.w400).copyWith(color: secondary)),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        children: [
          // 작게 · 오늘 루틴
          _PreviewCard(
            width: 158,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('오늘 루틴',
                    style: _font(12, FontWeight.w600).copyWith(color: secondary)),
                const Spacer(),
                Center(
                  child: SizedBox(
                    width: 84,
                    height: 84,
                    child: CustomPaint(
                      painter: _RingPainter(
                        progress: 2 / 3,
                        track: soft,
                        tint: kAccent,
                        stroke: 9,
                      ),
                      child: Center(
                        child: Text('2/3',
                            style: _font(20, FontWeight.w700)
                                .copyWith(color: label)),
                      ),
                    ),
                  ),
                ),
                const Spacer(),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // 작게 · 다음 일정
          _PreviewCard(
            width: 158,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: soft,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text('다음 일정',
                      style: _font(11, FontWeight.w600).copyWith(color: deep)),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            color: kAccent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('점심약속',
                            style: _font(16, FontWeight.w600)
                                .copyWith(color: label)),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 18, top: 4),
                      child: Text('2시간 40분 후 시작',
                          style: _font(12, FontWeight.w400)
                              .copyWith(color: secondary)),
                    ),
                  ],
                ),
                Text('오후 2:00',
                    style: _font(12, FontWeight.w600).copyWith(color: deep)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // 중간 · 오늘 루틴
          _PreviewCard(
            width: 338,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('오늘 · ${now.month}월 ${now.day}일',
                        style: _font(12, FontWeight.w600)
                            .copyWith(color: secondary)),
                    Text('2/3 완료',
                        style: _font(12, FontWeight.w400)
                            .copyWith(color: secondary)),
                  ],
                ),
                miniRow('물 2L 마시기', true, '12일 연속', flame: true),
                miniRow('스트레칭 10분', true, '5일 연속'),
                miniRow('영어 단어 20개', false, '3일 연속'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.track,
    required this.tint,
    required this.stroke,
  });

  final double progress;
  final Color track;
  final Color tint;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final arc = rect.deflate(stroke / 2);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track;
    canvas.drawArc(arc, 0, 6.2831853, false, base);
    if (progress > 0) {
      final top = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = tint;
      canvas.drawArc(arc, -1.5707963, 6.2831853 * progress, false, top);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress ||
      old.track != track ||
      old.tint != tint ||
      old.stroke != stroke;
}

/// 잠금화면 위젯 5종 미리보기 (어두운 배경 위)
class _LockPreview extends StatelessWidget {
  const _LockPreview();

  static const Color _white = CupertinoColors.white;

  Widget _glass({required Widget child, double radius = 16}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0x2EFFFFFF),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: child,
    );
  }

  Widget _circle(Widget child) {
    return Container(
      width: 62,
      height: 62,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: Color(0x2EFFFFFF),
        shape: BoxShape.circle,
      ),
      child: child,
    );
  }

  Widget _line(
    IconData icon,
    String text, {
    String? time,
    bool strike = false,
    bool flame = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 13, color: _white),
          const SizedBox(width: 5),
          if (time != null) ...[
            Text(time,
                style: _font(12, FontWeight.w700).copyWith(color: _white)),
            const SizedBox(width: 5),
          ],
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _font(12, FontWeight.w500).copyWith(
                color: _white,
                decoration: strike ? TextDecoration.lineThrough : null,
                decorationColor: _white,
              ),
            ),
          ),
          if (flame)
            const Icon(CupertinoIcons.flame_fill, size: 11, color: _white),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(
            begin: Alignment(-0.3, -1),
            end: Alignment(0.3, 1),
            colors: [Color(0xFF2A4A7C), Color(0xFF1A2E54), Color(0xFF0E192F)],
            stops: [0, 0.48, 1],
          ),
        ),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _glass(
                    child: Column(
                      children: [
                        _line(CupertinoIcons.circle, '점심약속', time: '2:00'),
                        _line(CupertinoIcons.circle, '택배 반품 접수', time: '4:30'),
                        _line(CupertinoIcons.circle, '영어 스터디', time: '7:00'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _glass(
                    child: Column(
                      children: [
                        _line(CupertinoIcons.check_mark_circled_solid,
                            '물 2L 마시기',
                            strike: true, flame: true),
                        _line(CupertinoIcons.check_mark_circled_solid,
                            '스트레칭 10분',
                            strike: true),
                        _line(CupertinoIcons.circle, '영어 단어 20개'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _circle(
                  SizedBox(
                    width: 50,
                    height: 50,
                    child: CustomPaint(
                      painter: _RingPainter(
                        progress: 2 / 3,
                        track: const Color(0x40FFFFFF),
                        tint: _white,
                        stroke: 4,
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('루틴',
                                style: _font(8, FontWeight.w600)
                                    .copyWith(color: _white)),
                            Text('2/3',
                                style: _font(14, FontWeight.w700)
                                    .copyWith(color: _white)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _circle(
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(CupertinoIcons.flame_fill,
                          size: 15, color: _white),
                      Text('12일',
                          style: _font(14, FontWeight.w700)
                              .copyWith(color: _white)),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    '점심약속 · 오후 2:00',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _font(14, FontWeight.w500).copyWith(color: _white),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
