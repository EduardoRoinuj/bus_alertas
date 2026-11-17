import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'notifier.dart';

// ---------------------------------------------------------------------------
// Paleta (igual ao painel web)
// ---------------------------------------------------------------------------
class C {
  static const bg = Color(0xFF0B1120);
  static const card = Color(0xFF172033);
  static const card2 = Color(0xFF1F293D);
  static const border = Color(0x29FFFFFF);
  static const fg = Color(0xFFF8FAFC);
  static const fg2 = Color(0xFFCBD5E1);
  static const muted = Color(0xFF94A3B8);
  static const green = Color(0xFF22C55E);
  static const greenDark = Color(0xFF052E16);
  static const blue = Color(0xFF38BDF8);
  static const amber = Color(0xFFF59E0B);
  static const violet = Color(0xFFA78BFA);
  static const red = Color(0xFFF87171);
}

const _mono = TextStyle(fontFeatures: [FontFeature.tabularFigures()], fontWeight: FontWeight.w600);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: C.bg,
  ));
  runApp(const BusAlertasApp());
}

class BusAlertasApp extends StatelessWidget {
  const BusAlertasApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: C.green,
      brightness: Brightness.dark,
      surface: C.bg,
      primary: C.green,
      onPrimary: C.greenDark,
    );
    return MaterialApp(
      title: 'Bus Alertas',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: scheme,
        scaffoldBackgroundColor: C.bg,
        useMaterial3: true,
        cardTheme: const CardThemeData(
          color: C.card,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
            side: BorderSide(color: C.border),
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: C.card,
          indicatorColor: C.green.withValues(alpha: .18),
          labelTextStyle: WidgetStateProperty.all(const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ),
      ),
      home: const HomePage(),
    );
  }
}

// ---------------------------------------------------------------------------
// Ecrã principal
// ---------------------------------------------------------------------------
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

enum Live { connecting, online, offline }

class _HomePageState extends State<HomePage> with WidgetsBindingObserver, TickerProviderStateMixin {
  final api = Api();
  final notifier = Notifier();
  final mapController = MapController();

  Snapshot? snap;
  Live live = Live.connecting;
  int? lastId;
  int failures = 0;
  int tab = 0;
  bool follow = false;
  bool foreground = true;
  Duration serverOffset = Duration.zero;
  Alert? banner;
  final Map<String, DateTime> arrivedUntil = {};

  Timer? _pollTimer, _tick, _bannerTimer;

  // animação suave do autocarro
  late final AnimationController _busAnim =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
  final Map<String, LatLng> _busFrom = {}, _busTo = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && foreground) setState(() {});
    });
  }

  Future<void> _start() async {
    await api.load();
    final prefs = await SharedPreferences.getInstance();
    notifier.soundOn = prefs.getBool('sound') ?? true;
    await notifier.init();
    _poll();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _tick?.cancel();
    _bannerTimer?.cancel();
    _busAnim.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    foreground = s == AppLifecycleState.resumed;
    if (foreground) _poll();
  }

  // ----------------------------- polling ---------------------------------
  Future<void> _poll() async {
    _pollTimer?.cancel();
    try {
      final data = await api.fetch(since: lastId);
      _apply(data);
      failures = 0;
      live = Live.online;
    } catch (_) {
      failures++;
      if (failures >= 2) live = Live.offline;
    }
    if (mounted) setState(() {});
    final base = foreground ? 2000 : 6000;
    final ms = failures == 0 ? base : math.min(15000, base * (1 << math.min(failures, 3)));
    _pollTimer = Timer(Duration(milliseconds: ms), _poll);
  }

  void _apply(Snapshot data) {
    serverOffset = data.serverTime.difference(DateTime.now().toUtc());
    final first = lastId == null;

    // posições do autocarro para animação
    final current = _busPositions();
    for (final b in data.buses) {
      if (b.lat == null) continue;
      final to = LatLng(b.lat!, b.lng!);
      _busFrom[b.code] = current[b.code] ?? to;
      _busTo[b.code] = to;
    }
    _busAnim.forward(from: 0);

    snap = data;
    lastId = data.lastId;

    if (!first) {
      for (final a in data.newAlerts) {
        arrivedUntil[a.stopCode] = DateTime.now().add(const Duration(seconds: 45));
        notifier.arrival(a, inForeground: foreground);
        _showBanner(a);
      }
    }
    if (follow && _busTo.isNotEmpty) {
      mapController.move(_busTo.values.first, mapController.camera.zoom);
    }
  }

  Map<String, LatLng> _busPositions() {
    final t = Curves.easeOutCubic.transform(_busAnim.value);
    return {
      for (final k in _busTo.keys)
        k: LatLng(
          _busFrom[k]!.latitude + (_busTo[k]!.latitude - _busFrom[k]!.latitude) * t,
          _busFrom[k]!.longitude + (_busTo[k]!.longitude - _busFrom[k]!.longitude) * t,
        ),
    };
  }

  void _showBanner(Alert a) {
    setState(() => banner = a);
    _bannerTimer?.cancel();
    _bannerTimer = Timer(const Duration(seconds: 9), () {
      if (mounted) setState(() => banner = null);
    });
  }

  // ----------------------------- helpers ---------------------------------
  DateTime get _now => DateTime.now().toUtc().add(serverOffset);

  String ago(DateTime? t) {
    if (t == null) return '—';
    final s = math.max(0, _now.difference(t).inSeconds);
    if (s < 5) return 'agora';
    if (s < 60) return 'há $s s';
    final m = s ~/ 60;
    if (m < 60) return 'há $m min';
    final h = m ~/ 60;
    if (h < 24) return 'há $h h';
    return 'há ${h ~/ 24} d';
  }

  String clock(DateTime t) {
    final l = t.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(l.hour)}:${two(l.minute)}:${two(l.second)}';
  }

  String dist(int? m) => m == null ? '—' : m < 1000 ? '$m m' : '${(m / 1000).toStringAsFixed(1)} km';

  bool arrived(String code) => (arrivedUntil[code]?.isAfter(DateTime.now())) ?? false;

  void _fitAll() {
    final pts = <LatLng>[
      ...?snap?.stops.map((s) => LatLng(s.lat, s.lng)),
      ..._busTo.values,
    ];
    if (pts.isEmpty) return;
    mapController.fitCamera(CameraFit.bounds(
      bounds: LatLngBounds.fromPoints(pts),
      padding: const EdgeInsets.all(70),
      maxZoom: 17,
    ));
  }

  void _goToStop(Stop s) {
    setState(() {
      tab = 0;
      follow = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => mapController.move(LatLng(s.lat, s.lng), 18));
  }

  Future<void> _toggleSound() async {
    setState(() => notifier.soundOn = !notifier.soundOn);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sound', notifier.soundOn);
  }

  Future<void> _openSettings() async {
    final ctrl = TextEditingController(text: api.server);
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: C.card,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(children: [
              FaIcon(FontAwesomeIcons.server, size: 18, color: C.green),
              SizedBox(width: 10),
              Text('Servidor', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 6),
            const Text('Endereço onde o sistema está hospedado.', style: TextStyle(color: C.muted)),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'URL do servidor',
                hintText: 'https://bus-alertas.onrender.com',
                border: OutlineInputBorder(),
                prefixIcon: Padding(padding: EdgeInsets.all(14), child: FaIcon(FontAwesomeIcons.link, size: 16)),
              ),
            ),
            const SizedBox(height: 16),
            Row(children: [
              TextButton(
                onPressed: () => ctrl.text = kDefaultServer,
                child: const Text('Repor'),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => Navigator.pop(ctx, true),
                icon: const FaIcon(FontAwesomeIcons.check, size: 16),
                label: const Text('Guardar'),
                style: FilledButton.styleFrom(minimumSize: const Size(120, 48)),
              ),
            ]),
          ],
        ),
      ),
    );
    if (saved == true) {
      await api.setServer(ctrl.text);
      setState(() {
        lastId = null;
        snap = null;
        live = Live.connecting;
        _busFrom.clear();
        _busTo.clear();
      });
      _poll();
    }
  }

  // ----------------------------- UI --------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: C.bg,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 16,
        title: Row(children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              gradient: const LinearGradient(colors: [C.green, Color(0xFF16A34A)]),
            ),
            alignment: Alignment.center,
            child: const FaIcon(FontAwesomeIcons.busSimple, size: 18, color: C.greenDark),
          ),
          const SizedBox(width: 12),
          const Text('Bus Alertas', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 19)),
        ]),
        actions: [
          _LivePill(live),
          IconButton(
            tooltip: notifier.soundOn ? 'Desactivar som' : 'Activar som',
            onPressed: _toggleSound,
            icon: FaIcon(notifier.soundOn ? FontAwesomeIcons.volumeHigh : FontAwesomeIcons.volumeXmark,
                size: 18, color: notifier.soundOn ? C.fg : C.muted),
          ),
          IconButton(
            tooltip: 'Definições',
            onPressed: _openSettings,
            icon: const FaIcon(FontAwesomeIcons.gear, size: 18),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Stack(children: [
        Column(children: [
          _kpis(),
          Expanded(
            child: IndexedStack(index: tab, children: [_mapTab(), _stopsTab(), _historyTab()]),
          ),
        ]),
        // banner de chegada
        AnimatedPositioned(
          duration: const Duration(milliseconds: 380),
          curve: Curves.easeOutBack,
          top: banner == null ? -140 : 8,
          left: 12,
          right: 12,
          child: banner == null ? const SizedBox.shrink() : _ArrivalBanner(banner!, clock(banner!.createdAt), () {
            setState(() => banner = null);
          }),
        ),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: [
          const NavigationDestination(icon: FaIcon(FontAwesomeIcons.map, size: 18), label: 'Mapa'),
          const NavigationDestination(icon: FaIcon(FontAwesomeIcons.signsPost, size: 18), label: 'Paragens'),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: (snap?.stats.arrivals24h ?? 0) > 0,
              label: Text('${snap?.stats.arrivals24h ?? 0}'),
              child: const FaIcon(FontAwesomeIcons.clockRotateLeft, size: 18),
            ),
            label: 'Histórico',
          ),
        ],
      ),
    );
  }

  Widget _kpis() {
    final st = snap?.stats;
    final lastArrival = snap?.alerts.isNotEmpty == true ? snap!.alerts.first.createdAt : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      child: Row(children: [
        _Kpi(FontAwesomeIcons.bus, C.green, 'Autocarros', st == null ? '–' : '${st.busesOnline}/${st.busesTotal}'),
        const SizedBox(width: 8),
        _Kpi(FontAwesomeIcons.towerBroadcast, C.blue, 'Paragens', st == null ? '–' : '${st.stopsOnline}/${st.stopsTotal}'),
        const SizedBox(width: 8),
        _Kpi(FontAwesomeIcons.flagCheckered, C.amber, 'Chegadas 24h', st == null ? '–' : '${st.arrivals24h}'),
        const SizedBox(width: 8),
        _Kpi(FontAwesomeIcons.clock, C.violet, 'Última', ago(lastArrival)),
      ]),
    );
  }

  // ----------------------------- Mapa -------------------------------------
  Widget _mapTab() {
    final stops = snap?.stops ?? [];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(children: [
          FlutterMap(
            mapController: mapController,
            options: MapOptions(
              initialCenter: const LatLng(-25.9652, 32.5781),
              initialZoom: 16,
              backgroundColor: const Color(0xFF0D1526),
              onMapReady: () => Future.delayed(const Duration(milliseconds: 600), _fitAll),
              onPositionChanged: (_, hasGesture) {
                if (hasGesture && follow) setState(() => follow = false);
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.busalertas.bus_alertas',
                tileBuilder: darkModeTileBuilder,
              ),
              MarkerLayer(markers: [
                for (final s in stops)
                  Marker(
                    point: LatLng(s.lat, s.lng),
                    width: 64,
                    height: 64,
                    alignment: Alignment.center,
                    child: GestureDetector(
                      onTap: () => _showStopSheet(s),
                      child: _StopPin(online: s.online, arrived: arrived(s.code)),
                    ),
                  ),
              ]),
              AnimatedBuilder(
                animation: _busAnim,
                builder: (_, _) {
                  final pos = _busPositions();
                  final buses = {for (final b in snap?.buses ?? <Bus>[]) b.code: b};
                  return MarkerLayer(markers: [
                    for (final e in pos.entries)
                      Marker(
                        point: e.value,
                        width: 48,
                        height: 48,
                        child: _BusPin(online: buses[e.key]?.online ?? false),
                      ),
                  ]);
                },
              ),
              const SimpleAttributionWidget(source: Text('OpenStreetMap')),
            ],
          ),
          Positioned(
            top: 12,
            right: 12,
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              _MapChip(icon: FontAwesomeIcons.expand, label: 'Ver tudo', onTap: _fitAll),
              const SizedBox(height: 8),
              _MapChip(
                icon: FontAwesomeIcons.locationCrosshairs,
                label: 'Seguir',
                active: follow,
                onTap: () {
                  setState(() => follow = !follow);
                  if (follow && _busTo.isNotEmpty) mapController.move(_busTo.values.first, 17);
                },
              ),
            ]),
          ),
          if (snap == null)
            Positioned.fill(
              child: Container(
                color: C.bg.withValues(alpha: .6),
                alignment: Alignment.center,
                child: live == Live.offline ? _offlineMessage() : const CircularProgressIndicator(),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _offlineMessage() => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const FaIcon(FontAwesomeIcons.plugCircleXmark, size: 36, color: C.red),
          const SizedBox(height: 12),
          const Text('Sem ligação ao servidor', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 4),
          Text(api.server, style: const TextStyle(color: C.muted), textAlign: TextAlign.center),
          const SizedBox(height: 4),
          const Text('O servidor gratuito pode demorar ~50 s a acordar.',
              style: TextStyle(color: C.muted, fontSize: 12), textAlign: TextAlign.center),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: _openSettings,
            icon: const FaIcon(FontAwesomeIcons.gear, size: 14),
            label: const Text('Alterar servidor'),
          ),
        ]),
      );

  void _showStopSheet(Stop s) {
    showModalBottomSheet(
      context: context,
      backgroundColor: C.card,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: _StopCard(stop: s, arrived: arrived(s.code), ago: ago, dist: dist),
      ),
    );
  }

  // ----------------------------- Paragens ---------------------------------
  Widget _stopsTab() {
    final stops = snap?.stops ?? [];
    final buses = snap?.buses ?? [];
    return RefreshIndicator(
      onRefresh: _poll,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
        children: [
          const _SectionTitle(FontAwesomeIcons.signsPost, 'Paragens'),
          for (final s in stops) ...[
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _goToStop(s),
              child: _StopCard(stop: s, arrived: arrived(s.code), ago: ago, dist: dist),
            ),
            const SizedBox(height: 10),
          ],
          const _SectionTitle(FontAwesomeIcons.bus, 'Frota'),
          if (buses.isEmpty)
            const _Empty(FontAwesomeIcons.satellite, 'À espera do primeiro sinal do autocarro…'),
          for (final b in buses) ...[
            _BusCard(bus: b, ago: ago),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  // ----------------------------- Histórico --------------------------------
  Widget _historyTab() {
    final alerts = snap?.alerts ?? [];
    if (alerts.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Align(alignment: Alignment.topCenter, child: _Empty(FontAwesomeIcons.bellSlash, 'Sem chegadas registadas ainda')),
      );
    }
    return RefreshIndicator(
      onRefresh: _poll,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
        itemCount: alerts.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final a = alerts[i];
          return Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: C.green.withValues(alpha: .14), borderRadius: BorderRadius.circular(10)),
                alignment: Alignment.center,
                child: const FaIcon(FontAwesomeIcons.flagCheckered, size: 16, color: C.green),
              ),
              title: Text(a.stopName, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('${a.busCode ?? '—'} · ${ago(a.createdAt)}', style: const TextStyle(color: C.muted)),
              trailing: Text(clock(a.createdAt), style: _mono.copyWith(color: C.fg2)),
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Widgets
// ---------------------------------------------------------------------------
class _LivePill extends StatelessWidget {
  final Live live;
  const _LivePill(this.live);

  @override
  Widget build(BuildContext context) {
    final (color, text) = switch (live) {
      Live.online => (C.green, 'Ao vivo'),
      Live.offline => (C.red, 'Offline'),
      Live.connecting => (C.amber, 'A ligar'),
    };
    return Semantics(
      liveRegion: true,
      label: 'Estado: $text',
      child: Container(
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .14),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: color.withValues(alpha: .35)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          _Pulse(color: color, active: live != Live.offline),
          const SizedBox(width: 6),
          Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }
}

class _Pulse extends StatefulWidget {
  final Color color;
  final bool active;
  const _Pulse({required this.color, required this.active});
  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, _) => Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: widget.color,
            shape: BoxShape.circle,
            boxShadow: widget.active
                ? [BoxShadow(color: widget.color.withValues(alpha: (1 - _c.value) * .7), spreadRadius: _c.value * 5)]
                : null,
          ),
        ),
      );
}

class _Kpi extends StatelessWidget {
  final FaIconData icon;
  final Color color;
  final String label, value;
  const _Kpi(this.icon, this.color, this.label, this.value);

  @override
  Widget build(BuildContext context) => Expanded(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              FaIcon(icon, size: 14, color: color),
              const SizedBox(height: 6),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                child: Text(value,
                    key: ValueKey(value),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _mono.copyWith(fontSize: 16, color: C.fg)),
              ),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.muted, fontSize: 11)),
            ]),
          ),
        ),
      );
}

class _StopPin extends StatefulWidget {
  final bool online, arrived;
  const _StopPin({required this.online, required this.arrived});
  @override
  State<_StopPin> createState() => _StopPinState();
}

class _StopPinState extends State<_StopPin> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.online ? C.green : const Color(0xFF475569);
    return Stack(alignment: Alignment.center, children: [
      if (widget.arrived)
        AnimatedBuilder(
          animation: _c,
          builder: (_, _) => Container(
            width: 30 + 34 * _c.value,
            height: 30 + 34 * _c.value,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: C.green.withValues(alpha: 1 - _c.value), width: 3),
            ),
          ),
        ),
      Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: C.bg, width: 2.5),
          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, 4))],
        ),
        alignment: Alignment.center,
        child: FaIcon(FontAwesomeIcons.signsPost, size: 15, color: widget.online ? C.greenDark : Colors.white),
      ),
    ]);
  }
}

class _BusPin extends StatelessWidget {
  final bool online;
  const _BusPin({required this.online});
  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: online ? C.blue : const Color(0xFF64748B),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: C.bg, width: 2.5),
            boxShadow: [
              if (online) BoxShadow(color: C.blue.withValues(alpha: .3), spreadRadius: 6),
              const BoxShadow(color: Colors.black54, blurRadius: 12, offset: Offset(0, 4)),
            ],
          ),
          alignment: Alignment.center,
          child: FaIcon(FontAwesomeIcons.bus, size: 17, color: online ? const Color(0xFF082F49) : Colors.white),
        ),
      );
}

class _MapChip extends StatelessWidget {
  final FaIconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  const _MapChip({required this.icon, required this.label, required this.onTap, this.active = false});

  @override
  Widget build(BuildContext context) => Material(
        color: active ? C.green : C.bg.withValues(alpha: .88),
        shape: StadiumBorder(side: BorderSide(color: active ? C.green : C.border)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                FaIcon(icon, size: 14, color: active ? C.greenDark : C.fg),
                const SizedBox(width: 8),
                Text(label,
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: active ? C.greenDark : C.fg)),
              ]),
            ),
          ),
        ),
      );
}

class _StopCard extends StatelessWidget {
  final Stop stop;
  final bool arrived;
  final String Function(DateTime?) ago;
  final String Function(int?) dist;
  const _StopCard({required this.stop, required this.arrived, required this.ago, required this.dist});

  @override
  Widget build(BuildContext context) {
    final ok = stop.online;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: arrived ? C.green.withValues(alpha: .12) : C.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: arrived ? C.green.withValues(alpha: .7) : C.border, width: arrived ? 1.5 : 1),
        boxShadow: arrived ? [BoxShadow(color: C.green.withValues(alpha: .25), blurRadius: 24)] : null,
      ),
      child: Column(children: [
        Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: arrived ? C.green : (ok ? C.green.withValues(alpha: .14) : C.card2),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: FaIcon(FontAwesomeIcons.signsPost, size: 18, color: arrived ? C.greenDark : (ok ? C.green : C.muted)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(stop.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              Text(stop.code, style: _mono.copyWith(color: C.muted, fontSize: 12, fontWeight: FontWeight.w500)),
            ]),
          ),
          _StatusChip(
            icon: arrived ? FontAwesomeIcons.bus : (ok ? FontAwesomeIcons.wifi : FontAwesomeIcons.plugCircleXmark),
            text: arrived ? 'Autocarro aqui' : (ok ? 'Online' : 'Offline'),
            color: ok || arrived ? C.green : C.muted,
          ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          _Meta(FontAwesomeIcons.sun, 'LDR', ok ? '${stop.ldr}' : '—'),
          const SizedBox(width: 8),
          _Meta(FontAwesomeIcons.route, 'Distância', dist(stop.distanceM)),
          const SizedBox(width: 8),
          _Meta(FontAwesomeIcons.clock, 'Chegada', ago(stop.lastArrival)),
        ]),
      ]),
    );
  }
}

class _BusCard extends StatelessWidget {
  final Bus bus;
  final String Function(DateTime?) ago;
  const _BusCard({required this.bus, required this.ago});

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(children: [
            Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: bus.online ? C.blue.withValues(alpha: .14) : C.card2,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: FaIcon(FontAwesomeIcons.bus, size: 18, color: bus.online ? C.blue : C.muted),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(bus.code, style: _mono.copyWith(fontSize: 16)),
                  Text('Visto ${ago(bus.lastSeen)}', style: const TextStyle(color: C.muted, fontSize: 12)),
                ]),
              ),
              _StatusChip(
                icon: bus.online ? FontAwesomeIcons.wifi : FontAwesomeIcons.plugCircleXmark,
                text: bus.online ? 'Online' : 'Offline',
                color: bus.online ? C.green : C.muted,
              ),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              _Meta(FontAwesomeIcons.satellite, 'GPS', bus.gpsFix ? 'OK' : 'Sem fix'),
              const SizedBox(width: 8),
              _Meta(FontAwesomeIcons.gaugeHigh, 'Velocidade', bus.speedKmh == null ? '—' : '${bus.speedKmh!.toStringAsFixed(0)} km/h'),
              const SizedBox(width: 8),
              _Meta(FontAwesomeIcons.lightbulb, 'LED', bus.led ? 'Activo' : 'Off'),
            ]),
          ]),
        ),
      );
}

class _StatusChip extends StatelessWidget {
  final FaIconData icon;
  final String text;
  final Color color;
  const _StatusChip({required this.icon, required this.text, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: color.withValues(alpha: .14), borderRadius: BorderRadius.circular(99)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          FaIcon(icon, size: 11, color: color),
          const SizedBox(width: 6),
          Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
        ]),
      );
}

class _Meta extends StatelessWidget {
  final FaIconData icon;
  final String label, value;
  const _Meta(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(color: C.bg.withValues(alpha: .55), borderRadius: BorderRadius.circular(10)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              FaIcon(icon, size: 10, color: C.muted),
              const SizedBox(width: 5),
              Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.muted, fontSize: 11))),
            ]),
            const SizedBox(height: 2),
            Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: _mono.copyWith(fontSize: 14)),
          ]),
        ),
      );
}

class _SectionTitle extends StatelessWidget {
  final FaIconData icon;
  final String text;
  const _SectionTitle(this.icon, this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
        child: Row(children: [
          FaIcon(icon, size: 14, color: C.muted),
          const SizedBox(width: 8),
          Text(text, style: const TextStyle(color: C.fg2, fontWeight: FontWeight.w700, fontSize: 14)),
        ]),
      );
}

class _Empty extends StatelessWidget {
  final FaIconData icon;
  final String text;
  const _Empty(this.icon, this.text);
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: C.border),
        ),
        child: Row(children: [
          FaIcon(icon, size: 16, color: C.muted),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(color: C.muted))),
        ]),
      );
}

class _ArrivalBanner extends StatelessWidget {
  final Alert alert;
  final String time;
  final VoidCallback onClose;
  const _ArrivalBanner(this.alert, this.time, this.onClose);

  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF16A34A), Color(0xFF15803D)]),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [BoxShadow(color: C.green.withValues(alpha: .5), blurRadius: 30, offset: const Offset(0, 10))],
            ),
            child: Row(children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(13)),
                alignment: Alignment.center,
                child: const FaIcon(FontAwesomeIcons.solidBell, size: 20, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('AUTOCARRO NA PARAGEM',
                      style: TextStyle(color: Colors.white70, fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w700)),
                  Text(alert.message, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                  Text('$time · ${alert.stopCode}', style: _mono.copyWith(color: Colors.white70, fontSize: 12)),
                ]),
              ),
              IconButton(
                tooltip: 'Fechar',
                onPressed: onClose,
                icon: const FaIcon(FontAwesomeIcons.xmark, size: 16, color: Colors.white),
              ),
            ]),
          ),
        ),
      );
}
