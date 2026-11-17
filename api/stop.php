<?php
require_once __DIR__.'/../config/config.php';
require_token();

$input = json_decode(file_get_contents('php://input'), true) ?: $_POST;
$codigo = strtoupper(trim((string)($input['stop_code'] ?? '')));
$ldr = (int)($input['ldr_value'] ?? 0);
$detected = !empty($input['detected']) ? 1 : 0;
$busCode = trim((string)($input['bus_code'] ?? 'BUS-01'));

if (!in_array($codigo, ['RONIL','PANDORA'], true)) {
    json_response(['ok'=>false,'error'=>'Paragem inválida'], 400);
}

$pdo = db();
$stmt = $pdo->prepare("UPDATE stops SET ldr_value=?, detected=?, last_seen=NOW() WHERE codigo=?");
$stmt->execute([$ldr,$detected,$codigo]);

if ($detected) {
    $stop = $pdo->prepare("SELECT id,nome FROM stops WHERE codigo=?");
    $stop->execute([$codigo]);
    $row = $stop->fetch();

    // Anti-duplicação: não cria outro alerta se houve um igual nos últimos 20 segundos.
    $dup = $pdo->prepare(
        "SELECT id FROM alerts WHERE stop_id=? AND type='CHEGADA'
         AND created_at >= DATE_SUB(NOW(), INTERVAL 20 SECOND) LIMIT 1"
    );
    $dup->execute([$row['id']]);
    if (!$dup->fetch()) {
        $msg = "Autocarro $busCode chegou à paragem ".$row['nome'];
        $ins = $pdo->prepare(
            "INSERT INTO alerts(stop_id,bus_code,type,message,ldr_value,created_at)
             VALUES(?,?,?,?,?,NOW())"
        );
        $ins->execute([$row['id'],$busCode,'CHEGADA',$msg,$ldr]);
    }
}

json_response(['ok'=>true,'stop_code'=>$codigo,'detected'=>(bool)$detected]);
