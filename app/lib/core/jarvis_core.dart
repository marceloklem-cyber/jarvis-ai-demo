// JARVIS AI — núcleo do app (Dart). Porte fiel de src/jarvis-core.js da versão web 0.7.2,
// que tem 33 testes automatizados; os mesmos cenários estão em test/core_test.dart.
// Sem dependência de Flutter: interpreta comandos, mantém a agenda, desfaz e planeja avisos.
import 'dart:convert';
import 'dart:math' as math;

const String coreVersion = '0.8.0';
const String keyTasks = 'jarvis-app-tasks';
const String keySettings = 'jarvis-app-settings';

// ===================================================================== texto
const Map<String, String> _accent = {
  'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
  'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i', 'ó': 'o', 'ò': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
  'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u', 'ç': 'c', 'ñ': 'n'
};
const Map<String, Map<String, String>> _combining = {
  '́': {'a': 'á', 'e': 'é', 'i': 'í', 'o': 'ó', 'u': 'ú', 'A': 'Á', 'E': 'É', 'I': 'Í', 'O': 'Ó', 'U': 'Ú'},
  '̀': {'a': 'à', 'A': 'À'},
  '̂': {'a': 'â', 'e': 'ê', 'o': 'ô', 'A': 'Â', 'E': 'Ê', 'O': 'Ô'},
  '̃': {'a': 'ã', 'o': 'õ', 'A': 'Ã', 'O': 'Õ'},
  '̧': {'c': 'ç', 'C': 'Ç'},
};
final RegExp _markRe = RegExp('[̀-ͯ]');

/// Junta letra + acento combinante (o Dart não tem normalização Unicode embutida).
String compose(String s) {
  if (!_markRe.hasMatch(s)) return s;
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final ch = s[i];
    if (i + 1 < s.length) {
      final c = _combining[s[i + 1]]?[ch];
      if (c != null) {
        b.write(c);
        i++;
        continue;
      }
    }
    if (_markRe.hasMatch(ch)) continue;
    b.write(ch);
  }
  return b.toString();
}

/// Minúsculas sem acento, com o mesmo comprimento do texto original.
String fold(String s) {
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final ch = s[i].toLowerCase();
    final m = _accent[ch];
    if (m != null) {
      b.write(m);
    } else if (ch.length == 1) {
      b.write(ch);
    } else {
      b.write(' ');
    }
  }
  return b.toString();
}

const Map<String, int> _units = {
  'um': 1, 'uma': 1, 'dois': 2, 'duas': 2, 'tres': 3, 'quatro': 4, 'cinco': 5, 'seis': 6, 'sete': 7, 'oito': 8, 'nove': 9
};
const Map<String, int> _nums = {
  'um': 1, 'uma': 1, 'dois': 2, 'duas': 2, 'tres': 3, 'quatro': 4, 'cinco': 5, 'seis': 6, 'sete': 7, 'oito': 8, 'nove': 9,
  'dez': 10, 'onze': 11, 'doze': 12, 'treze': 13, 'quatorze': 14, 'catorze': 14, 'quinze': 15, 'dezesseis': 16,
  'dezessete': 17, 'dezoito': 18, 'dezenove': 19, 'vinte': 20, 'trinta': 30, 'quarenta': 40, 'cinquenta': 50, 'sessenta': 60
};
final String _num = () {
  final words = _nums.keys.toList()..sort((a, b) => b.length - a.length);
  return r'(?:\d{1,3}|(?:vinte|trinta|quarenta|cinquenta)\s+e\s+(?:' + _units.keys.join('|') + ')|' + words.join('|') + ')';
}();

int toNum(String s) {
  s = s.trim();
  if (RegExp(r'^\d+$').hasMatch(s)) return int.parse(s);
  if (s == 'meia') return 30;
  if (s == 'primeiro') return 1;
  return s.split(RegExp(r'\s+e\s+')).fold(0, (a, w) => a + (_nums[w] ?? 0));
}

const List<String> _wd = ['domingo', 'segunda', 'terca', 'quarta', 'quinta', 'sexta', 'sabado'];
final String _wdAlt = _wd.join('|');
final String _wdAny = '(?:$_wdAlt)s?(?:[- ]feiras?)?';
const List<String> _months = ['janeiro', 'fevereiro', 'marco', 'abril', 'maio', 'junho', 'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro'];
const List<String> weekdayFull = ['domingo', 'segunda-feira', 'terça-feira', 'quarta-feira', 'quinta-feira', 'sexta-feira', 'sábado'];
const List<String> monthFull = ['janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', 'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro'];

/// Texto em trabalho: casa expressões no texto "dobrado" e remove os trechos do original.
class Work {
  final String orig;
  late String f;
  late List<bool> cut;
  Work(String text) : orig = compose(text) {
    f = fold(orig);
    cut = List<bool>.filled(orig.length, false);
  }
  RegExpMatch? find(RegExp re) => re.firstMatch(f);
  RegExpMatch? take(RegExp re) {
    final m = re.firstMatch(f);
    if (m != null) remove(m.start, m.end - m.start);
    return m;
  }

  void remove(int i, int n) {
    for (var k = i; k < i + n; k++) {
      cut[k] = true;
    }
    f = f.substring(0, i) + ' ' * n + f.substring(i + n);
  }

  String rest() {
    final b = StringBuffer();
    for (var k = 0; k < orig.length; k++) {
      b.write(cut[k] ? ' ' : orig[k]);
    }
    return b.toString();
  }
}

// ===================================================================== datas
String pad(int n) => n.toString().padLeft(2, '0');
String dayKey(DateTime d) => '${d.year}-${pad(d.month)}-${pad(d.day)}';
DateTime startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n, d.hour, d.minute);
int daysInMonth(int y, int m) => DateTime(y, m + 1, 0).day; // m de 1 a 12 (aceita estouro)
int wdOf(DateTime d) => d.weekday % 7; // 0 = domingo, como no JavaScript
bool validYMD(int y, int m, int d) => m >= 1 && m <= 12 && d >= 1 && d <= 31 && y >= 1970 && y <= 2200 && d <= daysInMonth(y, m);
int dayDiff(DateTime a, DateTime b) => (startOfDay(a).difference(startOfDay(b)).inHours / 24).round();
int _minOfDay(DateTime d) => d.hour * 60 + d.minute;

// ================================================================= lembretes
const String _unit = r'(minutos?|mins?|horas?|hrs?|h|dias?)';
int _unitMinutes(String u) => u[0] == 'd' ? 1440 : (u[0] == 'h' ? 60 : 1);
int? _amount(String numStr, String unit, bool plusHalf) {
  final u = _unitMinutes(unit);
  int? v;
  if (numStr == 'meia') {
    v = u == 60 ? 30 : null;
  } else {
    v = toNum(numStr) * u;
  }
  if (v == null) return null;
  if (plusHalf && u == 60) v += 30;
  return v;
}

final RegExp _rmNone = RegExp(r'(?:^|[\s,;])(?:sem\s+(?:lembrete|aviso|alerta|avisos|lembretes)|nao\s+(?:precisa\s+|quero\s+)?(?:me\s+)?(?:avisar|lembrar|aviso|lembrete))\b');
final RegExp _rmAt = RegExp(r'[,;]?\s*(?:\be\s+)?(?:\bme\s+)?\b(?:avise|avisa|avisar|alerte|alerta|lembre|lembra)(?:-me|\s+me)?\s+na\s+hora\b');
final RegExp _rm1 = RegExp(r'[,;]?\s*(?:\be\s+)?(?:\bme\s+)?\b(?:avise|avisa|avisar|alerte|alerta|alertar|notifique|notifica|lembre|lembra|lembrar)(?:-me|\s+me)?\s+(?:com\s+)?(' +
    _num + r'|meia)\s*' + _unit + r'(\s+e\s+meia)?\s+(?:de\s+)?(?:antes|antecedencia)\b');
final RegExp _rm2 = RegExp(r'[,;]?\s*(?:\bcom\s+)?(?:\bum\s+)?\b(?:lembrete|aviso|alerta)\s+(?:de\s+)?(' + _num + r'|meia)\s*' + _unit +
    r'(\s+e\s+meia)?(?:\s+(?:de\s+)?(?:antes|antecedencia))?\b');
final RegExp _rm3 = RegExp(r'[,;]?\s*(?:\be\s+)?(?:\bcom\s+)?\b(' + _num + r'|meia)\s*' + _unit + r'(\s+e\s+meia)?\s+(?:de\s+)?(?:antes|antecedencia)\b');
final RegExp _rmBare = RegExp(r'^\s*(?:com\s+|so\s+|apenas\s+)?(' + _num + r'|meia)\s*' + _unit + r'(\s+e\s+meia)?\b');

class ReminderSpec {
  final List<int>? list;
  final bool none;
  const ReminderSpec(this.list, this.none);
}

ReminderSpec extractReminders(Work w, {bool allowBare = false}) {
  final list = <int>[];
  var none = false;
  if (w.take(_rmNone) != null) none = true;
  if (w.take(_rmAt) != null) list.add(0);
  for (final re in [_rm1, _rm2, _rm3]) {
    RegExpMatch? m;
    while ((m = w.take(re)) != null) {
      final v = _amount(m!.group(1)!, m.group(2)!, m.group(3) != null);
      if (v != null && v <= 60 * 24 * 30) list.add(v);
    }
  }
  if (allowBare && list.isEmpty) {
    final m = w.take(_rmBare);
    if (m != null) {
      final v = _amount(m.group(1)!, m.group(2)!, m.group(3) != null);
      if (v != null) list.add(v);
    }
  }
  if (list.isEmpty) return ReminderSpec(null, none);
  final s = {...list}.toList()..sort((a, b) => b - a);
  return ReminderSpec(s, none);
}

// =============================================================== recorrência
class Recurrence {
  final String freq; // daily | weekly | monthly
  final List<int>? byDay; // 0 = domingo
  final int? day;
  final String? error;
  const Recurrence(this.freq, {this.byDay, this.day, this.error});
  Map<String, dynamic> toJson() => {'freq': freq, if (byDay != null) 'byDay': byDay, if (day != null) 'day': day};
  static Recurrence? fromJson(dynamic j) {
    if (j is! Map) return null;
    final f = j['freq'];
    if (f is! String) return null;
    return Recurrence(f,
        byDay: (j['byDay'] as List?)?.map((e) => (e as num).toInt()).toList(), day: (j['day'] as num?)?.toInt());
  }
}

final RegExp _rcMonthDay = RegExp(r'\btodo\s+(?:santo\s+)?dia\s+(\d{1,2})(?:\s+de\s+cada\s+mes|\s+do\s+mes)?\b');
final RegExp _rcWorkdays = RegExp(r'\b(?:todos\s+os\s+dias\s+uteis|(?:nos\s+|em\s+)?dias\s+uteis|de\s+segunda\s+a\s+sexta(?:[- ]feira)?)\b');
final RegExp _rcWeekdays = RegExp(r'\b(?:todas\s+as|todos\s+os|toda|todo|cada)\s+' + _wdAny + r'(?:\s*(?:,|e)\s*(?:as\s+|os\s+)?' + _wdAny + r')*');
final RegExp _rcDaily = RegExp(r'\b(?:todos\s+os\s+dias|todo\s+(?:santo\s+)?dia|diariamente|cada\s+dia|toda\s+(?:manha|tarde|noite))\b');
final RegExp _rcWeekly = RegExp(r'\b(?:toda\s+semana|todas\s+as\s+semanas|semanalmente|uma\s+vez\s+por\s+semana)\b');
final RegExp _rcMonthly = RegExp(r'\b(?:todo\s+mes|todos\s+os\s+meses|mensalmente|uma\s+vez\s+por\s+mes)\b');

Recurrence? extractRecurrence(Work w) {
  RegExpMatch? m;
  if ((m = w.take(_rcMonthDay)) != null) {
    final d = int.parse(m!.group(1)!);
    return d >= 1 && d <= 31 ? Recurrence('monthly', day: d) : Recurrence('error', error: 'Dia do mês inválido: $d.');
  }
  if (w.take(_rcWorkdays) != null) return const Recurrence('weekly', byDay: [1, 2, 3, 4, 5]);
  if ((m = w.take(_rcWeekdays)) != null) {
    final days = RegExp('($_wdAlt)').allMatches(m!.group(0)!).map((x) => _wd.indexOf(x.group(1)!)).toSet().toList()..sort();
    return Recurrence('weekly', byDay: days);
  }
  if (w.take(_rcDaily) != null) return const Recurrence('daily');
  if (w.take(_rcWeekly) != null) return const Recurrence('weekly');
  if (w.take(_rcMonthly) != null) return const Recurrence('monthly');
  return null;
}

// ================================================================ data/hora
class DateSpec {
  final String kind; // offset | ymd | dayN | weekday | nextweek
  final int days, d, m, wd;
  final int? y;
  final String mode; // this | next | auto
  const DateSpec(this.kind, {this.days = 0, this.d = 0, this.m = 0, this.y, this.wd = 0, this.mode = 'auto'});
}

class TimeSpec {
  final int h, mi;
  const TimeSpec(this.h, this.mi);
}

class RelSpec {
  final double n;
  final String unit; // min | h | d | w | mo
  const RelSpec(this.n, this.unit);
}

class WhenSpec {
  DateSpec? date;
  TimeSpec? time;
  String? period;
  RelSpec? rel;
  String? error;
  WhenSpec({this.date, this.time, this.rel});
  bool get any => date != null || time != null || rel != null;
}

final RegExp _reRel = RegExp(r'\b(?:daqui\s+a|daqui|dentro\s+de|em)\s+(' + _num + r'|meia)\s*(minutos?|mins?|horas?|dias?|semanas?|meses|mes)(\s+e\s+meia)?\b');
final List<MapEntry<RegExp, int>> _reDayWords = [
  MapEntry(RegExp(r'\bdepois\s+de\s+amanha\b'), 2),
  MapEntry(RegExp(r'\banteontem\b'), -2),
  MapEntry(RegExp(r'\bamanha\b'), 1),
  MapEntry(RegExp(r'\bhoje\b'), 0),
  MapEntry(RegExp(r'\bontem\b'), -1),
];
final RegExp _reNumDate = RegExp(r'\b(?:(?:no\s+|para\s+o\s+)?dia\s+)?(\d{1,2})[/-](\d{1,2})(?:[/-](\d{2,4}))?\b');
final RegExp _reTxtDate = RegExp(r'\b(?:(?:no\s+|para\s+o\s+)?dia\s+)?(\d{1,2}|primeiro|' + _num + r')\s+de\s+(' + _months.join('|') + r')(?:\s+(?:de\s+)?(\d{4}))?\b');
final RegExp _reDayN = RegExp(r'\b(?:(?:no|para\s+o)\s+)?dia\s+(\d{1,2}|primeiro)\b');
final RegExp _reWeekday = RegExp(r'\b(?:(na|no|nesta|neste|esta|este|essa|nessa|nesse|desta|proxima|proximo|na\s+proxima|no\s+proximo|para|pra)\s+)?(' +
    _wdAlt + r')(?:[- ]feira)?(\s+que\s+vem)?\b');
final RegExp _reNextWeek = RegExp(r'\b(?:na\s+|para\s+a\s+)?(?:proxima\s+semana|semana\s+que\s+vem)\b');

const String _pre = r'(?:(?:as|a|pelas|pela|para\s+as|ate\s+as|la\s+pelas)\s+)?';
final RegExp _reT1 = RegExp(r'\b' + _pre + r'(\d{1,2})\s*(?::|h)\s*(\d{2})\b(?:\s*(?:min|minutos)\b)?');
final RegExp _reT2 = RegExp(r'\b' + _pre + r'(\d{1,2}|' + _num + r')\s*(?:h|hs|hrs?|horas?)\b(?:\s+e\s+(\d{1,2}|meia|' + _num + r')(?:\s+minutos?)?)?');
final RegExp _reT3 = RegExp(r'\b(?:as|pelas|para\s+as|ate\s+as)\s+(\d{1,2}|' + _num + r')(?:\s+e\s+(\d{1,2}|meia|' + _num + r'))?\b');
final RegExp _reT3b = RegExp(r'\ba\s+(uma)(?:\s+e\s+(meia|\d{1,2}))?\b(?=\s+(?:da|de)\s+(?:manha|tarde|noite|madrugada))');
final RegExp _reT4 = RegExp(r'\b(?:ao\s+|as\s+|a\s+|para\s+o\s+)?(meio[- ]dia|meia[- ]noite)(?:\s+e\s+(meia|\d{1,2}))?\b');
final RegExp _rePeriod = RegExp(r'\b(?:de|pela|a|da|na)\s+(manha|tarde|noite|madrugada)\b');

WhenSpec extractWhen(Work w) {
  final out = WhenSpec();
  RegExpMatch? m;
  if ((m = w.take(_reRel)) != null) {
    final g1 = m!.group(1)!, g2 = m.group(2)!;
    final n = g1 == 'meia' ? 0.5 : toNum(g1).toDouble();
    final unit = (g2[0] == 'm' && g2.startsWith('mi')) ? 'min' : g2[0] == 'h' ? 'h' : g2[0] == 'd' ? 'd' : g2[0] == 's' ? 'w' : 'mo';
    out.rel = RelSpec(n + (m.group(3) != null ? 0.5 : 0), unit);
  }
  final relDayish = out.rel == null || const ['d', 'w', 'mo'].contains(out.rel!.unit);
  if (relDayish) {
    for (final e in _reDayWords) {
      if (out.date != null) break;
      if (w.take(e.key) != null) out.date = DateSpec('offset', days: e.value);
    }
    if (out.date == null && (m = w.take(_reNumDate)) != null) {
      final ys = m!.group(3);
      out.date = DateSpec('ymd', d: int.parse(m.group(1)!), m: int.parse(m.group(2)!), y: ys == null ? null : (ys.length == 2 ? 2000 + int.parse(ys) : int.parse(ys)));
    }
    if (out.date == null && (m = w.take(_reTxtDate)) != null) {
      out.date = DateSpec('ymd', d: toNum(m!.group(1)!), m: _months.indexOf(m.group(2)!) + 1, y: m.group(3) == null ? null : int.parse(m.group(3)!));
    }
    if (out.date == null && (m = w.take(_reDayN)) != null) out.date = DateSpec('dayN', d: toNum(m!.group(1)!));
    if (out.date == null && w.take(_reNextWeek) != null) out.date = const DateSpec('nextweek');
    if (out.date == null && (m = w.take(_reWeekday)) != null) {
      final q = (m!.group(1) ?? '').replaceAll(RegExp(r'\s+'), ' ');
      final mode = RegExp(r'^(?:nesta|neste|esta|este|essa|nessa|nesse|desta)$').hasMatch(q)
          ? 'this'
          : (q.contains('proxim') || m.group(3) != null)
              ? 'next'
              : 'auto';
      out.date = DateSpec('weekday', wd: _wd.indexOf(m.group(2)!), mode: mode);
    }
  }
  if (out.rel == null || out.date != null || relDayish) {
    int? h;
    var mi = 0;
    if ((m = w.take(_reT4)) != null) {
      h = m!.group(1)!.startsWith('meio') ? 12 : 0;
      mi = m.group(2) != null ? toNum(m.group(2)!) : 0;
    } else if ((m = w.take(_reT1)) != null) {
      h = int.parse(m!.group(1)!);
      mi = int.parse(m.group(2)!);
    } else if ((m = w.take(_reT2)) != null || (m = w.take(_reT3)) != null || (m = w.take(_reT3b)) != null) {
      h = toNum(m!.group(1)!);
      mi = m.group(2) != null ? toNum(m.group(2)!) : 0;
    }
    final pm = w.take(_rePeriod);
    if (pm != null) out.period = pm.group(1);
    if (h != null) {
      if (out.period == 'tarde' && h >= 1 && h <= 11) {
        h += 12;
      } else if (out.period == 'noite' && h >= 5 && h <= 11) {
        h += 12;
      } else if ((out.period == 'noite' || out.period == 'madrugada') && h == 12) {
        h = 0;
      }
      if (h > 23 || mi > 59 || h < 0) {
        out.error = 'Horário inválido.';
      } else {
        out.time = TimeSpec(h, mi);
      }
    }
  }
  return out;
}

DateTime nextWeekdayDate(DateTime now, int wd, String mode, TimeSpec? time) {
  var delta = (wd - wdOf(now) + 7) % 7;
  if (delta == 0) {
    if (mode == 'next') {
      delta = 7;
    } else if (mode == 'this') {
      delta = 0;
    } else if (time != null && time.h * 60 + time.mi > _minOfDay(now)) {
      delta = 0;
    } else {
      delta = 7;
    }
  }
  return addDays(startOfDay(now), delta);
}

class Resolved {
  final DateTime? due;
  final bool allDay, hasDate, hasTime, rolled;
  final String? error;
  const Resolved({this.due, this.allDay = false, this.hasDate = false, this.hasTime = false, this.rolled = false, this.error});
}

Resolved resolveWhen(WhenSpec spec, DateTime now, Recurrence? rec) {
  if (spec.error != null) return Resolved(error: spec.error);
  final today = startOfDay(now);
  DateTime? base;
  var rolled = false;
  final r = spec.rel;
  if (r != null) {
    if (r.unit == 'min' || r.unit == 'h') {
      final mins = (r.n * (r.unit == 'h' ? 60 : 1)).round();
      final d = now.add(Duration(minutes: mins));
      return Resolved(due: DateTime(d.year, d.month, d.day, d.hour, d.minute), hasDate: true, hasTime: true);
    }
    final n = r.n.round();
    if (r.unit == 'd') {
      base = addDays(today, n);
    } else if (r.unit == 'w') {
      base = addDays(today, n * 7);
    } else {
      final mm = today.month + n;
      base = DateTime(today.year, mm, math.min(today.day, daysInMonth(today.year, mm)));
    }
  }
  final d = spec.date, t = spec.time;
  if (base == null && d != null) {
    switch (d.kind) {
      case 'offset':
        base = addDays(today, d.days);
        break;
      case 'ymd': {
        var y = d.y ?? today.year;
        if (!validYMD(y, d.m, d.d)) return Resolved(error: 'Data inválida: ${pad(d.d)}/${pad(d.m)}${d.y != null ? '/${d.y}' : ''}.');
        base = DateTime(y, d.m, d.d);
        if (d.y == null && base.isBefore(today)) {
          if (!validYMD(y + 1, d.m, d.d)) return const Resolved(error: 'Data inválida.');
          y += 1;
          base = DateTime(y, d.m, d.d);
        }
        break;
      }
      case 'dayN': {
        if (d.d < 1 || d.d > 31) return Resolved(error: 'Dia inválido: ${d.d}.');
        var y = today.year, mo = today.month;
        for (var guard = 0; guard < 14; guard++) {
          if (d.d <= daysInMonth(y, mo)) {
            final c = DateTime(y, mo, d.d);
            if (!c.isBefore(today)) {
              base = c;
              break;
            }
          }
          mo++;
          if (mo > 12) {
            mo = 1;
            y++;
          }
        }
        break;
      }
      case 'weekday':
        base = nextWeekdayDate(now, d.wd, d.mode, t);
        break;
      case 'nextweek':
        base = nextWeekdayDate(now, 1, 'next', null);
        break;
    }
  }
  if (base == null && rec != null) {
    if (rec.freq == 'weekly' && rec.byDay != null && rec.byDay!.isNotEmpty) {
      for (var i = 0; i < 8; i++) {
        final c = addDays(today, i);
        if (!rec.byDay!.contains(wdOf(c))) continue;
        if (i == 0 && t != null && t.h * 60 + t.mi <= _minOfDay(now)) continue;
        base = c;
        break;
      }
    } else if (rec.freq == 'monthly' && rec.day != null) {
      var y = today.year, mo = today.month;
      var c = DateTime(y, mo, math.min(rec.day!, daysInMonth(y, mo)));
      if (c.isBefore(today) || (c.isAtSameMomentAs(today) && t != null && t.h * 60 + t.mi <= _minOfDay(now))) {
        mo++;
        if (mo > 12) {
          mo = 1;
          y++;
        }
        c = DateTime(y, mo, math.min(rec.day!, daysInMonth(y, mo)));
      }
      base = c;
    } else {
      base = today;
    }
  }
  if (base == null && t == null) return const Resolved();
  if (base == null) {
    base = today;
    if (t!.h * 60 + t.mi < _minOfDay(now)) {
      base = addDays(today, 1);
      rolled = true;
    }
  }
  if (t == null) return Resolved(due: base, allDay: true, hasDate: true);
  final due = DateTime(base.year, base.month, base.day, t.h, t.mi);
  if (rec != null && due.isBefore(now.subtract(const Duration(minutes: 1))) && !(d != null && d.kind == 'ymd')) {
    return Resolved(due: nextOccurrenceDate(due, rec, now), hasDate: true, hasTime: true, rolled: true);
  }
  return Resolved(due: due, hasDate: d != null || spec.rel != null, hasTime: true, rolled: rolled);
}

DateTime _stepOnce(DateTime d, Recurrence rec) {
  if (rec.freq == 'daily') return addDays(d, 1);
  if (rec.freq == 'weekly') {
    if (rec.byDay != null && rec.byDay!.isNotEmpty) {
      var c = addDays(d, 1);
      for (var i = 0; i < 8 && !rec.byDay!.contains(wdOf(c)); i++) {
        c = addDays(c, 1);
      }
      return c;
    }
    return addDays(d, 7);
  }
  if (rec.freq == 'monthly') {
    final day = rec.day ?? d.day;
    var y = d.year, mo = d.month + 1;
    if (mo > 12) {
      mo = 1;
      y++;
    }
    return DateTime(y, mo, math.min(day, daysInMonth(y, mo)), d.hour, d.minute);
  }
  return addDays(d, 1);
}

DateTime nextOccurrenceDate(DateTime from, Recurrence rec, DateTime after) {
  var d = from;
  var guard = 0;
  do {
    d = _stepOnce(d, rec);
  } while (!d.isAfter(after) && ++guard < 2000);
  return d;
}

// =================================================================== título
final List<RegExp> _titleLead = [
  RegExp(r'^(?:e\s+)?(?:me\s+)?(?:lembr(?:e|a|ar)(?:-me)?|lembrete)(?:\s+me)?(?:\s+(?:de|que|para|da|do))?\b'),
  RegExp(r'^(?:me\s+)?avis(?:e|a|ar)(?:-me)?(?:\s+(?:de|que|para))?\b'),
  RegExp(r'^(?:agend(?:e|a|ar)|marqu?e|marc(?:a|ar)|registr(?:e|a|ar)|anot(?:e|a|ar)|adicion(?:e|a|ar)|inclu(?:a|i|ir)|coloqu?e|bot(?:e|a))(?:\s+(?:na|em)\s+(?:minha\s+)?agenda)?(?:\s+(?:que|uma|um|para|de))?\b'),
  RegExp(r'^cri(?:e|a|ar)(?:\s+(?:uma|um))?(?:\s+(?:nova|novo))?(?:\s+(?:tarefa|lembrete|compromisso|evento|pendencia))?(?:\s+(?:de|para|chamad[ao]|que))?\b'),
  RegExp(r'^(?:nova|novo)\s+(?:tarefa|lembrete|compromisso|evento|pendencia)(?:\s+(?:de|para))?\b'),
  RegExp(r'^(?:tarefa|lembrete|pendencia)(?:\s*:)?(?:\s+(?:de|para))?\b'),
  RegExp(r'^(?:eu\s+)?(?:preciso|tenho\s+que|tenho\s+de|devo|vou\s+ter\s+que)(?:\s+de)?\b'),
  RegExp(r'^(?:de|que|para)\b'),
];
final RegExp _titleTrail = RegExp(r'(?:\s+(?:para|pra|no|na|em|de|do|da|as|e|com|que|me\s+lembre|me\s+avise|lembre-me))+\s*$');
final RegExp _lead = RegExp(r'^[\s,;:.!?-]+');
final RegExp _trail = RegExp(r'[\s,;:.!?-]+$');

String cleanTitle(String s) {
  var t = s
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAllMapped(RegExp(r'\s+([,;:.!?])'), (m) => m.group(1)!)
      .replaceFirst(_lead, '')
      .trim();
  for (var guard = 0; guard < 8; guard++) {
    final before = t;
    for (final re in _titleLead) {
      final m = re.firstMatch(fold(t));
      if (m != null && m.end > 0) t = t.substring(m.end).replaceFirst(_lead, '');
    }
    t = t.replaceFirst(_trail, '');
    final tm = _titleTrail.firstMatch(fold(t));
    if (tm != null) t = t.substring(0, tm.start);
    t = t.replaceFirst(_trail, '').replaceAllMapped(RegExp(r'([,;])\s*[,;]+'), (m) => m.group(1)!).trim();
    if (t == before) break;
  }
  return t.isEmpty ? '' : t[0].toUpperCase() + t.substring(1);
}

// ================================================================ intenções
class Intent {
  final String type;
  String title = '';
  WhenSpec? when;
  List<int>? reminders;
  Recurrence? recurrence;
  String kind = 'task';
  bool reminderVerb = false;
  String? error;
  String range = 'pending';
  String? date;
  String target = '';
  WhenSpec? from;
  WhenSpec? to;
  int? shift;
  List<int>? minutes;
  bool? enable;
  String? time;
  bool missing = false;
  String? message;
  Intent(this.type);
}

final RegExp _reWake = RegExp(r'^\s*(?:(?:ok|ei|ola|oi|e\s+ai|alo|hey)[\s,]+)?jarvis\b[\s,!.:;-]*');
final RegExp _rePolite = RegExp(r'[,]?\s*\b(?:por\s+favor|por\s+gentileza|se\s+puder)\b');
final RegExp _reUndo = RegExp(r'^(?:desfaz(?:er|a)?|desfaca|volta(?:r)?(?:\s+atras)?|anula(?:r)?)(?:\s+(?:isso|a\s+ultima(?:\s+acao)?|o\s+ultimo))?\s*[.!]?\s*$|^(?:cancel(?:a|e|ar))\s+(?:isso|a\s+ultima(?:\s+acao)?)\s*[.!]?\s*$');
final RegExp _reHelp = RegExp(r'^(?:ajuda|socorro|o\s+que\s+voce\s+(?:faz|sabe\s+fazer|pode\s+fazer)|quais\s+(?:sao\s+)?(?:os\s+)?comandos|comandos|como\s+(?:funciona|te\s+uso|usar))\b');
final RegExp _reTimeQ = RegExp(r'^(?:que\s+horas\s+(?:sao|e)|me\s+diga\s+as\s+horas|horas)\s*[?.!]?\s*$');
final RegExp _reDateQ = RegExp(r'^(?:que\s+dia\s+(?:e\s+)?hoje|qual\s+(?:e\s+)?a\s+data(?:\s+de\s+hoje)?|que\s+data\s+e\s+hoje)\s*[?.!]?\s*$');
final RegExp _reSummaryOff = RegExp(r'\b(?:desativ|deslig|cancel|par[ae]|interromp|suspend)\w*\s+(?:o\s+)?resumo');
final RegExp _reSummaryVerb = RegExp(r'\b(?:apresente|apresenta|leia|le|mostre|mostra|diga|diz|fale|fala|resuma|resume|informe|liste|repasse|repassa|me\s+de|me\s+passe|me\s+passa)\b');
final RegExp _reSummaryObj = RegExp(r'\b(?:tarefas|agenda|compromissos|pendencias|programacao)\b');
final RegExp reQuery = RegExp(r'^(?:(?:o\s+)?que\s+(?:eu\s+)?(?:tenho|tem|ha|temos|esta\s+marcado|esta\s+agendado)|quais?\s+(?:sao\s+|e\s+)?(?:as\s+|os\s+)?(?:minhas|meus|as|os|tarefas|compromissos)|qual\s+(?:e\s+)?(?:a\s+)?minha\s+agenda|(?:me\s+)?(?:mostre|mostra|liste|lista|listar|leia|le|diga|diz|fale|fala|informe|consulte|consultar|veja|repasse|resuma)\b|(?:como\s+(?:esta|e)\s+)?(?:a\s+)?minha\s+agenda|minhas\s+tarefas|meus\s+compromissos|tenho\s+(?:algo|alguma\s+coisa|algum|alguma|tarefas?|compromissos?|reuni)|agenda\s+de|quantas\s+tarefas)');
final RegExp _reComplete = RegExp(r'^(?:pode\s+)?(?:conclu(?:a|i|ir|ida|ido)|finaliz(?:e|a|ar)|termin(?:e|a|ar|ei)|complet(?:e|a|ar)|(?:dar|de|da)\s+baixa(?:\s+n[ao]s?)?|ja\s+(?:fiz|fizemos|terminei|conclui|resolvi|liguei|paguei|enviei|mandei|comprei|entreguei|falei)|fiz|feito|resolvi)\b');
final RegExp _reCompleteMark = RegExp(r'^(marqu?e|marca|marcar|coloqu?e|deixe)\b(.*?)\bcomo\s+(?:feit|conclu|realiz|pront)\w*');
final RegExp _reCancel = RegExp(r'^(?:cancel(?:e|a|ar)|exclu(?:a|i|ir)|apag(?:ue|a|ar)|remov(?:a|e|er)|delet(?:e|a|ar)|desmarqu?e|desmarc(?:a|ar)|tir(?:e|a|ar))\b');
final RegExp _reResched = RegExp(r'^(?:transfir(?:a|o)|transfer(?:e|ir)|mud(?:e|a|ar)|remarqu?e|remarc(?:a|ar)|adi(?:e|a|ar)|pass(?:e|a|ar)|mov(?:a|e|er)|alter(?:e|a|ar)|reagend(?:e|a|ar)|empurr(?:e|a|ar)|jog(?:ue|a|ar)|antecip(?:e|a|ar)|troqu?e|troca|trocar)\b');
final RegExp _reschedLoose = RegExp(r'^(?:pass(?:e|a|ar)|mov(?:a|e|er)|jog(?:ue|a|ar)|troqu?e|troca|trocar)$');
final RegExp _reShift = RegExp(r'\b(?:em|por|mais)?\s*(' + _num + r'|meia)\s*(minutos?|mins?|horas?|dias?|semanas?)(\s+e\s+meia)?\b');
final RegExp reEvent = RegExp(r'\b(?:reuniao|reunioes|consulta|compromisso|encontro|almoco|jantar|visita|evento|call|entrevista|audiencia|aula|dentista|medico|exame|agend(?:e|a|ar)|marqu?e|marc(?:a|ar))\b');

String _stripEnd(String s) => s.trim().replaceFirst(RegExp(r'[?!.]+$'), '').trim();

/// Interpreta um comando falado ou digitado.
Intent parse(String text, DateTime now) {
  final raw = text.trim();
  final w = Work(raw);
  w.take(_reWake);
  while (w.take(_rePolite) != null) {}
  final f = _stripEnd(w.f);
  if (f.isEmpty) return Intent('empty');
  if (_reUndo.hasMatch(f)) return Intent('undo');
  if (_reHelp.hasMatch(f)) return Intent('help');
  if (_reTimeQ.hasMatch(f)) return Intent('time');
  if (_reDateQ.hasMatch(f)) return Intent('date');
  if (_reSummaryOff.hasMatch(f)) return Intent('summary')..enable = false;
  final isDaily = _rcDaily.hasMatch(f) || RegExp(r'\btoda\s+manha\b').hasMatch(f);
  if (RegExp(r'\bresumo\s+diario\b').hasMatch(f) || (isDaily && _reSummaryVerb.hasMatch(f) && _reSummaryObj.hasMatch(f))) {
    w.take(_rcDaily);
    final when = extractWhen(w);
    if (when.error != null) return Intent('error')..message = when.error;
    return Intent('summary')
      ..enable = true
      ..time = when.time == null ? null : '${pad(when.time!.h)}:${pad(when.time!.mi)}';
  }

  final leadLen = RegExp(r'^\s*').firstMatch(w.f)!.group(0)!.length;
  final body = Work(w.rest().substring(leadLen));
  final bf = body.f.trim();
  if (reQuery.hasMatch(bf)) return _parseQuery(body, bf, now);

  final off = body.f.length - body.f.trimLeft().length;
  Work after(String m0) => Work(body.orig.substring(math.min(body.orig.length, off + m0.length)));
  RegExpMatch? m;
  if ((m = _reCompleteMark.firstMatch(bf)) != null) {
    final s = off + m!.group(1)!.length;
    return _withTarget(Intent('complete'), Work(body.orig.substring(s, s + m.group(2)!.length)));
  }
  if ((m = _reComplete.firstMatch(bf)) != null) return _withTarget(Intent('complete'), after(m!.group(0)!));
  if ((m = _reCancel.firstMatch(bf)) != null) return _withTarget(Intent('cancel'), after(m!.group(0)!));
  if ((m = _reResched.firstMatch(bf)) != null) {
    final verb = m!.group(0)!;
    final r = _parseReschedule(body.orig.substring(math.min(body.orig.length, off + verb.length)), verb);
    if (r != null) return r;
    if (!_reschedLoose.hasMatch(verb)) return _withTarget(Intent('reschedule')..missing = true, after(verb));
  }
  return _parseCreate(body, raw);
}

Intent _withTarget(Intent it, Work w) {
  final when = extractWhen(w);
  it.target = cleanTitle(w.rest().replaceAll(RegExp(r'\b(?:como\s+)?(?:feit[ao]|conclu[ií]d[ao])\b', caseSensitive: false), ''));
  it.from = (when.date != null || when.time != null) ? when : null;
  return it;
}

Intent? _parseReschedule(String after, String verb) {
  final fa = fold(after);
  final cuts = RegExp(r'\b(?:para|pra|pro)\b').allMatches(fa).map((x) => x.start).toList();
  for (var i = cuts.length - 1; i >= 0; i--) {
    final right = Work(after.substring(cuts[i]).replaceFirst(RegExp(r'^\s*\S+'), ''));
    final rem = extractReminders(right);
    final when = extractWhen(right);
    if (rem.list != null || rem.none) {
      return _withTarget(Intent('setReminder')..minutes = rem.none ? <int>[] : rem.list, Work(after.substring(0, cuts[i])));
    }
    if (when.any || when.error != null) {
      final left = after.substring(0, cuts[i]).replaceFirst(RegExp(r'\b(?:o\s+horario|a\s+data|o\s+dia)\s+(?:d[aoe]s?)\b', caseSensitive: false), '');
      return _withTarget(Intent('reschedule')..to = when, Work(left));
    }
  }
  if (RegExp(r'^(?:adi|empurr|atras)').hasMatch(verb)) {
    final w = Work(after);
    final sm = w.take(_reShift);
    if (sm != null) {
      final g1 = sm.group(1)!, g2 = sm.group(2)!;
      final factor = g2[0] == 'h' ? 60 : g2[0] == 'd' ? 1440 : g2[0] == 's' ? 10080 : 1;
      final n = g1 == 'meia' ? 30 : toNum(g1) * factor + (sm.group(3) != null ? 30 : 0);
      return _withTarget(Intent('reschedule')..shift = n, w);
    }
  }
  return null;
}

Intent _parseQuery(Work w, String f, DateTime now) {
  final it = Intent('query');
  if (RegExp(r'\batrasad').hasMatch(f)) {
    it.range = 'overdue';
  } else if (RegExp(r'\bconclu|\bfeitas\b|\bfinalizad').hasMatch(f)) {
    it.range = 'done';
  } else if (RegExp(r'\b(?:proxima\s+semana|semana\s+que\s+vem)\b').hasMatch(f)) {
    it.range = 'nextweek';
  } else if (RegExp(r'\bsemana\b').hasMatch(f)) {
    it.range = 'week';
  } else {
    final when = extractWhen(w);
    if (when.date != null) {
      final r = resolveWhen(WhenSpec(date: when.date), now, null);
      if (r.due != null) {
        it.range = 'day';
        it.date = dayKey(r.due!);
      }
    }
  }
  return it;
}

Intent _parseCreate(Work w, String raw) {
  final rem = extractReminders(w);
  final rec = extractRecurrence(w);
  final when = extractWhen(w);
  final title = cleanTitle(w.rest());
  final fr = fold(raw);
  if (title.isEmpty && (rem.list != null || rem.none) && !when.any && rec == null) {
    return Intent('setReminder')..minutes = rem.none ? <int>[] : rem.list;
  }
  return Intent('create')
    ..title = title
    ..when = when
    ..reminders = rem.none ? <int>[] : rem.list
    ..recurrence = (rec != null && rec.error == null) ? rec : null
    ..kind = reEvent.hasMatch(fr) ? 'event' : 'task'
    ..reminderVerb = RegExp(r'\b(?:lembr|avis|alert|notifiq)').hasMatch(fr)
    ..error = when.error ?? rec?.error;
}

// ============================================================ busca de alvo
final Set<String> _stop = ('a o as os de da do das dos para pra pro com em no na nos nas um uma uns umas que e minha meu minhas meus '
        'sua seu tarefa tarefas compromisso lembrete isso essa esse esta este aquela aquele feita feito concluida concluido como '
        'agenda la ja hoje amanha ate sobre aquilo')
    .split(' ')
    .toSet();
List<String> tokens(String s) => fold(s).split(RegExp(r'[^a-z0-9]+')).where((x) => x.length >= 3 && !_stop.contains(x)).toList();
double _tokMatch(String a, String b) {
  if (a == b) return 1;
  final n = math.min(a.length, b.length);
  if (n >= 5 && a.substring(0, 5) == b.substring(0, 5)) return 0.9;
  if (n >= 4 && a.substring(0, 4) == b.substring(0, 4)) return 0.6;
  return 0;
}

double scoreTask(List<String> q, Task task) {
  if (q.isEmpty) return 0;
  final tt = tokens('${task.title} ${task.description}');
  var s = 0.0;
  for (final a in q) {
    var best = 0.0;
    for (final b in tt) {
      best = math.max(best, _tokMatch(a, b));
    }
    s += best;
  }
  return s / q.length;
}

// ============================================================= textos/fala
String atTime(DateTime d) {
  final h = d.hour, m = d.minute;
  if (h == 12 && m == 0) return 'ao meio-dia';
  if (h == 0 && m == 0) return 'à meia-noite';
  final hh = m == 0 ? '$h${h == 1 ? ' hora' : ' horas'}' : (m == 30 ? '$h e meia' : '$h e ${pad(m)}');
  return (h == 1 ? 'à ' : 'às ') + hh;
}

String dayLabel(DateTime d, DateTime now) {
  final diff = dayDiff(d, now);
  if (diff == 0) return 'hoje';
  if (diff == 1) return 'amanhã';
  if (diff == 2) return 'depois de amanhã';
  if (diff == -1) return 'ontem';
  if (diff > 2 && diff < 7) return '${weekdayFull[wdOf(d)]}, dia ${d.day}';
  return 'dia ${d.day} de ${monthFull[d.month - 1]}${d.year != now.year ? ' de ${d.year}' : ''}';
}

String describeWhen(Task task, DateTime now) {
  final d = task.due;
  if (d == null) return 'sem data definida';
  final lbl = dayLabel(d, now);
  return task.allDay ? '$lbl, sem horário' : lbl + (RegExp(r'dia \d').hasMatch(lbl) ? ', ' : ' ') + atTime(d);
}

String describeLead(int min) {
  if (min == 0) return 'na hora';
  if (min % 1440 == 0) return '${min ~/ 1440}${min == 1440 ? ' dia' : ' dias'} antes';
  if (min % 60 == 0) return '${min ~/ 60}${min == 60 ? ' hora' : ' horas'} antes';
  if (min > 60 && min % 30 == 0) return '${min ~/ 60} hora${min >= 120 ? 's' : ''} e meia antes';
  return '$min minutos antes';
}

String describeRecurrence(Recurrence? r) {
  if (r == null) return '';
  if (r.freq == 'daily') return 'todos os dias';
  if (r.freq == 'monthly') return r.day != null ? 'todo dia ${r.day}' : 'todo mês';
  if (r.freq == 'weekly') {
    if (r.byDay != null && r.byDay!.join(',') == '1,2,3,4,5') return 'de segunda a sexta';
    if (r.byDay != null && r.byDay!.isNotEmpty) return 'toda ${r.byDay!.map((d) => weekdayFull[d].replaceAll('-feira', '')).join(' e ')}';
    return 'toda semana';
  }
  return '';
}

String listJoin(List<String> a) {
  if (a.length <= 1) return a.join();
  return '${a.sublist(0, a.length - 1).join('; ')}; e ${a.last}';
}

// ==================================================================== dados
String _iso(DateTime d) => d.toUtc().toIso8601String();
String _newId(math.Random r) => 't${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${r.nextInt(1 << 30).toRadixString(36)}';

class Task {
  String id, title, description, type;
  String? dueAt;
  bool allDay;
  String timezone;
  List<int> reminderOffsetsMinutes;
  Recurrence? recurrenceRule;
  String status, priority, createdAt, updatedAt, source;
  String? completedAt;
  String? lastNotificationAt;

  Task({
    required this.id,
    required this.title,
    this.description = '',
    this.type = 'task',
    this.dueAt,
    this.allDay = false,
    this.timezone = 'America/Sao_Paulo',
    List<int>? reminderOffsetsMinutes,
    this.recurrenceRule,
    this.status = 'pending',
    this.priority = 'normal',
    required this.createdAt,
    required this.updatedAt,
    this.completedAt,
    this.source = 'voice',
    this.lastNotificationAt,
  }) : reminderOffsetsMinutes = reminderOffsetsMinutes ?? <int>[];

  DateTime? get due => dueAt == null ? null : DateTime.parse(dueAt!).toLocal();

  Map<String, dynamic> toJson() => {
        'id': id, 'title': title, 'description': description, 'type': type, 'dueAt': dueAt, 'allDay': allDay,
        'timezone': timezone, 'reminderOffsetsMinutes': reminderOffsetsMinutes, 'recurrenceRule': recurrenceRule?.toJson(),
        'status': status, 'priority': priority, 'createdAt': createdAt, 'updatedAt': updatedAt, 'completedAt': completedAt,
        'source': source, 'lastNotificationAt': lastNotificationAt,
      };

  static Task fromJson(Map<String, dynamic> j, String nowIso) {
    String? due = j['dueAt'] as String?;
    if (due != null && DateTime.tryParse(due) == null) due = null;
    final st = j['status'];
    return Task(
      id: (j['id'] ?? 't${nowIso.hashCode}').toString(),
      title: (j['title'] ?? '(sem título)').toString(),
      description: (j['description'] ?? '').toString(),
      type: j['type'] == 'event' ? 'event' : 'task',
      dueAt: due,
      allDay: j['allDay'] == true,
      timezone: (j['timezone'] ?? 'America/Sao_Paulo').toString(),
      reminderOffsetsMinutes: ((j['reminderOffsetsMinutes'] as List?) ?? const []).whereType<num>().map((e) => e.toInt()).where((e) => e >= 0).toList(),
      recurrenceRule: Recurrence.fromJson(j['recurrenceRule']),
      status: (st == 'completed' || st == 'cancelled') ? st as String : 'pending',
      priority: (j['priority'] ?? 'normal').toString(),
      createdAt: (j['createdAt'] ?? nowIso).toString(),
      updatedAt: (j['updatedAt'] ?? nowIso).toString(),
      completedAt: j['completedAt'] as String?,
      source: (j['source'] ?? 'manual').toString(),
      lastNotificationAt: j['lastNotificationAt'] as String?,
    );
  }
}

class JarvisSettings {
  String voiceName = '';
  String voiceLocale = '';
  double rate = 0.48; // escala do Android: 0,5 = normal
  double pitch = 0.9;
  bool honorific = true;
  bool askLead = true;
  int defaultLead = 15;
  bool followUp = true;
  bool summaryEnabled = false;
  String summaryTime = '08:00';

  Map<String, dynamic> toJson() => {
        'voiceName': voiceName, 'voiceLocale': voiceLocale, 'rate': rate, 'pitch': pitch, 'honorific': honorific,
        'askLead': askLead, 'defaultLead': defaultLead, 'followUp': followUp, 'summaryEnabled': summaryEnabled, 'summaryTime': summaryTime,
      };
  static JarvisSettings fromJson(dynamic j) {
    final s = JarvisSettings();
    if (j is! Map) return s;
    s.voiceName = (j['voiceName'] ?? '').toString();
    s.voiceLocale = (j['voiceLocale'] ?? '').toString();
    s.rate = (j['rate'] as num?)?.toDouble() ?? s.rate;
    s.pitch = (j['pitch'] as num?)?.toDouble() ?? s.pitch;
    s.honorific = j['honorific'] as bool? ?? true;
    s.askLead = j['askLead'] as bool? ?? true;
    s.defaultLead = (j['defaultLead'] as num?)?.toInt() ?? 15;
    s.followUp = j['followUp'] as bool? ?? true;
    s.summaryEnabled = j['summaryEnabled'] as bool? ?? false;
    s.summaryTime = (j['summaryTime'] ?? '08:00').toString();
    return s;
  }
}

/// Armazenamento: no app, SharedPreferences; nos testes, memória.
abstract class JarvisStore {
  Future<String?> read(String key);
  Future<bool> write(String key, String value);
}

class MemoryStore implements JarvisStore {
  final Map<String, String> data = {};
  bool failWrites = false;
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<bool> write(String key, String value) async {
    if (failWrites) return false;
    data[key] = value;
    return true;
  }
}

class Reply {
  final String speech;
  final String kind; // ok | question | info | error
  final bool changed;
  final String? taskId;
  final Intent? query;
  final List<String> ids;
  const Reply(this.speech, [this.kind = 'ok', this.changed = false, this.taskId, this.query, this.ids = const []]);
}

class PlannedNotice {
  final int id;
  final DateTime at;
  final String title, body, payload;
  const PlannedNotice(this.id, this.at, this.title, this.body, this.payload);
}

class _Pending {
  final String type; // lead | choose | when | title | past
  DateTime at;
  final String? taskId;
  final List<String> ids;
  final String? action;
  final Intent? payload;
  final _Draft? draft;
  _Pending(this.type, this.at, {this.taskId, this.ids = const [], this.action, this.payload, this.draft});
}

class _Draft {
  String title;
  DateTime? due;
  bool allDay, rolled, reminderVerb;
  List<int>? reminders;
  Recurrence? recurrence;
  String kind, source;
  _Draft({required this.title, this.due, this.allDay = false, this.rolled = false, this.reminders, this.recurrence, this.kind = 'task', this.reminderVerb = false, this.source = 'voice'});
  _Draft copy() => _Draft(title: title, due: due, allDay: allDay, rolled: rolled, reminders: reminders, recurrence: recurrence, kind: kind, reminderVerb: reminderVerb, source: source);
}

// ==================================================================== motor
class JarvisEngine {
  final JarvisStore store;
  final DateTime Function() clock;
  final math.Random rand;
  List<Task> tasks = [];
  JarvisSettings settings = JarvisSettings();
  String? loadError;
  final List<MapEntry<String, String>> _undo = [];
  String? _lastTaskId;
  DateTime? _lastAt;
  _Pending? _pending;
  final Map<String, int> _lastPick = {};

  JarvisEngine._(this.store, this.clock, this.rand);

  static Future<JarvisEngine> open(JarvisStore store, {DateTime Function()? now, math.Random? random}) async {
    final e = JarvisEngine._(store, now ?? DateTime.now, random ?? math.Random());
    await e._load();
    return e;
  }

  Future<void> _load() async {
    final nowIso = _iso(clock());
    final raw = await store.read(keyTasks);
    if (raw != null && raw.isNotEmpty) {
      try {
        final arr = jsonDecode(raw);
        if (arr is List) {
          tasks = arr.whereType<Map>().map((m) => Task.fromJson(Map<String, dynamic>.from(m), nowIso)).toList();
        } else {
          throw const FormatException('não é lista');
        }
      } catch (_) {
        await store.write('$keyTasks-corrompido-${DateTime.now().millisecondsSinceEpoch}', raw);
        loadError = 'corrupt';
        tasks = [];
      }
    }
    final s = await store.read(keySettings);
    if (s != null) {
      try {
        settings = JarvisSettings.fromJson(jsonDecode(s));
      } catch (_) {
        settings = JarvisSettings();
      }
    }
  }

  bool get hasPending => _pending != null;
  bool get canUndo => _undo.isNotEmpty;
  void clearPending() => _pending = null;

  static const _ph = {
    'ack': ['Anotado', 'Registrado', 'Feito', 'Certamente', 'Pronto', 'Entendido'],
    'done': ['Concluída', 'Marcada como concluída', 'Feito, concluída'],
    'none': ['Não encontrei', 'Não localizei'],
  };
  String _pick(String key) {
    final a = _ph[key]!;
    var i = rand.nextInt(a.length);
    if (a.length > 1 && i == _lastPick[key]) i = (i + 1) % a.length;
    _lastPick[key] = i;
    return a[i];
  }

  String get _sir => settings.honorific ? ', senhor' : '';

  String _encode() => jsonEncode(tasks.map((t) => t.toJson()).toList());
  List<Task> _decode(String s) {
    final nowIso = _iso(clock());
    return (jsonDecode(s) as List).map((m) => Task.fromJson(Map<String, dynamic>.from(m as Map), nowIso)).toList();
  }

  Future<bool> _persist() async {
    try {
      final json = _encode();
      final ok = await store.write(keyTasks, json);
      if (!ok) return false;
      return await store.read(keyTasks) == json;
    } catch (_) {
      return false;
    }
  }

  Future<bool> saveSettings() async {
    try {
      final j = jsonEncode(settings.toJson());
      return await store.write(keySettings, j);
    } catch (_) {
      return false;
    }
  }

  Future<bool> _commit(String label, void Function() fn) async {
    final before = _encode();
    fn();
    if (!await _persist()) {
      tasks = _decode(before);
      return false;
    }
    _undo.add(MapEntry(label, before));
    if (_undo.length > 30) _undo.removeAt(0);
    return true;
  }

  Reply _failSave() => const Reply('Não consegui gravar no armazenamento do aparelho. Nada foi alterado.', 'error');
  Task? _find(String? id) {
    for (final t in tasks) {
      if (t.id == id) return t;
    }
    return null;
  }

  List<Task> get _pendingTasks => tasks.where((t) => t.status == 'pending').toList();
  void _setContext(String id) {
    _lastTaskId = id;
    _lastAt = clock();
  }

  Task? _contextTask() {
    if (_lastTaskId == null || _lastAt == null || clock().difference(_lastAt!).inMinutes > 15) return null;
    final t = _find(_lastTaskId);
    return (t != null && t.status == 'pending') ? t : null;
  }

  Task _makeTask(_Draft d, List<int> reminders) {
    final nowIso = _iso(clock());
    return Task(
      id: _newId(rand), title: d.title, type: d.kind, dueAt: d.due == null ? null : _iso(d.due!), allDay: d.allDay,
      reminderOffsetsMinutes: reminders, recurrenceRule: d.recurrence, createdAt: nowIso, updatedAt: nowIso, source: d.source,
    );
  }

  String _norm(String s) => fold(s).replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  Task? _duplicate(String title, String? dueIso) {
    final ft = _norm(title);
    for (final t in _pendingTasks) {
      if (_norm(t.title) == ft && t.dueAt == dueIso) return t;
    }
    return null;
  }

  // ------------------------------------------------------------- criar
  Future<Reply> _finishCreate(_Draft d) async {
    final now = clock();
    final dueIso = d.due == null ? null : _iso(d.due!);
    final dup = _duplicate(d.title, dueIso);
    if (dup != null) {
      _setContext(dup.id);
      return Reply('Essa tarefa já está registrada: ${dup.title}, ${describeWhen(dup, now)}.', 'info', false, dup.id);
    }
    var reminders = d.reminders;
    var ask = false;
    if (d.due == null || d.allDay) {
      reminders = [];
    } else if (reminders == null) {
      if (d.kind == 'event' && !d.reminderVerb) {
        reminders = [settings.defaultLead];
        ask = settings.askLead;
      } else {
        reminders = [0];
      }
    }
    final List<int> rems = reminders ?? <int>[];
    final task = _makeTask(d, rems);
    if (!await _commit('criar "${task.title}"', () => tasks.add(task))) return _failSave();
    _setContext(task.id);
    var s = '${_pick('ack')}$_sir. ${task.title}, ${describeWhen(task, now)}';
    if (task.recurrenceRule != null) s += ', ${describeRecurrence(task.recurrenceRule)}';
    s += '.';
    if (d.rolled && task.recurrenceRule == null) s += ' Como esse horário já passou hoje, considerei amanhã.';
    if (ask) {
      _pending = _Pending('lead', now, taskId: task.id);
      return Reply('$s Aviso ${describeLead(rems.first)}. Deseja outra antecedência?', 'question', true, task.id);
    }
    if (rems.isNotEmpty) {
      s += ' Aviso ${rems.map(describeLead).join(' e ')}.';
    } else if (task.allDay && d.reminderVerb && d.source != 'manual') {
      s += ' Sem horário definido, portanto sem aviso sonoro.';
    }
    return Reply(s, 'ok', true, task.id);
  }

  static final RegExp _junkTitle = RegExp(r'^(?:sim|nao|ok|okay|pode|isso|certo|primeir[ao]|segund[ao]|terceir[ao]|cancelar?|obrigad[ao]|valeu|oi|ola)$');

  Future<Reply> _doCreate(Intent it, String source) async {
    final now = clock();
    if (it.error != null) return Reply('${it.error} Pode repetir com uma data válida?', 'error');
    final r = resolveWhen(it.when!, now, it.recurrence);
    if (r.error != null) return Reply('${r.error} Pode repetir com uma data válida?', 'error');
    final d = _Draft(title: it.title, due: r.due, allDay: r.allDay, rolled: r.rolled, reminders: it.reminders, recurrence: it.recurrence, kind: it.kind, reminderVerb: it.reminderVerb, source: source);
    if (d.recurrence != null && d.due != null) {
      if (d.recurrence!.freq == 'weekly' && d.recurrence!.byDay == null) d.recurrence = Recurrence('weekly', byDay: [wdOf(d.due!)]);
      if (d.recurrence!.freq == 'monthly' && d.recurrence!.day == null) d.recurrence = Recurrence('monthly', day: d.due!.day);
    }
    if (d.title.isNotEmpty && _junkTitle.hasMatch(fold(d.title))) {
      return const Reply('Não entendi o que devo fazer. Pode repetir o comando completo?', 'error');
    }
    if (d.title.isEmpty) {
      if (r.due != null) {
        _pending = _Pending('title', now, draft: d);
        return Reply('Qual é a tarefa$_sir?', 'question');
      }
      return const Reply('Não entendi o que devo registrar. Pode repetir?', 'error');
    }
    if (it.kind == 'event' && r.due == null) {
      _pending = _Pending('when', now, draft: d);
      return Reply('Para quando devo agendar ${d.title}?', 'question');
    }
    if (r.due != null && d.recurrence == null && r.due!.isBefore(now.subtract(const Duration(minutes: 1))) && !(r.allDay && dayDiff(r.due!, now) == 0)) {
      _pending = _Pending('past', now, draft: d);
      return Reply('Essa data já passou: ${dayLabel(r.due!, now)}${r.allDay ? '' : ' ${atTime(r.due!)}'}. Registro para amanhã no mesmo horário?', 'question');
    }
    return _finishCreate(d);
  }

  // ------------------------------------------------------ localizar alvo
  ({Task? task, List<Task>? many, bool empty}) _locate(Intent it) {
    final now = clock();
    var pool = _pendingTasks;
    final q = tokens(it.target);
    if (q.isEmpty && it.from == null) {
      final c = _contextTask();
      return (task: c, many: null, empty: c == null);
    }
    final from = it.from;
    if (from != null) {
      final d = from.date;
      pool = pool.where((t) {
        final td = t.due;
        if (td == null) return false;
        if (d != null && d.kind == 'weekday') return wdOf(td) == d.wd && dayDiff(td, now) >= -1;
        final r = resolveWhen(WhenSpec(date: d, time: from.time, rel: from.rel), now, null);
        final tm = from.time;
        if (r.due == null) return true;
        if (d == null && tm != null) return td.hour == tm.h && td.minute == tm.mi;
        return dayKey(td) == dayKey(r.due!) && (tm == null || (td.hour == tm.h && td.minute == tm.mi));
      }).toList();
    }
    final scored = (q.isNotEmpty ? pool.map((t) => MapEntry(t, scoreTask(q, t))).where((x) => x.value >= 0.5) : pool.map((t) => MapEntry(t, 1.0))).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (scored.isEmpty) return (task: null, many: null, empty: false);
    final top = scored.where((x) => x.value >= scored.first.value - 0.05).toList();
    if (top.length == 1) return (task: top.first.key, many: null, empty: false);
    return (task: null, many: top.take(5).map((x) => x.key).toList(), empty: false);
  }

  Reply _askChoice(String action, List<Task> cands, Intent payload, String verb) {
    final now = clock();
    _pending = _Pending('choose', now, ids: cands.map((t) => t.id).toList(), action: action, payload: payload);
    final opts = <String>[];
    for (var i = 0; i < cands.length; i++) {
      opts.add('${i + 1}, ${cands[i].title}, ${describeWhen(cands[i], now)}');
    }
    return Reply('Encontrei ${cands.length} opções para $verb: ${listJoin(opts)}. Qual delas?', 'question');
  }

  Future<Reply> _withTargetAct(Intent it, String action, String verb) async {
    final r = _locate(it);
    if (r.task != null) return _act(action, r.task!, it);
    if (r.many != null) return _askChoice(action, r.many!, it, verb);
    if (r.empty) return Reply('A qual tarefa$_sir?', 'question');
    return Reply('${_pick('none')} tarefa pendente${it.target.isNotEmpty ? ' com "${it.target}"' : ''}${it.from?.date != null ? ' nessa data' : ''}.', 'error');
  }

  Future<Reply> _act(String action, Task task, Intent it) async {
    final now = clock();
    switch (action) {
      case 'complete': {
        var msg = '';
        final ok = await _commit('concluir "${task.title}"', () {
          task.updatedAt = _iso(now);
          final due = task.due;
          if (task.recurrenceRule != null && due != null) {
            task.dueAt = _iso(nextOccurrenceDate(due, task.recurrenceRule!, now));
            task.completedAt = _iso(now);
            msg = '${_pick('done')}: ${task.title}. Próxima ocorrência: ${describeWhen(task, now)}.';
          } else {
            task.status = 'completed';
            task.completedAt = _iso(now);
            msg = '${_pick('done')}: ${task.title}.';
          }
        });
        if (!ok) return _failSave();
        _setContext(task.id);
        return Reply(msg, 'ok', true, task.id);
      }
      case 'cancel': {
        if (!await _commit('cancelar "${task.title}"', () {
          task.status = 'cancelled';
          task.updatedAt = _iso(now);
        })) return _failSave();
        return Reply('Cancelada: ${task.title}. Se foi engano, diga "desfazer".', 'ok', true, task.id);
      }
      case 'setReminder': {
        if (task.dueAt == null || task.allDay) return Reply('${task.title} não tem horário definido. Informe um horário para eu poder avisar.', 'error');
        final mins = it.minutes ?? <int>[];
        if (!await _commit('aviso de "${task.title}"', () {
          task.reminderOffsetsMinutes = List<int>.from(mins);
          task.updatedAt = _iso(now);
        })) return _failSave();
        _setContext(task.id);
        return Reply(mins.isNotEmpty ? 'Certo. Aviso ${mins.map(describeLead).join(' e ')} de ${task.title}.' : 'Certo. Sem aviso para ${task.title}.', 'ok', true, task.id);
      }
      case 'reschedule': {
        final base = task.due;
        DateTime? due;
        var allDay = task.allDay;
        if (it.shift != null) {
          due = (base ?? now).add(Duration(minutes: it.shift!));
        } else {
          final spec = it.to!;
          final r = resolveWhen(spec, now, null);
          if (r.error != null) return Reply(r.error!, 'error');
          final rel = spec.rel;
          if (spec.time != null && spec.date == null && rel == null) {
            final b = base ?? startOfDay(now);
            due = DateTime(b.year, b.month, b.day, spec.time!.h, spec.time!.mi);
            allDay = false;
          } else if (spec.time == null && (spec.date != null || (rel != null && rel.unit != 'min' && rel.unit != 'h'))) {
            due = r.due;
            if (due != null && base != null && !task.allDay) {
              due = DateTime(due.year, due.month, due.day, base.hour, base.minute);
              allDay = false;
            } else {
              allDay = true;
            }
          } else {
            due = r.due;
            allDay = r.allDay;
          }
        }
        if (due == null) return Reply('Para quando devo transferir ${task.title}?', 'question');
        final newDue = due;
        if (!await _commit('transferir "${task.title}"', () {
          task.dueAt = _iso(newDue);
          task.allDay = allDay;
          task.updatedAt = _iso(now);
          if (!allDay && task.reminderOffsetsMinutes.isEmpty) task.reminderOffsetsMinutes = [task.type == 'event' ? settings.defaultLead : 0];
        })) return _failSave();
        _setContext(task.id);
        var s = 'Transferida: ${task.title}, para ${describeWhen(task, now)}.';
        if (newDue.isBefore(now.subtract(const Duration(minutes: 1)))) s += ' Atenção: essa data já passou.';
        return Reply(s, 'ok', true, task.id);
      }
    }
    return const Reply('Ação desconhecida.', 'error');
  }

  // ----------------------------------------------------------- consultas
  bool inRange(Task t, String range, {String? date}) {
    final now = clock();
    final today = startOfDay(now);
    final d = t.due;
    final p = t.status == 'pending';
    switch (range) {
      case 'day':
        return p && d != null && dayKey(d) == date;
      case 'week':
        return p && d != null && !d.isBefore(today) && d.isBefore(addDays(today, 7));
      case 'nextweek':
        final mon = nextWeekdayDate(now, 1, 'next', null);
        return p && d != null && !d.isBefore(mon) && d.isBefore(addDays(mon, 7));
      case 'overdue':
        return p && d != null && (t.allDay ? startOfDay(d).isBefore(today) : d.isBefore(now));
      case 'done':
        return t.status == 'completed';
      default:
        return p;
    }
  }

  static int sortTasks(Task a, Task b) {
    if (a.dueAt == null && b.dueAt == null) return a.createdAt.compareTo(b.createdAt);
    if (a.dueAt == null) return 1;
    if (b.dueAt == null) return -1;
    final c = a.dueAt!.compareTo(b.dueAt!);
    if (c != 0) return c;
    return a.allDay ? -1 : 1;
  }

  Reply _doQuery(Intent q) {
    final now = clock();
    final items = tasks.where((t) => inRange(t, q.range, date: q.date)).toList()..sort(sortTasks);
    String head;
    if (q.range == 'day') {
      final parts = q.date!.split('-').map(int.parse).toList();
      final lbl = dayLabel(DateTime(parts[0], parts[1], parts[2]), now);
      head = lbl[0].toUpperCase() + lbl.substring(1);
    } else {
      head = const {'week': 'Nos próximos 7 dias', 'nextweek': 'Na próxima semana', 'overdue': 'Atrasadas', 'done': 'Concluídas', 'pending': 'Pendentes'}[q.range] ?? 'Pendentes';
    }
    if (items.isEmpty) {
      final empty = const ['day', 'week', 'nextweek'].contains(q.range) ? 'não há nada agendado' : 'não há nenhuma tarefa';
      return Reply('$head, $empty$_sir.', 'info', false, null, q, const []);
    }
    final sameDay = q.range == 'day';
    const maxRead = 8;
    final parts = items.take(maxRead).map((t) {
      final d = t.due;
      if (d == null) return t.title;
      if (sameDay) return t.allDay ? '${t.title}, sem horário' : '${atTime(d)}, ${t.title}';
      return '${describeWhen(t, now)}, ${t.title}';
    }).toList();
    final n = items.length;
    var s = '$head${sameDay ? (settings.honorific ? ' o senhor tem ' : ' você tem ') : ': '}$n${n == 1 ? ' item' : ' itens'}: ${listJoin(parts)}';
    if (n > maxRead) s += '; e mais ${n - maxRead}';
    return Reply('$s.', 'info', false, null, q, items.map((t) => t.id).toList());
  }

  String summaryText() {
    final now = clock();
    final today = tasks.where((t) => inRange(t, 'day', date: dayKey(now))).toList()..sort(sortTasks);
    final overdue = tasks.where((t) => inRange(t, 'overdue') && dayKey(t.due!) != dayKey(now)).toList();
    final undated = tasks.where((t) => t.status == 'pending' && t.dueAt == null).toList();
    final h = now.hour;
    var s = '${h < 12 ? 'Bom dia' : h < 18 ? 'Boa tarde' : 'Boa noite'}$_sir. ';
    if (today.isNotEmpty) {
      s += 'Hoje há ${today.length}${today.length == 1 ? ' item: ' : ' itens: '}${listJoin(today.take(8).map((t) => (t.allDay ? '' : '${atTime(t.due!)}, ') + t.title).toList())}. ';
    } else {
      s += 'Não há nada agendado para hoje. ';
    }
    if (overdue.isNotEmpty) s += '${overdue.length}${overdue.length == 1 ? ' tarefa atrasada. ' : ' tarefas atrasadas. '}';
    if (undated.isNotEmpty) s += '${undated.length}${undated.length == 1 ? ' pendência sem data.' : ' pendências sem data.'}';
    return s.trim();
  }

  // --------------------------------------------------- respostas pendentes
  static final RegExp _yes = RegExp(r'^(?:sim|pode|pode\s+ser|isso|claro|ok|okay|positivo|confirmo|confirma|esta\s+bom|ta\s+bom|beleza|perfeito|certo|correto|exato|faca\s+isso|por\s+favor)\b');
  static final RegExp _no = RegExp(r'^(?:nao|negativo|deixa|esquece|cancela|cancelar|nenhum|nenhuma|nada)\b');
  static final RegExp _ord = RegExp(r'^(?:(?:a|o|numero|opcao)\s+)?(primeir[ao]|segund[ao]|terceir[ao]|quart[ao]|quint[ao]|um|uma|dois|duas|tres|quatro|cinco|[1-5])\b');
  static const Map<String, int> _ordMap = {'primeir': 1, 'segund': 2, 'terceir': 3, 'quart': 4, 'quint': 5, 'um': 1, 'uma': 1, 'dois': 2, 'duas': 2, 'tres': 3, 'quatro': 4, 'cinco': 5};

  Future<Reply?> _answerPending(String text) async {
    final p = _pending!;
    final now = clock();
    final w = Work(text);
    w.take(_reWake);
    final f = _stripEnd(w.f);
    switch (p.type) {
      case 'lead': {
        final task = _find(p.taskId);
        if (task == null) return null;
        final rem = extractReminders(Work(f), allowBare: true);
        if (rem.none || rem.list != null) {
          _pending = null;
          return _act('setReminder', task, Intent('setReminder')..minutes = rem.none ? <int>[] : rem.list);
        }
        if (RegExp(r'^(?:sim|quero|desejo|outra)\b').hasMatch(f)) {
          _pending = _Pending('lead', now, taskId: task.id);
          return const Reply('Com quanto tempo de antecedência?', 'question');
        }
        if (_no.hasMatch(f) || RegExp(r'^(?:esta\s+bom|ta\s+bom|pode\s+ser|assim\s+mesmo|mantenha|manter|ok)\b').hasMatch(f)) {
          _pending = null;
          return Reply('Mantido: aviso ${task.reminderOffsetsMinutes.map(describeLead).join(' e ')}.', 'ok');
        }
        return null;
      }
      case 'choose': {
        if (_no.hasMatch(f)) {
          _pending = null;
          return const Reply('Certo. Nada foi alterado.', 'ok');
        }
        final cands = p.ids.map(_find).whereType<Task>().where((t) => t.status == 'pending').toList();
        Task? chosen;
        final m = _ord.firstMatch(f);
        if (m != null) {
          final g = m.group(1)!;
          final n = RegExp(r'^\d$').hasMatch(g) ? int.parse(g) : (_ordMap[g.replaceFirst(RegExp(r'[ao]$'), '')] ?? _ordMap[g] ?? 0);
          if (n >= 1 && n <= cands.length) chosen = cands[n - 1];
        }
        if (chosen == null) {
          final q = tokens(f);
          final sc = cands.map((t) => MapEntry(t, scoreTask(q, t))).where((x) => x.value >= 0.5).toList()..sort((a, b) => b.value.compareTo(a.value));
          if (sc.length == 1 || (sc.length > 1 && sc[0].value > sc[1].value + 0.05)) chosen = sc.first.key;
          if (chosen == null) {
            final wh = extractWhen(Work(f));
            if (wh.date != null && wh.date!.kind == 'weekday') {
              final byDay = cands.where((t) => t.due != null && wdOf(t.due!) == wh.date!.wd).toList();
              if (byDay.length == 1) chosen = byDay.first;
            }
          }
        }
        if (chosen == null) {
          if (f.split(RegExp(r'\s+')).length <= 3 && !reQuery.hasMatch(f)) {
            p.at = now;
            return Reply('Não identifiquei a opção. Diga o número, de 1 a ${cands.length}, ou "cancelar".', 'question');
          }
          return null;
        }
        _pending = null;
        return _act(p.action!, chosen, p.payload!);
      }
      case 'when': {
        if (_no.hasMatch(f)) {
          _pending = null;
          return const Reply('Certo, não registrei.', 'ok');
        }
        final ww = Work(text);
        final rem = extractReminders(ww);
        final wh = extractWhen(ww);
        if (!wh.any) return null;
        final r = resolveWhen(wh, now, p.draft!.recurrence);
        if (r.error != null) return Reply('${r.error} Para quando?', 'question');
        _pending = null;
        final d = p.draft!.copy()
          ..due = r.due
          ..allDay = r.allDay
          ..rolled = r.rolled
          ..reminders = rem.list ?? p.draft!.reminders;
        return _finishCreate(d);
      }
      case 'title': {
        if (_no.hasMatch(f) && f.length < 12) {
          _pending = null;
          return const Reply('Certo, não registrei.', 'ok');
        }
        final t = cleanTitle(w.rest());
        if (t.isEmpty) return null;
        _pending = null;
        final d = p.draft!.copy()
          ..title = t
          ..kind = reEvent.hasMatch(fold(t)) ? 'event' : p.draft!.kind;
        return _finishCreate(d);
      }
      case 'past': {
        if (_yes.hasMatch(f)) {
          _pending = null;
          final d = p.draft!.copy()..due = nextOccurrenceDate(p.draft!.due!, const Recurrence('daily'), now);
          return _finishCreate(d);
        }
        if (_no.hasMatch(f)) {
          _pending = null;
          return const Reply('Certo, não registrei.', 'ok');
        }
        return null;
      }
    }
    return null;
  }

  Reply _help() => const Reply(
      'Posso criar tarefas e compromissos, ler sua agenda, concluir, transferir e cancelar tarefas, ajustar avisos e criar repetições. '
      'Por exemplo: "amanhã às 15 horas me lembre de ligar para o contador", "quais são meus compromissos?", '
      '"transfira a reunião de sexta para segunda às 9", "conclua a tarefa do fornecedor" ou "desfazer".',
      'info');

  /// Ponto de entrada: texto falado ou digitado → resposta.
  Future<Reply> handle(String text, {String source = 'text'}) async {
    final now = clock();
    if (_pending != null && now.difference(_pending!.at).inMinutes >= 3) _pending = null;
    if (_pending != null) {
      final r = await _answerPending(text);
      if (r != null) return r;
      _pending = null;
    }
    final it = parse(text, now);
    switch (it.type) {
      case 'empty': {
        return Reply('Pois não$_sir?', 'question');
      }
      case 'undo': {
        if (_undo.isEmpty) return const Reply('Não há nada para desfazer.', 'info');
        final u = _undo.removeLast();
        final cur = _encode();
        tasks = _decode(u.value);
        if (!await _persist()) {
          tasks = _decode(cur);
          _undo.add(u);
          return _failSave();
        }
        _pending = null;
        return Reply('Desfeito: ${u.key}.', 'ok', true);
      }
      case 'help': {
        return _help();
      }
      case 'time': {
        return Reply('São ${atTime(now).replaceFirst(RegExp(r'^(?:às|à|ao)\s+'), '')}.', 'info');
      }
      case 'date': {
        return Reply('Hoje é ${weekdayFull[wdOf(now)]}, ${now.day} de ${monthFull[now.month - 1]} de ${now.year}.', 'info');
      }
      case 'error': {
        return Reply(it.message ?? 'Não entendi.', 'error');
      }
      case 'summary': {
        if (it.enable == false) {
          settings.summaryEnabled = false;
          await saveSettings();
          return const Reply('Resumo diário desativado.', 'ok', true);
        }
        settings.summaryEnabled = true;
        settings.summaryTime = it.time ?? settings.summaryTime;
        if (!await saveSettings()) return _failSave();
        final hm = settings.summaryTime.split(':').map(int.parse).toList();
        return Reply('Resumo diário ativado, todos os dias ${atTime(DateTime(2000, 1, 1, hm[0], hm[1]))}. Uma notificação vai chamar o senhor; ao tocar nela, eu leio a agenda.', 'ok', true);
      }
      case 'query': {
        return _doQuery(it);
      }
      case 'complete': {
        return _withTargetAct(it, 'complete', 'concluir');
      }
      case 'cancel': {
        return _withTargetAct(it, 'cancel', 'cancelar');
      }
      case 'setReminder': {
        return _withTargetAct(it, 'setReminder', 'ajustar o aviso');
      }
      case 'reschedule': {
        if (it.missing) {
          final r = _locate(it);
          final t = r.task?.title ?? 'a tarefa';
          return Reply('Para quando devo transferir $t? Diga, por exemplo: "transfira ${r.task != null ? 'a ${t.toLowerCase()}' : 'a reunião'} para segunda às 9".', 'question');
        }
        return _withTargetAct(it, 'reschedule', 'transferir');
      }
      case 'create': {
        return _doCreate(it, source);
      }
    }
    return const Reply('Não entendi. Pode repetir?', 'error');
  }

  // ------------------------------------------------------ ações da tela
  Future<Reply> setDone(String id, bool done) async {
    final t = _find(id);
    if (t == null) return const Reply('Tarefa não encontrada.', 'error');
    if (done) return _act('complete', t, Intent('complete'));
    if (!await _commit('reabrir "${t.title}"', () {
      t.status = 'pending';
      t.completedAt = null;
      t.updatedAt = _iso(clock());
    })) return _failSave();
    return Reply('Reaberta: ${t.title}.', 'ok', true);
  }

  Future<Reply> remove(String id) async {
    final t = _find(id);
    if (t == null) return const Reply('Tarefa não encontrada.', 'error');
    if (!await _commit('excluir "${t.title}"', () => tasks.removeWhere((x) => x.id == id))) return _failSave();
    return Reply('Excluída: ${t.title}.', 'ok', true);
  }

  Future<Reply> undo() => handle('desfazer');

  /// Avisos a agendar no Android (próximas ocorrências, inclusive de tarefas que se repetem).
  List<PlannedNotice> planNotifications({int max = 60}) {
    final now = clock();
    final out = <PlannedNotice>[];
    for (final t in _pendingTasks) {
      final due = t.due;
      if (due == null || t.allDay || t.reminderOffsetsMinutes.isEmpty) continue;
      final occ = <DateTime>[due];
      if (t.recurrenceRule != null) {
        var d = due;
        for (var i = 0; i < 13; i++) {
          d = _stepOnce(d, t.recurrenceRule!);
          if (d.difference(now).inDays > 31) break;
          occ.add(d);
        }
      }
      for (final o in occ) {
        for (final off in t.reminderOffsetsMinutes) {
          final at = o.subtract(Duration(minutes: off));
          if (!at.isAfter(now)) continue;
          final when = off == 0 ? 'agora' : '${atTime(o)} (${describeLead(off)})';
          out.add(PlannedNotice(0, at, 'JARVIS · Lembrete', '${t.title} — $when', 'task:${t.id}:$off'));
        }
      }
    }
    out.sort((a, b) => a.at.compareTo(b.at));
    final list = out.take(max).toList();
    return [for (var i = 0; i < list.length; i++) PlannedNotice(i + 1, list[i].at, list[i].title, list[i].body, list[i].payload)];
  }

  /// Texto falado quando o usuário toca numa notificação de lembrete.
  String reminderSpeech(String payload) {
    final parts = payload.split(':');
    if (parts.length < 3) return summaryText();
    final t = _find(parts[1]);
    if (t == null || t.status != 'pending') return 'Esse lembrete já foi resolvido.';
    final off = int.tryParse(parts[2]) ?? 0;
    final now = clock();
    return 'Lembrete$_sir: ${t.title}${off == 0 ? '' : ', ${describeWhen(t, now)}'}.';
  }
}
