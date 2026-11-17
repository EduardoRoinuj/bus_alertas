<?php
require_once __DIR__.'/../config/config.php';
require_token();

$input = json_decode(file_get_contents('php://input'), true) ?: $_POST;
$codigo = trim((string)($input['bus_code'] ?? 'BUS-01'));
$lat = isset($input['latitude']) ? (float)$input['latitude'] : null;
$lng = isset($input['longitude']) ? (float)$input['longitude'] : null;
$fix = !empty($input['gps_fix']) ? 1 : 0;
$led = !empty($input['led']) ? 1 : 0;

$stmt = db()->prepare(
    "INSERT INTO buses (codigo,latitude,longitude,gps_fix,led_status,last_seen)
     VALUES (?,?,?,?,?,NOW())
     ON DUPLICATE KEY UPDATE latitude=VALUES(latitude), longitude=VALUES(longitude),
     gps_fix=VALUES(gps_fix), led_status=VALUES(led_status), last_seen=NOW()"
);
$stmt->execute([$codigo,$lat,$lng,$fix,$led]);

json_response(['ok'=>true,'bus_code'=>$codigo,'server_time'=>date('c')]);
