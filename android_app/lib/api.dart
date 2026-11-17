import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// URL do servidor gratuito (Render). Pode ser alterado nas definições da app.
const String kDefaultServer = 'https://bus-alertas.onrender.com';

class Bus {
  final String code;
  final double? lat, lng;
  final bool gpsFix, led, online;
  final double? speedKmh;
  final DateTime? lastSeen;

  Bus.fromJson(Map<String, dynamic> j)
      : code = j['codigo'] as String,
        lat = (j['latitude'] as num?)?.toDouble(),
        lng = (j['longitude'] as num?)?.toDouble(),
        gpsFix = j['gps_fix'] == true,
        led = j['led_status'] == true,
        online = j['online'] == true,
        speedKmh = (j['speed_kmh'] as num?)?.toDouble(),
        lastSeen = _date(j['last_seen']);
}

class Stop {
  final String code, name;
  final double lat, lng;
  final int ldr;
  final bool online;
  final DateTime? lastSeen, lastArrival;
  final String? lastBus;
  final int? distanceM;

  Stop.fromJson(Map<String, dynamic> j)
      : code = j['codigo'] as String,
        name = j['nome'] as String,
        lat = (j['latitude'] as num).toDouble(),
        lng = (j['longitude'] as num).toDouble(),
        ldr = (j['ldr_value'] as num?)?.toInt() ?? 0,
        online = j['online'] == true,
        lastSeen = _date(j['last_seen']),
        lastArrival = _date(j['last_arrival']),
        lastBus = j['last_bus'] as String?,
        distanceM = (j['distance_m'] as num?)?.toInt();
}

class Alert {
  final int id;
  final String stopCode, stopName, message;
  final String? busCode;
  final DateTime createdAt;

  Alert.fromJson(Map<String, dynamic> j)
      : id = (j['id'] as num).toInt(),
        stopCode = j['stop_code'] as String,
        stopName = j['stop_name'] as String,
        message = j['message'] as String,
        busCode = j['bus_code'] as String?,
        createdAt = _date(j['created_at'])!;
}

class Stats {
  final int busesOnline, busesTotal, stopsOnline, stopsTotal, arrivals24h;
  Stats.fromJson(Map<String, dynamic> j)
      : busesOnline = j['buses_online'] ?? 0,
        busesTotal = j['buses_total'] ?? 0,
        stopsOnline = j['stops_online'] ?? 0,
        stopsTotal = j['stops_total'] ?? 0,
        arrivals24h = j['arrivals_24h'] ?? 0;
}

class Snapshot {
  final DateTime serverTime;
  final int lastId;
  final Stats stats;
  final List<Bus> buses;
  final List<Stop> stops;
  final List<Alert> alerts, newAlerts;

  Snapshot.fromJson(Map<String, dynamic> j)
      : serverTime = _date(j['server_time']) ?? DateTime.now().toUtc(),
        lastId = (j['last_id'] as num?)?.toInt() ?? 0,
        stats = Stats.fromJson(j['stats'] as Map<String, dynamic>),
        buses = (j['buses'] as List).map((e) => Bus.fromJson(e)).toList(),
        stops = (j['stops'] as List).map((e) => Stop.fromJson(e)).toList(),
        alerts = (j['alerts'] as List).map((e) => Alert.fromJson(e)).toList(),
        newAlerts = ((j['new_alerts'] as List?) ?? []).map((e) => Alert.fromJson(e)).toList();
}

DateTime? _date(dynamic v) => v is String ? DateTime.tryParse(v)?.toUtc() : null;

class Api {
  final http.Client _client = http.Client();
  String server = kDefaultServer;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    server = prefs.getString('server') ?? kDefaultServer;
  }

  Future<void> setServer(String url) async {
    server = url.trim().replaceAll(RegExp(r'/+$'), '');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server', server);
  }

  Future<Snapshot> fetch({int? since}) async {
    final uri = Uri.parse('$server/api/state${since != null ? '?since=$since' : ''}');
    final res = await _client.get(uri).timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    return Snapshot.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }
}
