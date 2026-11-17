<?php
require_once __DIR__.'/../config/config.php';

set_time_limit(0);
header('Content-Type: text/event-stream');
header('Cache-Control: no-cache');
header('Connection: keep-alive');
header('X-Accel-Buffering: no');

$lastId = isset($_GET['last_id']) ? (int)$_GET['last_id'] : 0;

for ($i=0; $i<55; $i++) {
    if (connection_aborted()) break;

    $pdo = db();
    $q = $pdo->prepare(
        "SELECT a.id,a.bus_code,a.type,a.message,a.ldr_value,a.created_at,
                s.codigo stop_code,s.nome stop_name
         FROM alerts a JOIN stops s ON s.id=a.stop_id
         WHERE a.id > ? ORDER BY a.id ASC"
    );
    $q->execute([$lastId]);
    $rows = $q->fetchAll();

    foreach ($rows as $row) {
        $lastId = (int)$row['id'];
        echo "event: arrival\n";
        echo "data: ".json_encode($row, JSON_UNESCAPED_UNICODE)."\n\n";
    }

    echo "event: heartbeat\n";
    echo "data: {\"time\":\"".date('c')."\"}\n\n";
    @ob_flush();
    @flush();
    sleep(1);
}
