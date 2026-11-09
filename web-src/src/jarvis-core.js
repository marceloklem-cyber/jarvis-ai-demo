/* JARVIS AI — núcleo 0.7 (sem DOM).
 * Interpreta comandos em português, mantém tarefas, contexto, desfazer, lembretes,
 * recorrência e classificação de vozes. Usado pelo index.html e pelos testes (Node).
 * Datas são calculadas no fuso local do dispositivo (no seu caso, America/Sao_Paulo).
 */
(function (root, factory) {
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  else root.JarvisCore = api;
})(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  const VERSION = '0.7.2';
  const KEY_TASKS = 'jarvis-ai-v07-tasks';
  const KEY_SETTINGS = 'jarvis-ai-v07-settings';
  const KEY_LEGACY = 'jarvis-demo-v03';
  const KEY_LEGACY_VOICE = 'jarvis-voice';

  // ------------------------------------------------------------------ texto
  /** Minúsculas sem acento, preservando o comprimento (1 caractere → 1 caractere). */
  function fold(s) {
    s = String(s == null ? '' : s).normalize('NFC');
    let out = '';
    for (let i = 0; i < s.length; i++) {
      const m = s[i].normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();
      out += m.length === 1 ? m : ' ';
    }
    return out;
  }

  const UNITS = { um: 1, uma: 1, dois: 2, duas: 2, tres: 3, quatro: 4, cinco: 5, seis: 6, sete: 7, oito: 8, nove: 9 };
  const NUMS = Object.assign({}, UNITS, {
    dez: 10, onze: 11, doze: 12, treze: 13, quatorze: 14, catorze: 14, quinze: 15, dezesseis: 16,
    dezessete: 17, dezoito: 18, dezenove: 19, vinte: 20, trinta: 30, quarenta: 40, cinquenta: 50, sessenta: 60
  });
  const TENS = 'vinte|trinta|quarenta|cinquenta';
  const NUM = '(?:\\d{1,3}|(?:' + TENS + ')\\s+e\\s+(?:' + Object.keys(UNITS).join('|') + ')|' +
    Object.keys(NUMS).sort((a, b) => b.length - a.length).join('|') + ')';
  function toNum(str) {
    str = String(str).trim();
    if (/^\d+$/.test(str)) return parseInt(str, 10);
    if (str === 'meia') return 30;
    if (str === 'primeiro') return 1;
    return str.split(/\s+e\s+/).reduce((s, w) => s + (NUMS[w] || 0), 0);
  }

  const WD = ['domingo', 'segunda', 'terca', 'quarta', 'quinta', 'sexta', 'sabado'];
  const WD_ALT = WD.join('|');
  const WD_ANY = '(?:' + WD_ALT + ')s?(?:[- ]feiras?)?';
  const MONTHS = ['janeiro', 'fevereiro', 'marco', 'abril', 'maio', 'junho', 'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro'];
  const WEEKDAY_FULL = ['domingo', 'segunda-feira', 'terça-feira', 'quarta-feira', 'quinta-feira', 'sexta-feira', 'sábado'];
  const MONTH_FULL = ['janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', 'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro'];

  /** Texto em trabalho: casa expressões no texto "dobrado" e remove os trechos do original. */
  class Work {
    constructor(text) {
      this.orig = String(text == null ? '' : text).normalize('NFC');
      this.f = fold(this.orig);
      this.cut = new Array(this.orig.length).fill(false);
    }
    find(re) { return re.exec(this.f); }
    take(re) {
      const m = re.exec(this.f);
      if (m) this.remove(m.index, m[0].length);
      return m;
    }
    remove(i, n) {
      for (let k = i; k < i + n; k++) this.cut[k] = true;
      this.f = this.f.slice(0, i) + ' '.repeat(n) + this.f.slice(i + n);
    }
    rest() {
      let s = '';
      for (let k = 0; k < this.orig.length; k++) s += this.cut[k] ? ' ' : this.orig[k];
      return s;
    }
  }
  const rx = (s) => new RegExp(s);

  // ------------------------------------------------------------- datas
  const pad = (n) => String(n).padStart(2, '0');
  const dayKey = (d) => d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate());
  const startOfDay = (d) => new Date(d.getFullYear(), d.getMonth(), d.getDate());
  const addDays = (d, n) => new Date(d.getFullYear(), d.getMonth(), d.getDate() + n, d.getHours(), d.getMinutes());
  const daysInMonth = (y, m0) => new Date(y, m0 + 1, 0).getDate();
  function validYMD(y, m, d) {
    if (!(m >= 1 && m <= 12 && d >= 1 && d <= 31 && y >= 1970 && y <= 2200)) return false;
    return d <= daysInMonth(y, m - 1);
  }
  function dayDiff(a, b) { return Math.round((startOfDay(a) - startOfDay(b)) / 86400000); }

  // ------------------------------------------------------- lembretes
  const UNIT = '(minutos?|mins?|horas?|hrs?|h|dias?)';
  function unitMinutes(u) { u = u[0]; return u === 'd' ? 1440 : u === 'h' ? 60 : 1; }
  function amountMinutes(numStr, unit, plusHalf) {
    const u = unitMinutes(unit);
    let v = numStr === 'meia' ? (u === 60 ? 30 : null) : toNum(numStr) * u;
    if (v == null) return null;
    if (plusHalf && u === 60) v += 30;
    return v;
  }
  const RM_NONE = /(?:^|[\s,;])(?:sem\s+(?:lembrete|aviso|alerta|avisos|lembretes)|nao\s+(?:precisa\s+|quero\s+)?(?:me\s+)?(?:avisar|lembrar|aviso|lembrete))\b/;
  const RM_AT = /[,;]?\s*(?:\be\s+)?(?:\bme\s+)?\b(?:avise|avisa|avisar|alerte|alerta|lembre|lembra)(?:-me|\s+me)?\s+na\s+hora\b/;
  const RM1 = rx('[,;]?\\s*(?:\\be\\s+)?(?:\\bme\\s+)?\\b(?:avise|avisa|avisar|alerte|alerta|alertar|notifique|notifica|lembre|lembra|lembrar)(?:-me|\\s+me)?\\s+(?:com\\s+)?(' + NUM + '|meia)\\s*' + UNIT + '(\\s+e\\s+meia)?\\s+(?:de\\s+)?(?:antes|antecedencia)\\b');
  const RM2 = rx('[,;]?\\s*(?:\\bcom\\s+)?(?:\\bum\\s+)?\\b(?:lembrete|aviso|alerta)\\s+(?:de\\s+)?(' + NUM + '|meia)\\s*' + UNIT + '(\\s+e\\s+meia)?(?:\\s+(?:de\\s+)?(?:antes|antecedencia))?\\b');
  const RM3 = rx('[,;]?\\s*(?:\\be\\s+)?(?:\\bcom\\s+)?\\b(' + NUM + '|meia)\\s*' + UNIT + '(\\s+e\\s+meia)?\\s+(?:de\\s+)?(?:antes|antecedencia)\\b');
  const RM_BARE = rx('^\\s*(?:com\\s+|so\\s+|apenas\\s+)?(' + NUM + '|meia)\\s*' + UNIT + '(\\s+e\\s+meia)?\\b');

  /** Extrai antecedências. Retorna {list:number[]|null, none:boolean}. */
  function extractReminders(w, allowBare) {
    const list = [];
    let none = false;
    if (w.take(RM_NONE)) none = true;
    if (w.take(RM_AT)) list.push(0);
    for (const re of [RM1, RM2, RM3]) {
      let m;
      while ((m = w.take(re))) {
        const v = amountMinutes(m[1], m[2], !!m[3]);
        if (v != null && v <= 60 * 24 * 30) list.push(v);
      }
    }
    if (allowBare && !list.length) {
      const m = w.take(RM_BARE);
      if (m) { const v = amountMinutes(m[1], m[2], !!m[3]); if (v != null) list.push(v); }
    }
    return { list: list.length ? Array.from(new Set(list)).sort((a, b) => b - a) : null, none };
  }

  // ------------------------------------------------------ recorrência
  const RC_MONTHDAY = /\btodo\s+(?:santo\s+)?dia\s+(\d{1,2})(?:\s+de\s+cada\s+mes|\s+do\s+mes)?\b/;
  const RC_WORKDAYS = /\b(?:todos\s+os\s+dias\s+uteis|(?:nos\s+|em\s+)?dias\s+uteis|de\s+segunda\s+a\s+sexta(?:[- ]feira)?)\b/;
  const RC_WEEKDAYS = rx('\\b(?:todas\\s+as|todos\\s+os|toda|todo|cada)\\s+' + WD_ANY + '(?:\\s*(?:,|e)\\s*(?:as\\s+|os\\s+)?' + WD_ANY + ')*');
  const RC_DAILY = /\b(?:todos\s+os\s+dias|todo\s+(?:santo\s+)?dia|diariamente|cada\s+dia|toda\s+(?:manha|tarde|noite))\b/;
  const RC_WEEKLY = /\b(?:toda\s+semana|todas\s+as\s+semanas|semanalmente|uma\s+vez\s+por\s+semana)\b/;
  const RC_MONTHLY = /\b(?:todo\s+mes|todos\s+os\s+meses|mensalmente|uma\s+vez\s+por\s+mes)\b/;

  function extractRecurrence(w) {
    let m;
    if ((m = w.take(RC_MONTHDAY))) {
      const d = parseInt(m[1], 10);
      return d >= 1 && d <= 31 ? { freq: 'monthly', day: d } : { error: 'Dia do mês inválido: ' + d + '.' };
    }
    if (w.take(RC_WORKDAYS)) return { freq: 'weekly', byDay: [1, 2, 3, 4, 5] };
    if ((m = w.take(RC_WEEKDAYS))) {
      const days = [];
      const re = new RegExp('(' + WD_ALT + ')', 'g');
      let d;
      while ((d = re.exec(m[0]))) days.push(WD.indexOf(d[1]));
      return { freq: 'weekly', byDay: Array.from(new Set(days)).sort() };
    }
    if (w.take(RC_DAILY)) return { freq: 'daily' };
    if (w.take(RC_WEEKLY)) return { freq: 'weekly' };
    if (w.take(RC_MONTHLY)) return { freq: 'monthly' };
    return null;
  }

  // ------------------------------------------------------- data/hora
  const RE_REL = rx('\\b(?:daqui\\s+a|daqui|dentro\\s+de|em)\\s+(' + NUM + '|meia)\\s*(minutos?|mins?|horas?|dias?|semanas?|meses|mes)(\\s+e\\s+meia)?\\b');
  const RE_DAYWORDS = [
    [/\bdepois\s+de\s+amanha\b/, 2], [/\banteontem\b/, -2], [/\bamanha\b/, 1], [/\bhoje\b/, 0], [/\bontem\b/, -1]
  ];
  const RE_NUMDATE = /\b(?:(?:no\s+|para\s+o\s+)?dia\s+)?(\d{1,2})[/-](\d{1,2})(?:[/-](\d{2,4}))?\b/;
  const RE_TXTDATE = rx('\\b(?:(?:no\\s+|para\\s+o\\s+)?dia\\s+)?(\\d{1,2}|primeiro|' + NUM + ')\\s+de\\s+(' + MONTHS.join('|') + ')(?:\\s+(?:de\\s+)?(\\d{4}))?\\b');
  const RE_DAYN = /\b(?:(?:no|para\s+o)\s+)?dia\s+(\d{1,2}|primeiro)\b/;
  const RE_WEEKDAY = rx('\\b(?:(na|no|nesta|neste|esta|este|essa|nessa|nesse|desta|proxima|proximo|na\\s+proxima|no\\s+proximo|para|pra)\\s+)?(' + WD_ALT + ')(?:[- ]feira)?(\\s+que\\s+vem)?\\b');
  const RE_NEXTWEEK = /\b(?:na\s+|para\s+a\s+)?(?:proxima\s+semana|semana\s+que\s+vem)\b/;

  const PRE = '(?:(?:as|a|pelas|pela|para\\s+as|ate\\s+as|la\\s+pelas)\\s+)?';
  const RE_T1 = rx('\\b' + PRE + '(\\d{1,2})\\s*(?::|h)\\s*(\\d{2})\\b(?:\\s*(?:min|minutos)\\b)?');
  const RE_T2 = rx('\\b' + PRE + '(\\d{1,2}|' + NUM + ')\\s*(?:h|hs|hrs?|horas?)\\b(?:\\s+e\\s+(\\d{1,2}|meia|' + NUM + ')(?:\\s+minutos?)?)?');
  const RE_T3 = rx('\\b(?:as|pelas|para\\s+as|ate\\s+as)\\s+(\\d{1,2}|' + NUM + ')(?:\\s+e\\s+(\\d{1,2}|meia|' + NUM + '))?\\b');
  const RE_T3B = /\ba\s+(uma)(?:\s+e\s+(meia|\d{1,2}))?\b(?=\s+(?:da|de)\s+(?:manha|tarde|noite|madrugada))/;
  const RE_T4 = /\b(?:ao\s+|as\s+|a\s+|para\s+o\s+)?(meio[- ]dia|meia[- ]noite)(?:\s+e\s+(meia|\d{1,2}))?\b/;
  const RE_PERIOD = /\b(?:de|pela|a|da|na)\s+(manha|tarde|noite|madrugada)\b/;

  /** Extrai data/hora (sem resolver). */
  function extractWhen(w) {
    const out = { date: null, time: null, period: null, rel: null, error: null };
    let m;
    if ((m = w.take(RE_REL))) {
      const n = m[1] === 'meia' ? 0.5 : toNum(m[1]);
      const u = m[2][0] === 'm' && m[2].startsWith('mi') ? 'min' : m[2][0] === 'h' ? 'h' : m[2][0] === 'd' ? 'd' : m[2][0] === 's' ? 'w' : 'mo';
      out.rel = { n: n + (m[3] ? 0.5 : 0), unit: u };
    }
    if (!out.rel || out.rel.unit === 'd' || out.rel.unit === 'w' || out.rel.unit === 'mo') {
      for (const [re, off] of RE_DAYWORDS) {
        if (out.date) break;
        if (w.take(re)) out.date = { kind: 'offset', days: off };
      }
      if (!out.date && (m = w.take(RE_NUMDATE))) {
        out.date = { kind: 'ymd', d: +m[1], m: +m[2], y: m[3] ? (m[3].length === 2 ? 2000 + +m[3] : +m[3]) : null };
      }
      if (!out.date && (m = w.take(RE_TXTDATE))) {
        out.date = { kind: 'ymd', d: toNum(m[1]), m: MONTHS.indexOf(m[2]) + 1, y: m[3] ? +m[3] : null };
      }
      if (!out.date && (m = w.take(RE_DAYN))) out.date = { kind: 'dayN', d: toNum(m[1]) };
      if (!out.date && (m = w.take(RE_NEXTWEEK))) out.date = { kind: 'nextweek' };
      if (!out.date && (m = w.take(RE_WEEKDAY))) {
        const q = (m[1] || '').replace(/\s+/g, ' ');
        out.date = {
          kind: 'weekday', wd: WD.indexOf(m[2]),
          mode: /^(?:nesta|neste|esta|este|essa|nessa|nesse|desta)$/.test(q) ? 'this' : (/proxim/.test(q) || m[3]) ? 'next' : 'auto'
        };
      }
    }
    if (!out.rel || out.date || out.rel.unit === 'd' || out.rel.unit === 'w' || out.rel.unit === 'mo') {
      let h = null, mi = 0;
      if ((m = w.take(RE_T4))) {
        h = /^meio/.test(m[1]) ? 12 : 0;
        mi = m[2] ? toNum(m[2]) : 0;
      } else if ((m = w.take(RE_T1))) {
        h = +m[1]; mi = +m[2];
      } else if ((m = w.take(RE_T2)) || (m = w.take(RE_T3)) || (m = w.take(RE_T3B))) {
        h = toNum(m[1]); mi = m[2] ? toNum(m[2]) : 0;
      }
      const pm = w.take(RE_PERIOD);
      if (pm) out.period = pm[1];
      if (h != null) {
        if (out.period === 'tarde' && h >= 1 && h <= 11) h += 12;
        else if (out.period === 'noite' && h >= 5 && h <= 11) h += 12;
        else if ((out.period === 'noite' || out.period === 'madrugada') && h === 12) h = 0;
        if (h > 23 || mi > 59 || h < 0) out.error = 'Horário inválido.';
        else out.time = { h, mi };
      }
    }
    return out;
  }

  function nextWeekdayDate(now, wd, mode, time) {
    let delta = (wd - now.getDay() + 7) % 7;
    if (delta === 0) {
      if (mode === 'next') delta = 7;
      else if (mode === 'this') delta = 0;
      else if (time && (time.h * 60 + time.mi) > (now.getHours() * 60 + now.getMinutes())) delta = 0;
      else delta = 7;
    }
    return addDays(startOfDay(now), delta);
  }

  /** Converte o que foi extraído em data concreta. */
  function resolveWhen(spec, now, rec) {
    if (spec.error) return { error: spec.error };
    const today = startOfDay(now);
    let base = null, rolled = false;
    if (spec.rel) {
      const r = spec.rel;
      if (r.unit === 'min' || r.unit === 'h') {
        const due = new Date(now.getTime() + Math.round(r.n * (r.unit === 'h' ? 60 : 1)) * 60000);
        due.setSeconds(0, 0);
        return { due, allDay: false, hasDate: true, hasTime: true };
      }
      base = r.unit === 'd' ? addDays(today, Math.round(r.n)) : r.unit === 'w' ? addDays(today, Math.round(r.n * 7))
        : new Date(today.getFullYear(), today.getMonth() + Math.round(r.n), Math.min(today.getDate(), daysInMonth(today.getFullYear(), today.getMonth() + Math.round(r.n))));
    }
    const d = spec.date, t = spec.time;
    if (!base && d) {
      if (d.kind === 'offset') base = addDays(today, d.days);
      else if (d.kind === 'ymd') {
        let y = d.y || today.getFullYear();
        if (!validYMD(y, d.m, d.d)) return { error: 'Data inválida: ' + pad(d.d) + '/' + pad(d.m) + (d.y ? '/' + d.y : '') + '.' };
        base = new Date(y, d.m - 1, d.d);
        if (!d.y && base < today) {
          if (!validYMD(y + 1, d.m, d.d)) return { error: 'Data inválida.' };
          base = new Date(y + 1, d.m - 1, d.d);
        }
      } else if (d.kind === 'dayN') {
        if (d.d < 1 || d.d > 31) return { error: 'Dia inválido: ' + d.d + '.' };
        let y = today.getFullYear(), m0 = today.getMonth(), guard = 0;
        while (guard++ < 14) {
          if (d.d <= daysInMonth(y, m0)) {
            const c = new Date(y, m0, d.d);
            if (c >= today) { base = c; break; }
          }
          m0++; if (m0 > 11) { m0 = 0; y++; }
        }
      } else if (d.kind === 'weekday') base = nextWeekdayDate(now, d.wd, d.mode, t);
      else if (d.kind === 'nextweek') base = nextWeekdayDate(now, 1, 'next', null);
    }
    if (!base && rec && rec.freq) {
      // recorrência sem data explícita: primeira ocorrência a partir de hoje
      if (rec.freq === 'weekly' && rec.byDay && rec.byDay.length) {
        for (let i = 0; i < 8; i++) {
          const c = addDays(today, i);
          if (!rec.byDay.includes(c.getDay())) continue;
          if (i === 0 && t && (t.h * 60 + t.mi) <= now.getHours() * 60 + now.getMinutes()) continue;
          base = c; break;
        }
      } else if (rec.freq === 'monthly' && rec.day) {
        let y = today.getFullYear(), m0 = today.getMonth();
        let c = new Date(y, m0, Math.min(rec.day, daysInMonth(y, m0)));
        if (c < today || (+c === +today && t && (t.h * 60 + t.mi) <= now.getHours() * 60 + now.getMinutes())) {
          m0++; if (m0 > 11) { m0 = 0; y++; }
          c = new Date(y, m0, Math.min(rec.day, daysInMonth(y, m0)));
        }
        base = c;
      } else if (t) {
        base = today;
      } else {
        base = today;
      }
    }
    if (!base && !t) return { due: null, allDay: false, hasDate: false, hasTime: false };
    if (!base) {
      base = today;
      if (t.h * 60 + t.mi < now.getHours() * 60 + now.getMinutes()) { base = addDays(today, 1); rolled = true; }
    }
    if (!t) return { due: base, allDay: true, hasDate: true, hasTime: false };
    const due = new Date(base.getFullYear(), base.getMonth(), base.getDate(), t.h, t.mi);
    if (rec && rec.freq && due.getTime() < now.getTime() - 60000 && !(d && d.kind === 'ymd')) {
      // primeira ocorrência já passou hoje: começa na próxima
      return { due: nextOccurrenceDate(due, rec, now), allDay: false, hasDate: true, hasTime: true, rolled: true };
    }
    return { due, allDay: false, hasDate: !!(d || spec.rel), hasTime: true, rolled };
  }

  // ----------------------------------------------------- recorrência
  function stepOnce(d, rec) {
    if (rec.freq === 'daily') return addDays(d, 1);
    if (rec.freq === 'weekly') {
      if (rec.byDay && rec.byDay.length) {
        let c = addDays(d, 1);
        for (let i = 0; i < 8 && !rec.byDay.includes(c.getDay()); i++) c = addDays(c, 1);
        return c;
      }
      return addDays(d, 7);
    }
    if (rec.freq === 'monthly') {
      const day = rec.day || d.getDate();
      let y = d.getFullYear(), m0 = d.getMonth() + 1;
      if (m0 > 11) { m0 = 0; y++; }
      return new Date(y, m0, Math.min(day, daysInMonth(y, m0)), d.getHours(), d.getMinutes());
    }
    return addDays(d, 1);
  }
  function nextOccurrenceDate(from, rec, after) {
    let d = new Date(from), guard = 0;
    do { d = stepOnce(d, rec); } while (d.getTime() <= after.getTime() && ++guard < 2000);
    return d;
  }

  // ----------------------------------------------------------- título
  const TITLE_LEAD = [
    /^(?:e\s+)?(?:me\s+)?(?:lembr(?:e|a|ar)(?:-me)?|lembrete)(?:\s+me)?(?:\s+(?:de|que|para|da|do))?\b/,
    /^(?:me\s+)?avis(?:e|a|ar)(?:-me)?(?:\s+(?:de|que|para))?\b/,
    /^(?:agend(?:e|a|ar)|marqu?e|marc(?:a|ar)|registr(?:e|a|ar)|anot(?:e|a|ar)|adicion(?:e|a|ar)|inclu(?:a|i|ir)|coloqu?e|bot(?:e|a))(?:\s+(?:na|em)\s+(?:minha\s+)?agenda)?(?:\s+(?:que|uma|um|para|de))?\b/,
    /^cri(?:e|a|ar)(?:\s+(?:uma|um))?(?:\s+(?:nova|novo))?(?:\s+(?:tarefa|lembrete|compromisso|evento|pendencia))?(?:\s+(?:de|para|chamad[ao]|que))?\b/,
    /^(?:nova|novo)\s+(?:tarefa|lembrete|compromisso|evento|pendencia)(?:\s+(?:de|para))?\b/,
    /^(?:tarefa|lembrete|pendencia)(?:\s*:)?(?:\s+(?:de|para))?\b/,
    /^(?:eu\s+)?(?:preciso|tenho\s+que|tenho\s+de|devo|vou\s+ter\s+que)(?:\s+de)?\b/,
    /^(?:de|que|para)\b/
  ];
  const TITLE_TRAIL = /(?:\s+(?:para|pra|no|na|em|de|do|da|as|e|com|que|me\s+lembre|me\s+avise|lembre-me))+\s*$/;
  function cleanTitle(s) {
    let t = String(s).replace(/\s+/g, ' ').replace(/\s+([,;:.!?])/g, '$1').replace(/^[\s,;:.!?-]+/, '').trim();
    for (let guard = 0; guard < 8; guard++) {
      const before = t;
      for (const re of TITLE_LEAD) {
        const m = re.exec(fold(t));
        if (m && m[0].length) { t = t.slice(m[0].length).replace(/^[\s,;:.!?-]+/, ''); }
      }
      t = t.replace(/[\s,;:.!?-]+$/, '');
      const tm = TITLE_TRAIL.exec(fold(t));
      if (tm) t = t.slice(0, tm.index);
      t = t.replace(/[\s,;:.!?-]+$/, '').replace(/([,;])\s*[,;]+/g, '$1').trim();
      if (t === before) break;
    }
    return t ? t[0].toLocaleUpperCase('pt-BR') + t.slice(1) : '';
  }

  // ------------------------------------------------------- intenções
  const RE_WAKE = /^\s*(?:(?:ok|ei|ola|oi|e\s+ai|alo|hey)[\s,]+)?jarvis\b[\s,!.:;-]*/;
  const RE_POLITE = /[,]?\s*\b(?:por\s+favor|por\s+gentileza|se\s+puder)\b/;
  const RE_UNDO = /^(?:desfaz(?:er|a)?|desfaca|volta(?:r)?(?:\s+atras)?|anula(?:r)?)(?:\s+(?:isso|a\s+ultima(?:\s+acao)?|o\s+ultimo))?\s*[.!]?\s*$|^(?:cancel(?:a|e|ar))\s+(?:isso|a\s+ultima(?:\s+acao)?)\s*[.!]?\s*$/;
  const RE_HELP = /^(?:ajuda|socorro|o\s+que\s+voce\s+(?:faz|sabe\s+fazer|pode\s+fazer)|quais\s+(?:sao\s+)?(?:os\s+)?comandos|comandos|como\s+(?:funciona|te\s+uso|usar))\b/;
  const RE_TIMEQ = /^(?:que\s+horas\s+(?:sao|e)|me\s+diga\s+as\s+horas|horas)\s*[?.!]?\s*$/;
  const RE_DATEQ = /^(?:que\s+dia\s+(?:e\s+)?hoje|qual\s+(?:e\s+)?a\s+data(?:\s+de\s+hoje)?|que\s+data\s+e\s+hoje)\s*[?.!]?\s*$/;
  const RE_SUMMARY_OFF = /\b(?:desativ|deslig|cancel|par[ae]|interromp|suspend)\w*\s+(?:o\s+)?resumo/;
  const RE_SUMMARY_VERB = /\b(?:apresente|apresenta|leia|le|mostre|mostra|diga|diz|fale|fala|resuma|resume|informe|liste|repasse|repassa|me\s+de|me\s+passe|me\s+passa)\b/;
  const RE_SUMMARY_OBJ = /\b(?:tarefas|agenda|compromissos|pendencias|programacao)\b/;
  const RE_QUERY = /^(?:(?:o\s+)?que\s+(?:eu\s+)?(?:tenho|tem|ha|temos|esta\s+marcado|esta\s+agendado)|quais?\s+(?:sao\s+|e\s+)?(?:as\s+|os\s+)?(?:minhas|meus|as|os|tarefas|compromissos)|qual\s+(?:e\s+)?(?:a\s+)?minha\s+agenda|(?:me\s+)?(?:mostre|mostra|liste|lista|listar|leia|le|diga|diz|fale|fala|informe|consulte|consultar|veja|repasse|resuma)\b|(?:como\s+(?:esta|e)\s+)?(?:a\s+)?minha\s+agenda|minhas\s+tarefas|meus\s+compromissos|tenho\s+(?:algo|alguma\s+coisa|algum|alguma|tarefas?|compromissos?|reuni)|agenda\s+de|quantas\s+tarefas)/;
  const RE_COMPLETE = /^(?:pode\s+)?(?:conclu(?:a|i|ir|ida|ido)|finaliz(?:e|a|ar)|termin(?:e|a|ar|ei)|complet(?:e|a|ar)|(?:dar|de|da)\s+baixa(?:\s+n[ao]s?)?|ja\s+(?:fiz|fizemos|terminei|conclui|resolvi|liguei|paguei|enviei|mandei|comprei|entreguei|falei)|fiz|feito|resolvi)\b/;
  const RE_COMPLETE_MARK = /^(marqu?e|marca|marcar|coloqu?e|deixe)\b(.*?)\bcomo\s+(?:feit|conclu|realiz|pront)\w*/;
  const RE_CANCEL = /^(?:cancel(?:e|a|ar)|exclu(?:a|i|ir)|apag(?:ue|a|ar)|remov(?:a|e|er)|delet(?:e|a|ar)|desmarqu?e|desmarc(?:a|ar)|tir(?:e|a|ar))\b/;
  const RE_RESCHED = /^(?:transfir(?:a|o)|transfer(?:e|ir)|mud(?:e|a|ar)|remarqu?e|remarc(?:a|ar)|adi(?:e|a|ar)|pass(?:e|a|ar)|mov(?:a|e|er)|alter(?:e|a|ar)|reagend(?:e|a|ar)|empurr(?:e|a|ar)|jog(?:ue|a|ar)|antecip(?:e|a|ar)|troqu?e|troca|trocar)\b/;
  const RESCHED_LOOSE = /^(?:pass(?:e|a|ar)|mov(?:a|e|er)|jog(?:ue|a|ar)|troqu?e|troca|trocar)$/;
  const RE_SHIFT = rx('\\b(?:em|por|mais)?\\s*(' + NUM + '|meia)\\s*(minutos?|mins?|horas?|dias?|semanas?)(\\s+e\\s+meia)?\\b');
  const RE_EVENT = /\b(?:reuniao|reunioes|consulta|compromisso|encontro|almoco|jantar|visita|evento|call|entrevista|audiencia|aula|dentista|medico|exame|agend(?:e|a|ar)|marqu?e|marc(?:a|ar))\b/;

  /** Interpreta um comando. `now` é a data local atual. */
  function parse(text, now) {
    now = now || new Date();
    const raw = String(text == null ? '' : text).trim();
    const w = new Work(raw);
    w.take(RE_WAKE);
    while (w.take(RE_POLITE)) { /* remove cortesias */ }
    const f = w.f.trim().replace(/[?!.]+$/, '').trim();
    if (!f) return { type: 'empty' };
    if (RE_UNDO.test(f)) return { type: 'undo' };
    if (RE_HELP.test(f)) return { type: 'help' };
    if (RE_TIMEQ.test(f)) return { type: 'time' };
    if (RE_DATEQ.test(f)) return { type: 'date' };
    if (RE_SUMMARY_OFF.test(f)) return { type: 'summary', enable: false };
    const isDaily = RC_DAILY.test(f) || /\btoda\s+manha\b/.test(f);
    if (/\bresumo\s+diario\b/.test(f) || (isDaily && RE_SUMMARY_VERB.test(f) && RE_SUMMARY_OBJ.test(f))) {
      w.take(RC_DAILY);
      const when = extractWhen(w);
      if (when.error) return { type: 'error', message: when.error };
      return { type: 'summary', enable: true, time: when.time ? pad(when.time.h) + ':' + pad(when.time.mi) : null };
    }

    const lead = /^\s*/.exec(w.f)[0].length;
    const body = new Work(w.rest().slice(lead)); // sem a palavra de ativação
    const bf = body.f.trim();

    if (RE_QUERY.test(bf)) return parseQuery(body, bf, now);

    const off = body.f.length - body.f.trimStart().length;
    const after = (m0) => new Work(body.orig.slice(off + m0.length));
    let m;
    if ((m = RE_COMPLETE_MARK.exec(bf))) {
      return Object.assign({ type: 'complete' }, targetFrom(new Work(body.orig.slice(off + m[1].length, off + m[1].length + m[2].length))));
    }
    if ((m = RE_COMPLETE.exec(bf))) return Object.assign({ type: 'complete' }, targetFrom(after(m[0])));
    if ((m = RE_CANCEL.exec(bf))) return Object.assign({ type: 'cancel' }, targetFrom(after(m[0])));
    if ((m = RE_RESCHED.exec(bf))) {
      const r = parseReschedule(body.orig.slice(off + m[0].length), m[0]);
      if (r) return r;
      if (!RESCHED_LOOSE.test(m[0])) return Object.assign({ type: 'reschedule', missing: true }, targetFrom(after(m[0])));
    }
    return parseCreate(body, raw, now);
  }

  function targetFrom(w) {
    const when = extractWhen(w);
    const target = cleanTitle(w.rest().replace(/\b(?:como\s+)?(?:feit[ao]|conclu[ií]d[ao])\b/gi, ''));
    return { target, from: when.date || when.time ? when : null };
  }

  function parseReschedule(after, verb) {
    const fa = fold(after);
    const re = /\b(?:para|pra|pro)\b/g;
    const cuts = [];
    let p;
    while ((p = re.exec(fa))) cuts.push(p.index);
    for (let i = cuts.length - 1; i >= 0; i--) {
      const right = new Work(after.slice(cuts[i]).replace(/^\s*\S+/, ''));
      const rem = extractReminders(right, false);
      const when = extractWhen(right);
      if (rem.list || rem.none) {
        const t = targetFrom(new Work(after.slice(0, cuts[i])));
        return Object.assign({ type: 'setReminder', minutes: rem.none ? [] : rem.list }, t);
      }
      if (when.date || when.time || when.rel || when.error) {
        const t = targetFrom(new Work(after.slice(0, cuts[i]).replace(/\b(?:o\s+horario|a\s+data|o\s+dia)\s+(?:d[aoe]s?)\b/i, '')));
        return Object.assign({ type: 'reschedule', to: when }, t);
      }
    }
    if (/^(?:adi|empurr|atras)/.test(verb)) {
      const w = new Work(after);
      const sm = w.take(RE_SHIFT);
      if (sm) {
        const n = sm[1] === 'meia' ? 30 : toNum(sm[1]) * (sm[2][0] === 'h' ? 60 : sm[2][0] === 'd' ? 1440 : sm[2][0] === 's' ? 10080 : 1) + (sm[3] ? 30 : 0);
        return Object.assign({ type: 'reschedule', shift: n }, targetFrom(w));
      }
    }
    return null;
  }

  function parseQuery(w, f, now) {
    let range = 'pending', date = null, label = null;
    if (/\batrasad/.test(f)) range = 'overdue';
    else if (/\bconclu|\bfeitas\b|\bfinalizad/.test(f)) range = 'done';
    else if (/\b(?:proxima\s+semana|semana\s+que\s+vem)\b/.test(f)) range = 'nextweek';
    else if (/\bsemana\b/.test(f)) range = 'week';
    else {
      const when = extractWhen(w);
      if (when.date) {
        const r = resolveWhen({ date: when.date, time: null }, now, null);
        if (r.due) { range = 'day'; date = dayKey(r.due); }
      } else if (/\b(?:pendente|pendencias|em\s+aberto|a\s+fazer|sem\s+data)\b/.test(f)) range = 'pending';
    }
    return { type: 'query', range, date, label };
  }

  function parseCreate(w, raw, now) {
    const rem = extractReminders(w, false);
    const rec = extractRecurrence(w);
    const when = extractWhen(w);
    const title = cleanTitle(w.rest());
    const fr = fold(raw);
    const kind = RE_EVENT.test(fr) ? 'event' : 'task';
    const reminderVerb = /\b(?:lembr|avis|alert|notifiq)/.test(fr);
    const error = when.error || (rec && rec.error) || null;
    if (!title && (rem.list || rem.none) && !when.date && !when.time && !when.rel && !rec) {
      return { type: 'setReminder', minutes: rem.none ? [] : rem.list, target: '', from: null };
    }
    return { type: 'create', title, when, reminders: rem.none ? [] : rem.list, recurrence: rec && !rec.error ? rec : null, kind, reminderVerb, error };
  }

  // ---------------------------------------------------- busca de alvo
  const STOP = new Set(('a o as os de da do das dos para pra pro com em no na nos nas um uma uns umas que e minha meu minhas meus ' +
    'sua seu tarefa tarefas compromisso lembrete isso essa esse esta este aquela aquele feita feito concluida concluido como ' +
    'agenda la ja hoje amanha ate sobre aquilo').split(' '));
  function tokens(s) { return fold(s).split(/[^a-z0-9]+/).filter((x) => x.length >= 3 && !STOP.has(x)); }
  function tokMatch(a, b) {
    if (a === b) return 1;
    const n = Math.min(a.length, b.length);
    if (n >= 5 && a.slice(0, 5) === b.slice(0, 5)) return 0.9;
    if (n >= 4 && a.slice(0, 4) === b.slice(0, 4)) return 0.6;
    return 0;
  }
  function scoreTask(q, task) {
    if (!q.length) return 0;
    const tt = tokens(task.title + ' ' + (task.description || ''));
    let s = 0;
    for (const a of q) { let best = 0; for (const b of tt) best = Math.max(best, tokMatch(a, b)); s += best; }
    return s / q.length;
  }

  // ------------------------------------------------------- fala/textos
  function atTime(d) {
    const h = d.getHours(), m = d.getMinutes();
    if (h === 12 && m === 0) return 'ao meio-dia';
    if (h === 0 && m === 0) return 'à meia-noite';
    const hh = m === 0 ? h + (h === 1 ? ' hora' : ' horas') : m === 30 ? h + ' e meia' : h + ' e ' + pad(m);
    return (h === 1 ? 'à ' : 'às ') + hh;
  }
  function dayLabel(d, now) {
    const diff = dayDiff(d, now);
    if (diff === 0) return 'hoje';
    if (diff === 1) return 'amanhã';
    if (diff === 2) return 'depois de amanhã';
    if (diff === -1) return 'ontem';
    if (diff > 2 && diff < 7) return WEEKDAY_FULL[d.getDay()] + ', dia ' + d.getDate();
    return 'dia ' + d.getDate() + ' de ' + MONTH_FULL[d.getMonth()] + (d.getFullYear() !== now.getFullYear() ? ' de ' + d.getFullYear() : '');
  }
  function describeWhen(task, now) {
    if (!task.dueAt) return 'sem data definida';
    const d = new Date(task.dueAt);
    const lbl = dayLabel(d, now);
    return task.allDay ? lbl + ', sem horário' : lbl + (/dia \d/.test(lbl) ? ', ' : ' ') + atTime(d);
  }
  function describeLead(min) {
    if (min === 0) return 'na hora';
    if (min % 1440 === 0) return (min / 1440) + (min === 1440 ? ' dia' : ' dias') + ' antes';
    if (min % 60 === 0) return (min / 60) + (min === 60 ? ' hora' : ' horas') + ' antes';
    if (min > 60 && min % 30 === 0) return Math.floor(min / 60) + ' hora' + (min >= 120 ? 's' : '') + ' e meia antes';
    return min + ' minutos antes';
  }
  function describeRecurrence(r) {
    if (!r) return '';
    if (r.freq === 'daily') return 'todos os dias';
    if (r.freq === 'monthly') return r.day ? 'todo dia ' + r.day : 'todo mês';
    if (r.freq === 'weekly') {
      if (r.byDay && r.byDay.join() === '1,2,3,4,5') return 'de segunda a sexta';
      if (r.byDay && r.byDay.length) return 'toda ' + r.byDay.map((d) => WEEKDAY_FULL[d].replace('-feira', '')).join(' e ');
      return 'toda semana';
    }
    return '';
  }
  function list(arr) {
    if (arr.length <= 1) return arr.join('');
    return arr.slice(0, -1).join('; ') + '; e ' + arr[arr.length - 1];
  }

  // ------------------------------------------------------------ vozes
  const MALE = ['antonio', 'daniel', 'duarte', 'donato', 'fabio', 'humberto', 'julio', 'nicolau', 'valerio', 'ricardo', 'felipe',
    'paulo', 'joao', 'jorge', 'cristiano', 'tiago', 'thiago', 'bruno', 'rafael', 'lucas', 'marcos', 'pedro', 'eduardo', 'carlos',
    'andre', 'macerio', 'david', 'mark', 'george', 'ryan', 'thomas', 'guy', 'arthur', 'oliver'];
  const FEMALE = ['maria', 'francisca', 'thalita', 'brenda', 'elza', 'giovanna', 'leila', 'leticia', 'manuela', 'yara', 'raquel',
    'fernanda', 'luciana', 'joana', 'helena', 'camila', 'vitoria', 'catarina', 'ines', 'beatriz', 'julia', 'luiza', 'adriana',
    'heloisa', 'clara', 'lia', 'ana', 'isabela', 'sofia', 'luna', 'zira', 'samantha', 'karen', 'moira', 'tessa', 'fiona',
    'victoria', 'allison', 'ava', 'susan', 'hazel', 'libby', 'sonia', 'sonia', 'amelie', 'paulina', 'monica'];
  const RE_MALE = new RegExp('\\b(?:' + MALE.join('|') + ')\\b');
  const RE_FEMALE = new RegExp('\\b(?:' + FEMALE.join('|') + ')\\b');
  /** Estimativa de gênero pelo nome. Não é garantia: o navegador não informa o gênero. */
  function classifyVoice(v) {
    const n = fold((v.name || '') + ' ' + (v.voiceURI || ''));
    let gender = '?';
    if (/\b(?:female|feminin[oa]|mulher|woman)\b/.test(n)) gender = 'f';
    else if (/\b(?:male|masculin[oa]|homem|man)\b/.test(n)) gender = 'm';
    else if (RE_FEMALE.test(n)) gender = 'f';
    else if (RE_MALE.test(n)) gender = 'm';
    const lang = String(v.lang || '').toLowerCase().replace('_', '-');
    const pt = lang.startsWith('pt');
    const br = lang === 'pt-br';
    const quality = /natural|neural|online|premium|enhanced|aprimorad|wavenet|studio|network/.test(n);
    const score = (gender === 'm' ? 10 : gender === '?' ? 4 : 0) + (br ? 3 : pt ? 1 : -20) + (quality ? 2 : 0);
    return { gender, pt, br, quality, score };
  }
  function rankVoices(voices, showAll) {
    return Array.from(voices || [])
      .map((v) => ({ voice: v, info: classifyVoice(v) }))
      .filter((x) => showAll || x.info.pt)
      .sort((a, b) => b.info.score - a.info.score || String(a.voice.name).localeCompare(String(b.voice.name)));
  }

  // ---------------------------------------------------------- armazenamento
  function uid() {
    try { if (typeof crypto !== 'undefined' && crypto.randomUUID) return crypto.randomUUID(); } catch (e) { /* contexto inseguro */ }
    return 't' + Date.now().toString(36) + Math.random().toString(36).slice(2, 10);
  }
  function localTz() {
    try { return Intl.DateTimeFormat().resolvedOptions().timeZone || 'America/Sao_Paulo'; } catch (e) { return 'America/Sao_Paulo'; }
  }
  function normalizeTask(t, nowIso) {
    const due = t.dueAt ? new Date(t.dueAt) : null;
    return {
      id: String(t.id || uid()),
      title: String(t.title || '(sem título)'),
      description: String(t.description || ''),
      type: t.type === 'event' ? 'event' : 'task',
      dueAt: due && !isNaN(due) ? due.toISOString() : null,
      allDay: !!t.allDay,
      timezone: t.timezone || localTz(),
      reminderOffsetsMinutes: Array.isArray(t.reminderOffsetsMinutes) ? t.reminderOffsetsMinutes.filter((n) => Number.isFinite(n) && n >= 0) : [],
      recurrenceRule: t.recurrenceRule || null,
      status: ['pending', 'completed', 'cancelled'].includes(t.status) ? t.status : 'pending',
      priority: t.priority || 'normal',
      createdAt: t.createdAt || nowIso,
      updatedAt: t.updatedAt || nowIso,
      completedAt: t.completedAt || null,
      source: t.source || 'manual',
      notified: Array.isArray(t.notified) ? t.notified : [],
      lastNotificationAt: t.lastNotificationAt || null
    };
  }
  /** Tarefa da 0.3/0.4/0.6: {id,title,date,reminder,done}. */
  function migrateLegacyTask(t, nowIso) {
    const d = t && t.date ? new Date(t.date) : null;
    const ok = d && !isNaN(d);
    const r = Number(t && t.reminder);
    return normalizeTask({
      id: t && t.id, title: t && t.title, type: 'task',
      dueAt: ok ? d.toISOString() : null, allDay: false,
      reminderOffsetsMinutes: ok && r >= 0 ? [r] : [],
      status: t && t.done ? 'completed' : 'pending', completedAt: t && t.done ? nowIso : null,
      source: 'legado-0.6', createdAt: nowIso, updatedAt: nowIso
    }, nowIso);
  }
  function loadTasks(storage, now) {
    const nowIso = (now || new Date()).toISOString();
    let raw = null;
    try { raw = storage.getItem(KEY_TASKS); } catch (e) { return { tasks: [], migrated: 0, error: 'storage' }; }
    if (raw) {
      try {
        const arr = JSON.parse(raw);
        if (Array.isArray(arr)) return { tasks: arr.map((t) => normalizeTask(t, nowIso)), migrated: 0 };
      } catch (e) { /* cai para o backup abaixo */ }
      try { storage.setItem(KEY_TASKS + '-corrompido-' + Date.now(), raw); } catch (e) { /* ignora */ }
      return { tasks: [], migrated: 0, error: 'corrupt' };
    }
    let legacy = null;
    try { legacy = JSON.parse(storage.getItem(KEY_LEGACY) || 'null'); } catch (e) { legacy = null; }
    if (Array.isArray(legacy) && legacy.length) {
      const tasks = legacy.map((t) => migrateLegacyTask(t, nowIso));
      // tarefas antigas com aviso já vencido não devem disparar todas de uma vez
      for (const t of tasks) {
        if (!t.dueAt) continue;
        for (const o of t.reminderOffsetsMinutes) {
          const fire = new Date(t.dueAt).getTime() - o * 60000;
          if (fire < (now || new Date()).getTime() - 12 * 3600000) t.notified.push(t.dueAt + '|' + o);
        }
      }
      return { tasks, migrated: tasks.length };
    }
    return { tasks: [], migrated: 0 };
  }
  const DEFAULT_SETTINGS = {
    voiceURI: '', rate: 0.92, pitch: 0.9, honorific: true, askLead: true, defaultLead: 15,
    followUp: true, showAllVoices: false, summary: { enabled: false, time: '08:00', lastRun: '' }
  };
  function loadSettings(storage) {
    let s = {};
    try { s = JSON.parse(storage.getItem(KEY_SETTINGS) || '{}') || {}; } catch (e) { s = {}; }
    const out = Object.assign({}, DEFAULT_SETTINGS, s);
    out.summary = Object.assign({}, DEFAULT_SETTINGS.summary, s.summary || {});
    if (!out.voiceURI) { try { out.voiceURI = storage.getItem(KEY_LEGACY_VOICE) || ''; } catch (e) { /* ignora */ } }
    return out;
  }

  // ------------------------------------------------------------- motor
  const PH = {
    ack: ['Anotado', 'Registrado', 'Feito', 'Certamente', 'Pronto', 'Entendido'],
    done: ['Concluída', 'Marcada como concluída', 'Feito, concluída'],
    none: ['Não encontrei', 'Não localizei']
  };

  function createEngine(opts) {
    opts = opts || {};
    const storage = opts.storage;
    const clock = opts.now || (() => new Date());
    const rand = opts.random || Math.random;
    const loaded = loadTasks(storage, clock());
    let tasks = loaded.tasks;
    let settings = loadSettings(storage);
    const undo = [];
    const ctx = { lastTaskId: null, lastAt: 0, pending: null, last: {} };
    const status = { migrated: loaded.migrated, loadError: loaded.error || null, saved: false };

    function pick(key) {
      const a = PH[key];
      let i = Math.floor(rand() * a.length);
      if (a.length > 1 && i === ctx.last[key]) i = (i + 1) % a.length;
      ctx.last[key] = i;
      return a[i];
    }
    const sir = () => (settings.honorific ? ', senhor' : '');
    const Sir = () => (settings.honorific ? 'Senhor, ' : '');

    function persist() {
      try {
        const json = JSON.stringify(tasks);
        storage.setItem(KEY_TASKS, json);
        return storage.getItem(KEY_TASKS) === json;
      } catch (e) { return false; }
    }
    if (loaded.migrated) status.saved = persist();

    function commit(label, fn) {
      const before = JSON.stringify(tasks);
      const r = fn();
      if (!persist()) { tasks = JSON.parse(before); return { ok: false }; }
      undo.push({ label, data: before });
      if (undo.length > 30) undo.shift();
      return { ok: true, value: r };
    }
    const failSave = () => reply('Não consegui gravar no armazenamento do navegador. Nada foi alterado.', 'error');
    function reply(speech, kind, extra) { return Object.assign({ speech, kind: kind || 'ok' }, extra || {}); }
    const find = (id) => tasks.find((t) => t.id === id);
    const pendingTasks = () => tasks.filter((t) => t.status === 'pending');

    function setContext(id) { ctx.lastTaskId = id; ctx.lastAt = clock().getTime(); }
    function contextTask() {
      if (!ctx.lastTaskId || clock().getTime() - ctx.lastAt > 15 * 60000) return null;
      const t = find(ctx.lastTaskId);
      return t && t.status === 'pending' ? t : null;
    }

    function makeTask(p) {
      const nowIso = clock().toISOString();
      return normalizeTask({
        id: uid(), title: p.title, type: p.kind, dueAt: p.due ? p.due.toISOString() : null, allDay: !!p.allDay,
        reminderOffsetsMinutes: p.reminders || [], recurrenceRule: p.recurrence || null, status: 'pending',
        createdAt: nowIso, updatedAt: nowIso, source: p.source || 'voice'
      }, nowIso);
    }

    function isDuplicate(title, dueIso) {
      const ft = fold(title).replace(/[^a-z0-9]+/g, ' ').trim();
      return pendingTasks().find((t) => fold(t.title).replace(/[^a-z0-9]+/g, ' ').trim() === ft && (t.dueAt || null) === (dueIso || null));
    }

    // ---- criar
    function finishCreate(d) {
      const now = clock();
      const dueIso = d.due ? d.due.toISOString() : null;
      const dup = isDuplicate(d.title, dueIso);
      if (dup) { setContext(dup.id); return reply('Essa tarefa já está registrada: ' + dup.title + ', ' + describeWhen(dup, now) + '.', 'info', { taskId: dup.id }); }
      let reminders = d.reminders, ask = false;
      if (!d.due || d.allDay) reminders = [];
      else if (reminders == null) {
        if (d.kind === 'event' && !d.reminderVerb) { reminders = [settings.defaultLead]; ask = settings.askLead; }
        else reminders = [0];
      }
      const task = makeTask(Object.assign({}, d, { reminders }));
      const r = commit('criar "' + task.title + '"', () => tasks.push(task));
      if (!r.ok) return failSave();
      setContext(task.id);
      let s = pick('ack') + sir() + '. ' + task.title + ', ' + describeWhen(task, now);
      if (task.recurrenceRule) s += ', ' + describeRecurrence(task.recurrenceRule);
      s += '.';
      if (d.rolled && !task.recurrenceRule) s += ' Como esse horário já passou hoje, considerei amanhã.';
      if (ask) {
        ctx.pending = { type: 'lead', taskId: task.id, at: now.getTime() };
        return reply(s + ' Aviso ' + describeLead(reminders[0]) + '. Deseja outra antecedência?', 'question', { taskId: task.id, changed: true });
      }
      if (reminders.length) s += ' Aviso ' + reminders.map(describeLead).join(' e ') + '.';
      else if (task.allDay && d.reminderVerb && d.source !== 'manual') s += ' Sem horário definido, portanto sem aviso sonoro.';
      return reply(s, 'ok', { taskId: task.id, changed: true });
    }

    function doCreate(it, source) {
      const now = clock();
      if (it.error) return reply(it.error + ' Pode repetir com uma data válida?', 'error');
      const r = resolveWhen(it.when, now, it.recurrence);
      if (r.error) return reply(r.error + ' Pode repetir com uma data válida?', 'error');
      const draft = { title: it.title, due: r.due, allDay: r.allDay, rolled: r.rolled, reminders: it.reminders, recurrence: it.recurrence, kind: it.kind, reminderVerb: it.reminderVerb, source };
      if (draft.recurrence && draft.recurrence.freq === 'weekly' && !draft.recurrence.byDay && draft.due) draft.recurrence = { freq: 'weekly', byDay: [draft.due.getDay()] };
      if (draft.recurrence && draft.recurrence.freq === 'monthly' && !draft.recurrence.day && draft.due) draft.recurrence = { freq: 'monthly', day: draft.due.getDate() };
      if (draft.title && /^(?:sim|nao|ok|okay|pode|isso|certo|primeir[ao]|segund[ao]|terceir[ao]|cancelar?|obrigad[ao]|valeu|oi|ola)$/.test(fold(draft.title))) {
        return reply('Não entendi o que devo fazer. Pode repetir o comando completo?', 'error');
      }
      if (!draft.title) {
        if (r.due) { ctx.pending = { type: 'title', draft, at: now.getTime() }; return reply('Qual é a tarefa' + sir() + '?', 'question'); }
        return reply('Não entendi o que devo registrar. Pode repetir?', 'error');
      }
      if (it.kind === 'event' && !r.due) {
        ctx.pending = { type: 'when', draft, at: now.getTime() };
        return reply('Para quando devo agendar ' + draft.title + '?', 'question');
      }
      if (r.due && !draft.recurrence && r.due.getTime() < now.getTime() - 60000 && !(r.allDay && dayDiff(r.due, now) === 0)) {
        ctx.pending = { type: 'past', draft, at: now.getTime() };
        return reply('Essa data já passou: ' + dayLabel(r.due, now) + (r.allDay ? '' : ' ' + atTime(r.due)) + '. Registro para amanhã no mesmo horário?', 'question');
      }
      return finishCreate(draft);
    }

    // ---- localizar tarefa
    function locate(it) {
      const now = clock();
      let pool = pendingTasks();
      const q = tokens(it.target || '');
      if (!q.length && !it.from) {
        const c = contextTask();
        return c ? { task: c } : { none: true, empty: true };
      }
      if (it.from) {
        const d = it.from.date;
        pool = pool.filter((t) => {
          if (!t.dueAt) return false;
          const td = new Date(t.dueAt);
          if (d && d.kind === 'weekday') return td.getDay() === d.wd && dayDiff(td, now) >= -1;
          const r = resolveWhen({ date: d, time: it.from.time, rel: it.from.rel }, now, null);
          if (!r.due) return true;
          if (!d && it.from.time) return td.getHours() === it.from.time.h && td.getMinutes() === it.from.time.mi;
          return dayKey(td) === dayKey(r.due) && (!it.from.time || (td.getHours() === it.from.time.h && td.getMinutes() === it.from.time.mi));
        });
      }
      const scored = (q.length ? pool.map((t) => ({ t, s: scoreTask(q, t) })).filter((x) => x.s >= 0.5) : pool.map((t) => ({ t, s: 1 })))
        .sort((a, b) => b.s - a.s);
      if (!scored.length) return { none: true };
      const top = scored.filter((x) => x.s >= scored[0].s - 0.05);
      if (top.length === 1) return { task: top[0].t };
      return { many: top.slice(0, 5).map((x) => x.t) };
    }
    function askChoice(action, cands, payload, verb) {
      const now = clock();
      ctx.pending = { type: 'choose', action, ids: cands.map((t) => t.id), payload, at: now.getTime() };
      const opts = cands.map((t, i) => (i + 1) + ', ' + t.title + ', ' + describeWhen(t, now));
      return reply('Encontrei ' + cands.length + ' opções para ' + verb + ': ' + list(opts) + '. Qual delas?', 'question', { candidates: cands.map((t) => t.id) });
    }
    function withTarget(it, action, verb) {
      const r = locate(it);
      if (r.task) return act(action, r.task, it);
      if (r.many) return askChoice(action, r.many, it, verb);
      if (r.empty) return reply('A qual tarefa' + sir() + '?', 'question');
      return reply(pick('none') + ' tarefa pendente' + (it.target ? ' com "' + it.target + '"' : '') + (it.from && it.from.date ? ' nessa data' : '') + '.', 'error');
    }

    function act(action, task, it) {
      const now = clock();
      if (action === 'complete') {
        let msg;
        const res = commit('concluir "' + task.title + '"', () => {
          task.updatedAt = now.toISOString();
          if (task.recurrenceRule && task.dueAt) {
            const next = nextOccurrenceDate(new Date(task.dueAt), task.recurrenceRule, now);
            task.dueAt = next.toISOString(); task.notified = []; task.completedAt = now.toISOString();
            msg = pick('done') + ': ' + task.title + '. Próxima ocorrência: ' + describeWhen(task, now) + '.';
          } else {
            task.status = 'completed'; task.completedAt = now.toISOString();
            msg = pick('done') + ': ' + task.title + '.';
          }
        });
        if (!res.ok) return failSave();
        setContext(task.id);
        return reply(msg, 'ok', { taskId: task.id, changed: true });
      }
      if (action === 'cancel') {
        const res = commit('cancelar "' + task.title + '"', () => { task.status = 'cancelled'; task.updatedAt = now.toISOString(); });
        if (!res.ok) return failSave();
        return reply('Cancelada: ' + task.title + '. Se foi engano, diga "desfazer".', 'ok', { taskId: task.id, changed: true });
      }
      if (action === 'setReminder') {
        if (!task.dueAt || task.allDay) return reply(task.title + ' não tem horário definido. Informe um horário para eu poder avisar.', 'error');
        const mins = it.minutes || [];
        const res = commit('aviso de "' + task.title + '"', () => { task.reminderOffsetsMinutes = mins.slice(); task.notified = []; task.updatedAt = now.toISOString(); });
        if (!res.ok) return failSave();
        setContext(task.id);
        return reply(mins.length ? 'Certo. Aviso ' + mins.map(describeLead).join(' e ') + ' de ' + task.title + '.' : 'Certo. Sem aviso para ' + task.title + '.', 'ok', { taskId: task.id, changed: true });
      }
      if (action === 'reschedule') {
        const base = task.dueAt ? new Date(task.dueAt) : null;
        let due, allDay = task.allDay;
        if (it.shift) {
          due = new Date((base || now).getTime() + it.shift * 60000);
        } else {
          const spec = it.to;
          const r = resolveWhen(spec, now, null);
          if (r.error) return reply(r.error, 'error');
          if (spec.time && !spec.date && !spec.rel) {
            const b = base || startOfDay(now);
            due = new Date(b.getFullYear(), b.getMonth(), b.getDate(), spec.time.h, spec.time.mi); allDay = false;
          } else if (!spec.time && (spec.date || (spec.rel && spec.rel.unit !== 'min' && spec.rel.unit !== 'h'))) {
            due = r.due;
            if (base && !task.allDay) { due = new Date(due.getFullYear(), due.getMonth(), due.getDate(), base.getHours(), base.getMinutes()); allDay = false; }
            else allDay = true;
          } else { due = r.due; allDay = r.allDay; }
        }
        if (!due) return reply('Para quando devo transferir ' + task.title + '?', 'question');
        const res = commit('transferir "' + task.title + '"', () => {
          task.dueAt = due.toISOString(); task.allDay = allDay; task.notified = []; task.updatedAt = now.toISOString();
          if (!allDay && !task.reminderOffsetsMinutes.length) task.reminderOffsetsMinutes = [task.type === 'event' ? settings.defaultLead : 0];
        });
        if (!res.ok) return failSave();
        setContext(task.id);
        let s = 'Transferida: ' + task.title + ', para ' + describeWhen(task, now) + '.';
        if (due.getTime() < now.getTime() - 60000) s += ' Atenção: essa data já passou.';
        return reply(s, 'ok', { taskId: task.id, changed: true });
      }
      return reply('Ação desconhecida.', 'error');
    }

    // ---- consultas
    function inRange(t, q, now) {
      const today = startOfDay(now);
      const d = t.dueAt ? new Date(t.dueAt) : null;
      switch (q.range) {
        case 'day': return t.status === 'pending' && d && dayKey(d) === q.date;
        case 'week': return t.status === 'pending' && d && d >= today && d < addDays(today, 7);
        case 'nextweek': { const mon = nextWeekdayDate(now, 1, 'next', null); return t.status === 'pending' && d && d >= mon && d < addDays(mon, 7); }
        case 'overdue': return t.status === 'pending' && d && (t.allDay ? startOfDay(d) < today : d < now);
        case 'done': return t.status === 'completed';
        default: return t.status === 'pending';
      }
    }
    function sortTasks(a, b) {
      if (!a.dueAt && !b.dueAt) return a.createdAt.localeCompare(b.createdAt);
      if (!a.dueAt) return 1; if (!b.dueAt) return -1;
      return a.dueAt.localeCompare(b.dueAt) || (a.allDay ? -1 : 1);
    }
    function doQuery(q) {
      const now = clock();
      const items = tasks.filter((t) => inRange(t, q, now)).sort(sortTasks);
      let head;
      if (q.range === 'day') {
        const d = new Date(q.date + 'T12:00:00');
        const lbl = dayLabel(new Date(d.getFullYear(), d.getMonth(), d.getDate()), now);
        head = lbl[0].toUpperCase() + lbl.slice(1);
      } else head = { week: 'Nos próximos 7 dias', nextweek: 'Na próxima semana', overdue: 'Atrasadas', done: 'Concluídas', pending: 'Pendentes' }[q.range];
      if (!items.length) {
        const empty = { day: 'não há nada agendado', week: 'não há nada agendado', nextweek: 'não há nada agendado', overdue: 'não há nenhuma tarefa', done: 'não há nenhuma tarefa', pending: 'não há nenhuma tarefa' }[q.range];
        return reply(head + ', ' + empty + sir() + '.', 'info', { query: q, ids: [] });
      }
      const sameDay = q.range === 'day';
      const parts = items.slice(0, 6).map((t) => {
        if (!t.dueAt) return t.title;
        const d = new Date(t.dueAt);
        if (sameDay) return t.allDay ? t.title + ', sem horário' : atTime(d) + ', ' + t.title;
        return describeWhen(t, now) + ', ' + t.title;
      });
      const n = items.length;
      let s = head + (q.range === 'day' ? ' o senhor tem ' : ': ') + n + (n === 1 ? ' item' : ' itens') + ': ' + list(parts);
      if (!settings.honorific) s = s.replace(' o senhor tem ', ' você tem ');
      if (n > 6) s += '; e mais ' + (n - 6);
      return reply(s + '.', 'info', { query: q, ids: items.map((t) => t.id) });
    }

    function summaryText(now) {
      now = now || clock();
      const today = tasks.filter((t) => inRange(t, { range: 'day', date: dayKey(now) }, now)).sort(sortTasks);
      const overdue = tasks.filter((t) => inRange(t, { range: 'overdue' }, now) && dayKey(new Date(t.dueAt)) !== dayKey(now));
      const undated = tasks.filter((t) => t.status === 'pending' && !t.dueAt);
      const h = now.getHours();
      let s = (h < 12 ? 'Bom dia' : h < 18 ? 'Boa tarde' : 'Boa noite') + sir() + '. ';
      if (today.length) s += 'Hoje há ' + today.length + (today.length === 1 ? ' item: ' : ' itens: ') + list(today.slice(0, 6).map((t) => (t.allDay ? '' : atTime(new Date(t.dueAt)) + ', ') + t.title)) + '. ';
      else s += 'Não há nada agendado para hoje. ';
      if (overdue.length) s += overdue.length + (overdue.length === 1 ? ' tarefa atrasada. ' : ' tarefas atrasadas. ');
      if (undated.length) s += undated.length + (undated.length === 1 ? ' pendência sem data.' : ' pendências sem data.');
      return s.trim();
    }

    // ---- respostas a perguntas
    const YES = /^(?:sim|pode|pode\s+ser|isso|claro|ok|okay|positivo|confirmo|confirma|esta\s+bom|ta\s+bom|beleza|perfeito|certo|correto|exato|faca\s+isso|por\s+favor)\b/;
    const NO = /^(?:nao|negativo|deixa|esquece|cancela|cancelar|nenhum|nenhuma|nada)\b/;
    const ORD = /^(?:(?:a|o|numero|opcao)\s+)?(primeir[ao]|segund[ao]|terceir[ao]|quart[ao]|quint[ao]|um|uma|dois|duas|tres|quatro|cinco|[1-5])\b/;
    const ORD_MAP = { primeir: 1, segund: 2, terceir: 3, quart: 4, quint: 5, um: 1, uma: 1, dois: 2, duas: 2, tres: 3, quatro: 4, cinco: 5 };

    function answerPending(text) {
      const p = ctx.pending;
      const now = clock();
      const w = new Work(text);
      w.take(RE_WAKE);
      const f = w.f.trim().replace(/[?!.]+$/, '').trim();
      if (p.type === 'lead') {
        const task = find(p.taskId);
        if (!task) return null;
        const rem = extractReminders(new Work(f), true);
        if (rem.none || rem.list) {
          ctx.pending = null;
          return act('setReminder', task, { minutes: rem.none ? [] : rem.list });
        }
        if (/^(?:sim|quero|desejo|outra)\b/.test(f)) {
          ctx.pending = { type: 'lead', taskId: task.id, at: now.getTime() };
          return reply('Com quanto tempo de antecedência?', 'question');
        }
        if (NO.test(f) || /^(?:esta\s+bom|ta\s+bom|pode\s+ser|assim\s+mesmo|mantenha|manter|ok)\b/.test(f)) {
          ctx.pending = null;
          return reply('Mantido: aviso ' + task.reminderOffsetsMinutes.map(describeLead).join(' e ') + '.', 'ok');
        }
        return null;
      }
      if (p.type === 'choose') {
        if (NO.test(f)) { ctx.pending = null; return reply('Certo. Nada foi alterado.', 'ok'); }
        const cands = p.ids.map(find).filter((t) => t && t.status === 'pending');
        let chosen = null;
        const m = ORD.exec(f);
        if (m) {
          const k = m[1].replace(/[ao]$/, '');
          const n = /^\d$/.test(m[1]) ? +m[1] : (ORD_MAP[k] || ORD_MAP[m[1]]);
          chosen = cands[n - 1] || null;
        }
        if (!chosen) {
          const q = tokens(f);
          const sc = cands.map((t) => ({ t, s: scoreTask(q, t) })).filter((x) => x.s >= 0.5).sort((a, b) => b.s - a.s);
          if (sc.length === 1 || (sc.length > 1 && sc[0].s > sc[1].s + 0.05)) chosen = sc[0].t;
          if (!chosen) {
            const wd = new Work(f); const wh = extractWhen(wd);
            if (wh.date && wh.date.kind === 'weekday') {
              const byDay = cands.filter((t) => t.dueAt && new Date(t.dueAt).getDay() === wh.date.wd);
              if (byDay.length === 1) chosen = byDay[0];
            }
          }
        }
        if (!chosen) {
          if (f.split(/\s+/).length <= 3 && !RE_QUERY.test(f)) {
            ctx.pending.at = now.getTime();
            return reply('Não identifiquei a opção. Diga o número, de 1 a ' + cands.length + ', ou "cancelar".', 'question');
          }
          return null;
        }
        ctx.pending = null;
        return act(p.action, chosen, p.payload);
      }
      if (p.type === 'when') {
        if (NO.test(f)) { ctx.pending = null; return reply('Certo, não registrei.', 'ok'); }
        const ww = new Work(text);
        const rem = extractReminders(ww, false);
        const wh = extractWhen(ww);
        if (!wh.date && !wh.time && !wh.rel) return null;
        const r = resolveWhen(wh, now, p.draft.recurrence);
        if (r.error) return reply(r.error + ' Para quando?', 'question');
        ctx.pending = null;
        return finishCreate(Object.assign({}, p.draft, { due: r.due, allDay: r.allDay, rolled: r.rolled, reminders: rem.list || p.draft.reminders }));
      }
      if (p.type === 'title') {
        if (NO.test(f) && f.length < 12) { ctx.pending = null; return reply('Certo, não registrei.', 'ok'); }
        const t = cleanTitle(w.rest());
        if (!t) return null;
        ctx.pending = null;
        return finishCreate(Object.assign({}, p.draft, { title: t, kind: RE_EVENT.test(fold(t)) ? 'event' : p.draft.kind }));
      }
      if (p.type === 'past') {
        if (YES.test(f)) {
          ctx.pending = null;
          const d = p.draft.due;
          return finishCreate(Object.assign({}, p.draft, { due: nextOccurrenceDate(d, { freq: 'daily' }, now) }));
        }
        if (NO.test(f)) { ctx.pending = null; return reply('Certo, não registrei.', 'ok'); }
        return null;
      }
      return null;
    }

    function help() {
      return reply('Posso criar tarefas e compromissos, consultar sua agenda, concluir, transferir e cancelar tarefas, ajustar avisos e criar recorrências. ' +
        'Por exemplo: "amanhã às 15 horas me lembre de ligar para o contador", "o que tenho amanhã?", "transfira a reunião de sexta para segunda às 9", "conclua a tarefa do fornecedor" ou "desfazer".', 'info');
    }

    /** Ponto de entrada: texto falado ou digitado → resposta. */
    function handle(text, source) {
      source = source || 'text';
      const now = clock();
      if (ctx.pending && now.getTime() - ctx.pending.at > 3 * 60000) ctx.pending = null;
      if (ctx.pending) {
        const r = answerPending(String(text || ''));
        if (r) return r;
        ctx.pending = null;
      }
      const it = parse(text, now);
      switch (it.type) {
        case 'empty': return reply('Pois não' + sir() + '?', 'question');
        case 'undo': {
          const u = undo.pop();
          if (!u) return reply('Não há nada para desfazer.', 'info');
          const cur = JSON.stringify(tasks);
          tasks = JSON.parse(u.data);
          if (!persist()) { tasks = JSON.parse(cur); undo.push(u); return failSave(); }
          ctx.pending = null;
          return reply('Desfeito: ' + u.label + '.', 'ok', { changed: true });
        }
        case 'help': return help();
        case 'time': return reply('São ' + atTime(now).replace(/^(?:às|à|ao)\s+/, '') + '.', 'info');
        case 'date': return reply('Hoje é ' + WEEKDAY_FULL[now.getDay()] + ', ' + now.getDate() + ' de ' + MONTH_FULL[now.getMonth()] + ' de ' + now.getFullYear() + '.', 'info');
        case 'error': return reply(it.message, 'error');
        case 'summary': {
          if (!it.enable) { settings.summary.enabled = false; saveSettings(); return reply('Resumo diário desativado.', 'ok'); }
          settings.summary.enabled = true;
          settings.summary.time = it.time || settings.summary.time || '08:00';
          if (!saveSettings()) return failSave();
          const [hh, mm] = settings.summary.time.split(':').map(Number);
          return reply('Resumo diário ativado, todos os dias ' + atTime(new Date(2000, 0, 1, hh, mm)) + '. Nesta versão web, ele é apresentado se a página estiver aberta.', 'ok');
        }
        case 'query': return doQuery(it);
        case 'complete': return withTarget(it, 'complete', 'concluir');
        case 'cancel': return withTarget(it, 'cancel', 'cancelar');
        case 'setReminder': return withTarget(it, 'setReminder', 'ajustar o aviso');
        case 'reschedule':
          if (it.missing) {
            const r = locate(it);
            const t = r.task ? r.task.title : 'a tarefa';
            return reply('Para quando devo transferir ' + t + '? Diga, por exemplo: "transfira ' + (r.task ? 'a ' + t.toLowerCase() : 'a reunião') + ' para segunda às 9".', 'question');
          }
          return withTarget(it, 'reschedule', 'transferir');
        case 'create': return doCreate(it, source);
        default: return reply('Não entendi. Pode repetir?', 'error');
      }
    }

    // ---- API para a interface
    function saveSettings() {
      try { const j = JSON.stringify(settings); storage.setItem(KEY_SETTINGS, j); return storage.getItem(KEY_SETTINGS) === j; } catch (e) { return false; }
    }
    function addManual(p) {
      const now = clock();
      if (!p.title || !String(p.title).trim()) return reply('Informe uma descrição para a tarefa.', 'error');
      let due = p.due || null;
      if (due && p.allDay) due = startOfDay(due);
      const draft = { title: String(p.title).trim(), due, allDay: !!(due && p.allDay), reminders: due && !p.allDay ? (p.reminders || []) : [], recurrence: p.recurrence || null, kind: p.kind || 'task', source: 'manual', reminderVerb: true };
      if (draft.recurrence && draft.recurrence.freq === 'weekly' && due) draft.recurrence = { freq: 'weekly', byDay: [due.getDay()] };
      if (draft.recurrence && draft.recurrence.freq === 'monthly' && due) draft.recurrence = { freq: 'monthly', day: due.getDate() };
      if (draft.recurrence && !due) return reply('Uma recorrência precisa de data e hora iniciais.', 'error');
      const saved = finishCreate(draft);
      if (ctx.pending && ctx.pending.type === 'lead') ctx.pending = null;
      void now;
      return saved;
    }
    function update(id, patch) {
      const t = find(id);
      if (!t) return reply('Tarefa não encontrada.', 'error');
      const res = commit('editar "' + t.title + '"', () => {
        if (patch.title != null && String(patch.title).trim()) t.title = String(patch.title).trim();
        if ('due' in patch) { t.dueAt = patch.due ? (patch.allDay ? startOfDay(patch.due) : patch.due).toISOString() : null; t.allDay = !!(patch.due && patch.allDay); t.notified = []; }
        if (patch.reminders) t.reminderOffsetsMinutes = patch.reminders.slice();
        if ('recurrence' in patch) {
          let r = patch.recurrence;
          if (r && t.dueAt) { const d = new Date(t.dueAt); if (r.freq === 'weekly') r = { freq: 'weekly', byDay: [d.getDay()] }; if (r.freq === 'monthly') r = { freq: 'monthly', day: d.getDate() }; }
          t.recurrenceRule = t.dueAt ? r : null;
        }
        if (!t.dueAt || t.allDay) t.reminderOffsetsMinutes = [];
        t.updatedAt = clock().toISOString();
      });
      return res.ok ? reply('Alterações salvas: ' + t.title + '.', 'ok', { changed: true, taskId: id }) : failSave();
    }
    function setDone(id, done) {
      const t = find(id);
      if (!t) return reply('Tarefa não encontrada.', 'error');
      if (done) return act('complete', t, {});
      const res = commit('reabrir "' + t.title + '"', () => { t.status = 'pending'; t.completedAt = null; t.updatedAt = clock().toISOString(); });
      return res.ok ? reply('Reaberta: ' + t.title + '.', 'ok', { changed: true }) : failSave();
    }
    function remove(id) {
      const t = find(id);
      if (!t) return reply('Tarefa não encontrada.', 'error');
      const res = commit('excluir "' + t.title + '"', () => { tasks = tasks.filter((x) => x.id !== id); });
      return res.ok ? reply('Excluída: ' + t.title + '.', 'ok', { changed: true }) : failSave();
    }
    /** Avisos vencidos. `missed`: venceu com a página fechada (até 12 h atrás). */
    function dueReminders() {
      const now = clock().getTime();
      const out = [];
      let dirty = false;
      for (const t of tasks) {
        if (t.status !== 'pending' || !t.dueAt || t.allDay) continue;
        for (const o of t.reminderOffsetsMinutes) {
          const key = t.dueAt + '|' + o;
          if (t.notified.includes(key)) continue;
          const fire = new Date(t.dueAt).getTime() - o * 60000;
          if (now < fire) continue;
          if (now - fire <= 5 * 60000) out.push({ task: t, offset: o, key, missed: false });
          else if (now - fire <= 12 * 3600000) out.push({ task: t, offset: o, key, missed: true });
          else { t.notified.push(key); dirty = true; }
        }
      }
      if (dirty) persist();
      return out;
    }
    function markNotified(id, key) {
      const t = find(id);
      if (!t) return;
      if (!t.notified.includes(key)) t.notified.push(key);
      t.lastNotificationAt = clock().toISOString();
      persist();
    }
    function summaryDue() {
      const s = settings.summary;
      if (!s.enabled) return false;
      const now = clock();
      if (s.lastRun === dayKey(now)) return false;
      const [h, m] = String(s.time || '08:00').split(':').map(Number);
      const at = new Date(now.getFullYear(), now.getMonth(), now.getDate(), h, m);
      return now >= at && now - at < 6 * 3600000;
    }
    function markSummary() { settings.summary.lastRun = dayKey(clock()); saveSettings(); }
    function exportData() {
      return JSON.stringify({ app: 'JARVIS AI', version: VERSION, exportedAt: clock().toISOString(), timezone: localTz(), tasks, settings: Object.assign({}, settings, { voiceURI: '' }) }, null, 2);
    }
    function importData(json) {
      let data;
      try { data = JSON.parse(json); } catch (e) { return reply('Arquivo inválido.', 'error'); }
      const arr = Array.isArray(data) ? data : data && Array.isArray(data.tasks) ? data.tasks : null;
      if (!arr) return reply('O arquivo não contém tarefas.', 'error');
      const nowIso = clock().toISOString();
      const incoming = arr.map((t) => ('date' in t && !('dueAt' in t) ? migrateLegacyTask(t, nowIso) : normalizeTask(t, nowIso)));
      const res = commit('importar backup', () => {
        const byId = new Map(tasks.map((t) => [t.id, t]));
        for (const t of incoming) byId.set(t.id, t);
        tasks = Array.from(byId.values());
      });
      return res.ok ? reply('Backup importado: ' + incoming.length + ' tarefas.', 'ok', { changed: true }) : failSave();
    }

    return {
      handle, addManual, update, setDone, remove, dueReminders, markNotified, summaryDue, summaryText, markSummary,
      exportData, importData, saveSettings,
      get tasks() { return tasks; },
      get settings() { return settings; },
      get pending() { return ctx.pending; },
      get canUndo() { return undo.length > 0; },
      get undoLabel() { return undo.length ? undo[undo.length - 1].label : ''; },
      clearPending() { ctx.pending = null; },
      status,
      inRange: (t, q) => inRange(t, q, clock()),
      sortTasks
    };
  }

  return {
    VERSION, KEY_TASKS, KEY_SETTINGS, KEY_LEGACY,
    fold, parse, cleanTitle, extractWhen, resolveWhen, extractReminders, extractRecurrence, Work,
    nextOccurrenceDate, classifyVoice, rankVoices, createEngine, loadTasks, migrateLegacyTask,
    describeWhen, describeLead, describeRecurrence, dayLabel, atTime, dayKey, tokens
  };
});
