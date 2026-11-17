<?php
require_once __DIR__.'/../config/config.php';

$pdo = db();
$buses = $pdo->query("SELECT codigo,latitude,longitude,gps_fix,led_status,last_seen FROM buses")->fetchAll();
$stops = $pdo->query("SELECT codigo,nome,latitude,longitude,ldr_value,detected,last_seen FROM stops")->fetchAll();
$alerts = $pdo->query(
    "SELECT a.id,a.bus_code,a.type,a.message,a.ldr_value,a.created_at,s.codigo stop_code,s.nome stop_name
     FROM alerts a JOIN stops s ON s.id=a.stop_id
     ORDER BY a.id DESC LIMIT 20"
)->fetchAll();

json_response(['ok'=>true,'buses'=>$buses,'stops'=>$stops,'alerts'=>$alerts,'server_time'=>date('c')]);
