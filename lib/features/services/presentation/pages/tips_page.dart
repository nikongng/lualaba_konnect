import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TipsPage extends StatefulWidget {
  const TipsPage({super.key});

  @override
  State<TipsPage> createState() => _TipsPageState();
}

class _TipsPageState extends State<TipsPage> {
  static const Color _accent = Color(0xFF00A88E);
  static const String _cacheKey = 'tips.dailyAdvice.v1';

  _DailyAdvice? _dailyAdvice;
  bool _loadingAdvice = true;
  String? _adviceNotice;

  static const List<_StaticTip> _fallbackTips = [
    _StaticTip(
      category: 'TECH',
      title: 'Economiser sa batterie',
      desc: 'En zone de faible reseau, activez le mode economie et gardez une batterie de secours si vous devez sortir longtemps.',
      icon: Icons.battery_charging_full_rounded,
      iconBg: Color(0xFF64B5F6),
    ),
    _StaticTip(
      category: 'VIE PRATIQUE',
      title: 'Toujours garder une reserve',
      desc: 'Pensez a garder un peu d eau, vos documents essentiels et une lampe si vous vous deplacez loin de chez vous.',
      icon: Icons.backpack_outlined,
      iconBg: Colors.teal,
    ),
    _StaticTip(
      category: 'SECURITE',
      title: 'Partager sa destination',
      desc: 'Avant un deplacement, dites a un proche ou vous allez et gardez votre telephone suffisamment charge.',
      icon: Icons.shield_outlined,
      iconBg: Colors.orange,
    ),
  ];

  @override
  void initState() {
    super.initState();
    unawaited(_loadDailyAdvice());
  }

  Future<void> _loadDailyAdvice({bool forceRefresh = false}) async {
    final cachedAdvice = await _readCachedAdvice();
    final todayKey = _todayKey();
    final hasLiveCachedHeadlines = cachedAdvice != null && cachedAdvice.headlines.isNotEmpty;

    if (!forceRefresh && cachedAdvice != null && cachedAdvice.dayKey == todayKey && hasLiveCachedHeadlines) {
      if (!mounted) return;
      setState(() {
        _dailyAdvice = cachedAdvice;
        _loadingAdvice = false;
        _adviceNotice = null;
      });
      return;
    }

    if (mounted) {
      setState(() {
        _dailyAdvice = cachedAdvice;
        _loadingAdvice = true;
        _adviceNotice = cachedAdvice != null ? 'Actualisation des infos internet du Lualaba...' : null;
      });
    }

    try {
      final headlines = await _fetchLualabaHeadlines();
      final advice = _buildAdviceFromHeadlines(headlines);
      await _saveCachedAdvice(advice);
      if (!mounted) return;
      setState(() {
        _dailyAdvice = advice;
        _loadingAdvice = false;
        _adviceNotice = null;
      });
    } catch (_) {
      final fallback = cachedAdvice ?? _buildGenericAdvice();
      if (!mounted) return;
      setState(() {
        _dailyAdvice = fallback;
        _loadingAdvice = false;
        _adviceNotice = cachedAdvice != null ? 'Derniere mise a jour conservee en local.' : null;
      });
    }
  }

  Future<_DailyAdvice?> _readCachedAdvice() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return _DailyAdvice.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveCachedAdvice(_DailyAdvice advice) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cacheKey, jsonEncode(advice.toJson()));
  }

  Future<List<_LualabaHeadline>> _fetchLualabaHeadlines() async {
    final headlines = <_LualabaHeadline>[];
    final seen = <String>{};

    for (final item in await _fetchRadioOkapiHeadlines()) {
      final identity = '${item.title}|${item.source}|${item.link}';
      if (!seen.add(identity)) continue;
      headlines.add(item);
    }

    final feedUris = <Uri>[
      Uri.https('news.google.com', '/rss/search', <String, String>{
        'q': 'Lualaba OR Kolwezi OR Fungurume when:7d',
        'hl': 'fr',
        'gl': 'CD',
        'ceid': 'CD:fr',
      }),
      Uri.https('news.google.com', '/rss/search', <String, String>{
        'q': 'Kolwezi Lualaba actualite when:7d',
        'hl': 'fr',
        'gl': 'CD',
        'ceid': 'CD:fr',
      }),
      Uri.https('www.bing.com', '/news/search', <String, String>{
        'q': 'Lualaba Kolwezi Fungurume',
        'format': 'rss',
        'setlang': 'fr',
      }),
    ];

    for (final feedUri in feedUris) {
      if (headlines.length >= 6) break;
      final response = await http
          .get(
            feedUri,
            headers: const <String, String>{
              'User-Agent': 'Mozilla/5.0 (compatible; LualabaKonnect/1.0)',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        continue;
      }

      for (final item in _parseRssItems(response.body)) {
        final identity = '${item.title}|${item.source}|${item.link}';
        if (!seen.add(identity)) continue;
        headlines.add(item);
      }

      if (headlines.length >= 6) break;
    }

    headlines.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
    return headlines.take(6).toList();
  }

  Future<List<_LualabaHeadline>> _fetchRadioOkapiHeadlines() async {
    final pages = <Uri>[
      Uri.parse('https://www.radiookapi.net/mot-cle/lualaba'),
      Uri.parse('https://www.radiookapi.net/mot-cle/kolwezi'),
      Uri.parse('https://www.radiookapi.net/region/lualaba'),
    ];
    final headlines = <_LualabaHeadline>[];
    final seenLinks = <String>{};

    for (final page in pages) {
      try {
        final response = await http.get(
          page,
          headers: const <String, String>{
            'User-Agent': 'Mozilla/5.0 (compatible; LualabaKonnect/1.0)',
          },
        ).timeout(const Duration(seconds: 10));
        if (response.statusCode != 200) continue;

        for (final item in _parseRadioOkapiHtml(response.body)) {
          if (!seenLinks.add(item.link)) continue;
          headlines.add(item);
        }
      } catch (_) {
        // Best effort: other sources below can still answer.
      }
    }

    headlines.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
    return headlines.take(8).toList();
  }

  List<_LualabaHeadline> _parseRadioOkapiHtml(String html) {
    final items = <_LualabaHeadline>[];
    final articlePattern = RegExp(
      r'<a[^>]+href="(?:(https://www\.radiookapi\.net/20\d{2}/[^"]+)|(/20\d{2}/[^"]+))"[^>]*>([\s\S]*?)</a>',
      caseSensitive: false,
    );
    final datePattern = RegExp(r'(\d{2}/\d{2}/\d{4}\s*-\s*\d{2}:\d{2})');

    for (final match in articlePattern.allMatches(html)) {
      final rawHref = (match.group(1) ?? match.group(2) ?? '').trim();
      final rawTitle = match.group(3) ?? '';
      final title = _cleanXmlText(rawTitle);
      if (rawHref.isEmpty || title.length < 12) continue;
      if (_looksLikeNoiseTitle(title)) continue;

      final absoluteLink = rawHref.startsWith('http') ? rawHref : 'https://www.radiookapi.net$rawHref';
      final tailEnd = match.end + 220 > html.length ? html.length : match.end + 220;
      final tail = html.substring(match.end, tailEnd);
      final dateMatch = datePattern.firstMatch(tail);

      items.add(
        _LualabaHeadline(
          title: title,
          source: 'Radio Okapi',
          link: absoluteLink,
          publishedAt: dateMatch == null ? DateTime.now() : _parseNumericDate(dateMatch.group(1)!),
        ),
      );
    }

    return items;
  }

  bool _looksLikeNoiseTitle(String value) {
    final lower = value.toLowerCase();
    if (lower == 'image') return true;
    if (lower.contains('facebook') || lower.contains('twitter') || lower.contains('tunein')) return true;
    if (lower.contains('accueil') || lower.contains('actualite')) return true;
    return false;
  }

  DateTime _parseNumericDate(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    try {
      return DateFormat('dd/MM/yyyy - HH:mm').parse(cleaned);
    } catch (_) {
      return DateTime.now();
    }
  }

  List<_LualabaHeadline> _parseRssItems(String rss) {
    final items = <_LualabaHeadline>[];
    final itemMatches = RegExp(r'<item>([\s\S]*?)</item>', caseSensitive: false).allMatches(rss);

    for (final match in itemMatches) {
      final block = match.group(1) ?? '';
      final source = _cleanXmlText(_extractTag(block, 'source'));
      final rawTitle = _cleanXmlText(_extractTag(block, 'title'));
      final title = _normalizeHeadline(rawTitle, source);
      if (title.isEmpty) continue;

      items.add(
        _LualabaHeadline(
          title: title,
          source: source.isEmpty ? 'Internet' : source,
          link: _cleanXmlText(_extractTag(block, 'link')),
          publishedAt: _parsePubDate(_cleanXmlText(_extractTag(block, 'pubDate'))),
        ),
      );
    }

    return items;
  }

  String _extractTag(String block, String tag) {
    final match = RegExp('<$tag(?:\\s[^>]*)?>([\\s\\S]*?)</$tag>', caseSensitive: false).firstMatch(block);
    return match?.group(1) ?? '';
  }

  String _cleanXmlText(String raw) {
    var value = raw.trim();
    value = value.replaceAll('<![CDATA[', '').replaceAll(']]>', '');
    value = value.replaceAll(RegExp(r'<[^>]+>'), ' ');
    value = value
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&#39;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>');

    value = value.replaceAllMapped(RegExp(r'&#(\d+);'), (match) {
      final code = int.tryParse(match.group(1) ?? '');
      return code == null ? '' : String.fromCharCode(code);
    });

    value = value.replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (match) {
      final code = int.tryParse(match.group(1) ?? '', radix: 16);
      return code == null ? '' : String.fromCharCode(code);
    });

    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _normalizeHeadline(String title, String source) {
    var value = title.trim();
    if (source.isNotEmpty) {
      final suffix = ' - $source';
      if (value.toLowerCase().endsWith(suffix.toLowerCase())) {
        value = value.substring(0, value.length - suffix.length).trim();
      }
    }
    return value;
  }

  DateTime _parsePubDate(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return DateTime.now();
    final formats = <DateFormat>[
      DateFormat("EEE, dd MMM yyyy HH:mm:ss 'GMT'", 'en_US'),
      DateFormat('EEE, dd MMM yyyy HH:mm:ss Z', 'en_US'),
      DateFormat('EEE, dd MMM yyyy HH:mm:ss', 'en_US'),
    ];

    for (final format in formats) {
      try {
        return format.parseUtc(value).toLocal();
      } catch (_) {
        // Continue with the next format.
      }
    }

    return DateTime.tryParse(value)?.toLocal() ?? DateTime.now();
  }

  _DailyAdvice _buildAdviceFromHeadlines(List<_LualabaHeadline> headlines) {
    if (headlines.isEmpty) {
      return _buildGenericAdvice();
    }

    final topicScores = <String, int>{};
    for (var i = 0; i < headlines.length; i++) {
      final topic = _topicKeyFromText(headlines[i].title);
      topicScores[topic] = (topicScores[topic] ?? 0) + (i == 0 ? 3 : 2);
    }

    var topicKey = 'general';
    var bestScore = -1;
    topicScores.forEach((key, value) {
      if (value > bestScore) {
        bestScore = value;
        topicKey = key;
      }
    });

    final topHeadline = headlines.first;
    final sourceNames = headlines
        .map((item) => item.source.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .take(2)
        .join(', ');

    return switch (topicKey) {
      'weather' => _DailyAdvice(
          topicKey: topicKey,
          title: 'Restez loin des zones inondables',
          message:
              'Les actus recentes du Lualaba parlent de pluies ou d inondations. Evitez les routes basses, gardez vos papiers au sec et prevoyez une lampe chargee.',
          generatedAt: DateTime.now(),
          sourceLabel: sourceNames.isEmpty ? 'Actualites internet du Lualaba' : sourceNames,
          dayKey: _todayKey(),
          headlines: headlines,
        ),
      'mine_safety' => _DailyAdvice(
          topicKey: topicKey,
          title: 'Prudence autour des sites miniers',
          message:
              'Des titres recents signalent des eboulements ou incidents miniers au Lualaba. Evitez les zones instables, surtout apres la pluie, et limitez les passages non essentiels.',
          generatedAt: DateTime.now(),
          sourceLabel: sourceNames.isEmpty ? 'Actualites internet du Lualaba' : sourceNames,
          dayKey: _todayKey(),
          headlines: headlines,
        ),
      'security' => _DailyAdvice(
          topicKey: topicKey,
          title: 'Evitez les attroupements a tension',
          message:
              'Des nouvelles recentes evoquent des tensions ou violences locales. Deplacez-vous de preference de jour, evitez les foules nerveuses et partagez seulement des infos verifiees.',
          generatedAt: DateTime.now(),
          sourceLabel: sourceNames.isEmpty ? 'Actualites internet du Lualaba' : sourceNames,
          dayKey: _todayKey(),
          headlines: headlines,
        ),
      'health' => _DailyAdvice(
          topicKey: topicKey,
          title: 'Renforcez hygiene et prevention',
          message:
              'Les actus sante du Lualaba meritent de la vigilance. Lavez-vous souvent les mains, buvez une eau sure et consultez rapidement en cas de symptomes inhabituels.',
          generatedAt: DateTime.now(),
          sourceLabel: sourceNames.isEmpty ? 'Actualites internet du Lualaba' : sourceNames,
          dayKey: _todayKey(),
          headlines: headlines,
        ),
      'utilities' => _DailyAdvice(
          topicKey: topicKey,
          title: 'Preparez eau et batterie a l avance',
          message:
              'Des informations pratiques touchent les services du quotidien. Gardez une petite reserve d eau, chargez votre telephone et anticipez les courses importantes.',
          generatedAt: DateTime.now(),
          sourceLabel: sourceNames.isEmpty ? 'Actualites internet du Lualaba' : sourceNames,
          dayKey: _todayKey(),
          headlines: headlines,
        ),
      'traffic' => _DailyAdvice(
          topicKey: topicKey,
          title: 'Planifiez vos trajets avant de sortir',
          message:
              'Les titres recents parlent de circulation ou d incidents de route. Verifiez votre itineraire, partez plus tot et gardez un contact joignable pendant le trajet.',
          generatedAt: DateTime.now(),
          sourceLabel: sourceNames.isEmpty ? 'Actualites internet du Lualaba' : sourceNames,
          dayKey: _todayKey(),
          headlines: headlines,
        ),
      'economy' => _DailyAdvice(
          topicKey: topicKey,
          title: 'Verifiez prix et disponibilites avant achat',
          message:
              'Les actualites economiques du Lualaba peuvent vite faire bouger les habitudes. Comparez les prix, confirmez le stock avant de vous deplacer et gardez une marge dans le budget.',
          generatedAt: DateTime.now(),
          sourceLabel: sourceNames.isEmpty ? 'Actualites internet du Lualaba' : sourceNames,
          dayKey: _todayKey(),
          headlines: headlines,
        ),
      _ => _DailyAdvice(
          topicKey: 'general',
          title: 'Restez informe avant de bouger',
          message:
              'Le conseil du jour est construit a partir des titres internet recents sur le Lualaba. Avant de sortir, verifiez l etat local, chargez votre telephone et gardez un plan B.',
          generatedAt: DateTime.now(),
          sourceLabel: sourceNames.isEmpty ? topHeadline.source : sourceNames,
          dayKey: _todayKey(),
          headlines: headlines,
        ),
    };
  }

  _DailyAdvice _buildGenericAdvice() {
    return _DailyAdvice(
      topicKey: 'general',
      title: 'Conseil local du jour',
      message:
          'Chargez votre telephone, privilegiez les trajets utiles et verifiez les infos locales importantes avant de sortir dans le Lualaba.',
      generatedAt: DateTime.now(),
      sourceLabel: 'Conseil local Lualaba',
      dayKey: _todayKey(),
      headlines: const <_LualabaHeadline>[],
    );
  }

  String _topicKeyFromText(String text) {
    final lower = text.toLowerCase();
    if (_containsAny(lower, ['inond', 'pluie', 'averse', 'orage', 'crue'])) return 'weather';
    if (_containsAny(lower, ['eboulement', 'glissement', 'mine', 'carriere', 'creuseur', 'safi', 'lubudi'])) {
      return 'mine_safety';
    }
    if (_containsAny(lower, ['justice populaire', 'violence', 'insecur', 'attaque', 'police', 'rumeur'])) {
      return 'security';
    }
    if (_containsAny(lower, ['cholera', 'rougeole', 'epidem', 'hopital', 'sante', 'palud'])) return 'health';
    if (_containsAny(lower, ['regideso', 'snel', 'coupure', 'eau', 'electricite', 'panne'])) return 'utilities';
    if (_containsAny(lower, ['route', 'trafic', 'accident', 'pont', 'circulation', 'transport'])) return 'traffic';
    if (_containsAny(lower, ['prix', 'carburant', 'marche', 'commerce', 'hausse', 'emploi'])) return 'economy';
    return 'general';
  }

  bool _containsAny(String text, List<String> values) {
    for (final value in values) {
      if (text.contains(value)) return true;
    }
    return false;
  }

  String _todayKey() => DateFormat('yyyy-MM-dd').format(DateTime.now());

  Future<void> _shareAdvice(_DailyAdvice advice) async {
    final headlines = advice.headlines.take(3).map((item) => '- ${item.title} (${item.source})').join('\n');
    final text = StringBuffer()
      ..writeln(advice.title)
      ..writeln()
      ..writeln(advice.message)
      ..writeln()
      ..writeln('Source(s): ${advice.sourceLabel}');

    if (headlines.isNotEmpty) {
      text
        ..writeln()
        ..writeln('Titres analyses:')
        ..writeln(headlines);
    }

    await Share.share(text.toString().trim(), subject: 'Conseil du jour - Lualaba');
  }

  List<Widget> _buildTipCards({
    required Color card,
    required Color text,
    required Color sub,
  }) {
    final liveHeadlines = _dailyAdvice?.headlines ?? const <_LualabaHeadline>[];
    final cards = <Widget>[];

    for (final item in liveHeadlines.take(3)) {
      final style = _topicStyle(_topicKeyFromText(item.title));
      cards.add(
        _TipCard(
          card: card,
          text: text,
          sub: sub,
          category: style.label,
          title: item.title,
          desc: '${item.source} - ${DateFormat('dd/MM/yyyy HH:mm').format(item.publishedAt)}',
          icon: style.icon,
          iconBg: style.color,
        ),
      );
    }

    if (cards.isEmpty) {
      for (final item in _fallbackTips) {
        cards.add(
          _TipCard(
            card: card,
            text: text,
            sub: sub,
            category: item.category,
            title: item.title,
            desc: item.desc,
            icon: item.icon,
            iconBg: item.iconBg,
          ),
        );
      }
      return cards;
    }

    cards.add(
      _TipCard(
        card: card,
        text: text,
        sub: sub,
        category: _fallbackTips.first.category,
        title: _fallbackTips.first.title,
        desc: _fallbackTips.first.desc,
        icon: _fallbackTips.first.icon,
        iconBg: _fallbackTips.first.iconBg,
      ),
    );

    return cards;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0B141A) : const Color(0xFFF6F7F9);
    final card = isDark ? const Color(0xFF111B21) : Colors.white;
    final text = isDark ? const Color(0xFFE9EDF0) : const Color(0xFF111827);
    final sub = isDark ? const Color(0xFFAAB2B8) : const Color(0xFF6B7280);
    final divider = isDark ? Colors.white12 : Colors.black12;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: _accent,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Conseils utiles', style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: RefreshIndicator(
        color: _accent,
        onRefresh: () => _loadDailyAdvice(forceRefresh: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            _HighlightCard(
              card: card,
              text: text,
              sub: sub,
              divider: divider,
              advice: _dailyAdvice,
              loading: _loadingAdvice,
              notice: _adviceNotice,
              onRefresh: () => _loadDailyAdvice(forceRefresh: true),
              onShare: _dailyAdvice == null ? null : () => _shareAdvice(_dailyAdvice!),
            ),
            _FilterChips(card: card, sub: sub, divider: divider),
            ..._buildTipCards(card: card, text: text, sub: sub),
          ],
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: _ProposeBar(card: card, sub: sub, divider: divider),
    );
  }
}

class _HighlightCard extends StatelessWidget {
  const _HighlightCard({
    required this.card,
    required this.text,
    required this.sub,
    required this.divider,
    required this.advice,
    required this.loading,
    required this.notice,
    required this.onRefresh,
    required this.onShare,
  });

  final Color card;
  final Color text;
  final Color sub;
  final Color divider;
  final _DailyAdvice? advice;
  final bool loading;
  final String? notice;
  final VoidCallback onRefresh;
  final VoidCallback? onShare;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final style = _topicStyle(advice?.topicKey ?? 'general');
    final metaText = advice == null
        ? 'Internet Lualaba'
        : '${DateFormat('dd/MM/yyyy HH:mm').format(advice!.generatedAt)} - ${advice!.sourceLabel}';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.30 : 0.06),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF00A88E).withOpacity(isDark ? 0.20 : 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF00A88E).withOpacity(0.25)),
                ),
                child: const Text(
                  'CONSEIL DU JOUR',
                  style: TextStyle(color: Color(0xFF00A88E), fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.8),
                ),
              ),
              const Spacer(),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: loading ? null : onRefresh,
                icon: loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(Icons.refresh_rounded, color: sub, size: 20),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: onShare,
                icon: Icon(Icons.share_outlined, color: onShare == null ? sub.withOpacity(0.5) : sub, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            advice?.title ?? 'Recherche des actus du Lualaba...',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: text, letterSpacing: -0.2),
          ),
          const SizedBox(height: 8),
          Text(
            advice?.message ?? 'Le conseil du jour se construit a partir des titres internet recents sur le Lualaba.',
            style: TextStyle(color: sub, height: 1.35, fontWeight: FontWeight.w600),
          ),
          if ((notice ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(isDark ? 0.18 : 0.10),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.orange.withOpacity(0.28)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, size: 16, color: Colors.orange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      notice!,
                      style: TextStyle(color: sub, height: 1.2, fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(style.icon, size: 15, color: style.color),
              Expanded(
                child: Text(
                  ' $metaText',
                  style: TextStyle(color: sub, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FilterChips extends StatelessWidget {
  const _FilterChips({
    required this.card,
    required this.sub,
    required this.divider,
  });

  final Color card;
  final Color sub;
  final Color divider;

  @override
  Widget build(BuildContext context) {
    final filters = const ['Tout', 'Sante', 'Securite', 'Tech', 'Vie pratique'];
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      height: 50,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 15),
        itemCount: filters.length,
        itemBuilder: (context, index) {
          final selected = index == 0;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: Chip(
              backgroundColor: selected ? const Color(0xFF00A88E) : card,
              label: Text(filters[index], style: TextStyle(color: selected ? Colors.white : sub, fontWeight: FontWeight.w700)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: selected ? Colors.transparent : divider),
              ),
              shadowColor: Colors.black.withOpacity(isDark ? 0.35 : 0.08),
              elevation: selected ? 8 : 0,
            ),
          );
        },
      ),
    );
  }
}

class _TipCard extends StatelessWidget {
  const _TipCard({
    required this.card,
    required this.text,
    required this.sub,
    required this.category,
    required this.title,
    required this.desc,
    required this.icon,
    required this.iconBg,
  });

  final Color card;
  final Color text;
  final Color sub;
  final String category;
  final String title;
  final String desc;
  final IconData icon;
  final Color iconBg;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(top: 14, left: 20, right: 20),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.28 : 0.06),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconBg.withOpacity(isDark ? 0.22 : 0.14),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: iconBg.withOpacity(0.25)),
            ),
            child: Icon(icon, color: iconBg, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        category,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: sub, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.1),
                      ),
                    ),
                    Icon(Icons.bookmark_border, size: 18, color: sub),
                  ],
                ),
                const SizedBox(height: 2),
                Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: text, letterSpacing: -0.2)),
                const SizedBox(height: 6),
                Text(
                  desc,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: sub, fontSize: 13, height: 1.25, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProposeBar extends StatelessWidget {
  const _ProposeBar({required this.card, required this.sub, required this.divider});

  final Color card;
  final Color sub;
  final Color divider;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const accent = Color(0xFF00A88E);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.30 : 0.06),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: accent.withOpacity(isDark ? 0.22 : 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: accent.withOpacity(0.25)),
            ),
            child: const Icon(Icons.lightbulb_outline, color: accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Vous avez une astuce ? Partagez-la avec la communaute',
              style: TextStyle(color: sub, fontSize: 12, fontWeight: FontWeight.w700, height: 1.1),
            ),
          ),
          ElevatedButton(
            onPressed: () {},
            style: ElevatedButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Proposer', style: TextStyle(fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }
}

class _DailyAdvice {
  const _DailyAdvice({
    required this.topicKey,
    required this.title,
    required this.message,
    required this.generatedAt,
    required this.sourceLabel,
    required this.dayKey,
    required this.headlines,
  });

  final String topicKey;
  final String title;
  final String message;
  final DateTime generatedAt;
  final String sourceLabel;
  final String dayKey;
  final List<_LualabaHeadline> headlines;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'topicKey': topicKey,
      'title': title,
      'message': message,
      'generatedAt': generatedAt.toIso8601String(),
      'sourceLabel': sourceLabel,
      'dayKey': dayKey,
      'headlines': headlines.map((item) => item.toJson()).toList(),
    };
  }

  factory _DailyAdvice.fromJson(Map<String, dynamic> json) {
    final rawHeadlines = json['headlines'];
    final items = <_LualabaHeadline>[];
    if (rawHeadlines is List) {
      for (final item in rawHeadlines) {
        if (item is Map<String, dynamic>) {
          items.add(_LualabaHeadline.fromJson(item));
        } else if (item is Map) {
          items.add(_LualabaHeadline.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }

    return _DailyAdvice(
      topicKey: (json['topicKey'] ?? 'general').toString(),
      title: (json['title'] ?? 'Conseil du jour').toString(),
      message: (json['message'] ?? '').toString(),
      generatedAt: DateTime.tryParse((json['generatedAt'] ?? '').toString())?.toLocal() ?? DateTime.now(),
      sourceLabel: (json['sourceLabel'] ?? 'Internet').toString(),
      dayKey: (json['dayKey'] ?? '').toString(),
      headlines: items,
    );
  }
}

class _LualabaHeadline {
  const _LualabaHeadline({
    required this.title,
    required this.source,
    required this.link,
    required this.publishedAt,
  });

  final String title;
  final String source;
  final String link;
  final DateTime publishedAt;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'title': title,
      'source': source,
      'link': link,
      'publishedAt': publishedAt.toIso8601String(),
    };
  }

  factory _LualabaHeadline.fromJson(Map<String, dynamic> json) {
    return _LualabaHeadline(
      title: (json['title'] ?? '').toString(),
      source: (json['source'] ?? '').toString(),
      link: (json['link'] ?? '').toString(),
      publishedAt: DateTime.tryParse((json['publishedAt'] ?? '').toString())?.toLocal() ?? DateTime.now(),
    );
  }
}

class _StaticTip {
  const _StaticTip({
    required this.category,
    required this.title,
    required this.desc,
    required this.icon,
    required this.iconBg,
  });

  final String category;
  final String title;
  final String desc;
  final IconData icon;
  final Color iconBg;
}

class _TopicStyle {
  const _TopicStyle({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;
}

_TopicStyle _topicStyle(String topicKey) {
  return switch (topicKey) {
    'weather' => const _TopicStyle(label: 'METEO', icon: Icons.cloud_outlined, color: Colors.blue),
    'mine_safety' => const _TopicStyle(label: 'SECURITE', icon: Icons.engineering_rounded, color: Colors.orange),
    'security' => const _TopicStyle(label: 'SECURITE', icon: Icons.shield_outlined, color: Colors.redAccent),
    'health' => const _TopicStyle(label: 'SANTE', icon: Icons.health_and_safety_outlined, color: Colors.pinkAccent),
    'utilities' => const _TopicStyle(label: 'VIE PRATIQUE', icon: Icons.power_outlined, color: Colors.teal),
    'traffic' => const _TopicStyle(label: 'TRAJET', icon: Icons.alt_route_rounded, color: Colors.indigo),
    'economy' => const _TopicStyle(label: 'ECONOMIE', icon: Icons.storefront_outlined, color: Colors.green),
    _ => const _TopicStyle(label: 'ACTUALITE', icon: Icons.public_rounded, color: Color(0xFF00A88E)),
  };
}
