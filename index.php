<?php
require_once __DIR__ . '/config/config.php';
?>
<!DOCTYPE html>
<html lang="pt">
<head>
    <meta charset="UTF-8">

    <meta
        name="viewport"
        content="width=device-width, initial-scale=1.0"
    >

    <title>Sistema de Detecção de Autocarros</title>

    <!-- =========================================================
         PRECONNECT
         Ajuda a reduzir o tempo inicial de carregamento
    ========================================================== -->
    <link rel="preconnect" href="https://unpkg.com" crossorigin>
    <link rel="preconnect" href="https://tile.openstreetmap.org" crossorigin>

    <!-- =========================================================
         LEAFLET CSS
    ========================================================== -->
    <link
        rel="stylesheet"
        href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css"
        crossorigin=""
    >

    <style>
        * {
            box-sizing: border-box;
        }

        html,
        body {
            margin: 0;
            padding: 0;
            width: 100%;
            height: 100%;
            font-family: Arial, Helvetica, sans-serif;
            background: #f4f6f8;
        }

        body {
            overflow: hidden;
        }

        /* =====================================================
           LAYOUT PRINCIPAL
        ====================================================== */

        .app {
            width: 100%;
            height: 100vh;
            display: flex;
            flex-direction: column;
        }

        .topbar {
            height: 64px;
            min-height: 64px;
            background: #291868;
            color: #fff;
            display: flex;
            align-items: center;
            justify-content: space-between;
            padding: 0 20px;
            box-shadow: 0 2px 8px rgba(0, 0, 0, .18);
            z-index: 1000;
        }

        .topbar-title {
            display: flex;
            align-items: center;
            gap: 12px;
        }

        .topbar-title .icon {
            width: 38px;
            height: 38px;
            border-radius: 50%;
            background: rgba(255, 255, 255, .15);
            display: flex;
            align-items: center;
            justify-content: center;
            font-size: 20px;
        }

        .topbar-title h1 {
            margin: 0;
            font-size: 18px;
            font-weight: 700;
        }

        .topbar-title span {
            display: block;
            margin-top: 2px;
            font-size: 12px;
            opacity: .78;
        }

        .system-status {
            display: flex;
            align-items: center;
            gap: 8px;
            font-size: 13px;
        }

        .status-dot {
            width: 10px;
            height: 10px;
            border-radius: 50%;
            background: #aaa;
        }

        .status-dot.online {
            background: #31d158;
            box-shadow: 0 0 8px rgba(49, 209, 88, .8);
        }

        .status-dot.offline {
            background: #ff453a;
        }

        /* =====================================================
           CONTEÚDO
        ====================================================== */

        .content {
            flex: 1;
            min-height: 0;
            display: flex;
        }

        .sidebar {
            width: 330px;
            min-width: 330px;
            background: #fff;
            border-right: 1px solid #ddd;
            overflow-y: auto;
            z-index: 900;
        }

        .sidebar-header {
            padding: 18px;
            border-bottom: 1px solid #eee;
        }

        .sidebar-header h2 {
            margin: 0 0 5px;
            font-size: 17px;
            color: #222;
        }

        .sidebar-header p {
            margin: 0;
            color: #777;
            font-size: 12px;
        }

        .stop-card {
            padding: 16px 18px;
            border-bottom: 1px solid #eee;
        }

        .stop-card-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            gap: 10px;
        }

        .stop-name {
            font-weight: 700;
            font-size: 15px;
            color: #222;
        }

        .stop-code {
            margin-top: 3px;
            color: #777;
            font-size: 11px;
        }

        .online-badge {
            display: inline-flex;
            align-items: center;
            gap: 5px;
            padding: 5px 8px;
            border-radius: 20px;
            font-size: 11px;
            font-weight: 600;
            background: #eee;
            color: #666;
            white-space: nowrap;
        }

        .online-badge::before {
            content: "";
            width: 7px;
            height: 7px;
            border-radius: 50%;
            background: #aaa;
        }

        .online-badge.online {
            background: #eaf9ee;
            color: #17833b;
        }

        .online-badge.online::before {
            background: #22c55e;
        }

        .online-badge.offline {
            background: #fff0ef;
            color: #c92a20;
        }

        .online-badge.offline::before {
            background: #ff453a;
        }

        .stop-info {
            margin-top: 12px;
            font-size: 12px;
            color: #555;
            line-height: 1.6;
        }

        .arrival-time {
            margin-top: 10px;
            padding: 9px 10px;
            border-radius: 8px;
            background: #f5f3fa;
            color: #291868;
            font-size: 12px;
            font-weight: 600;
        }

        .arrival-time.no-arrival {
            color: #777;
            background: #f7f7f7;
            font-weight: 400;
        }

        /* =====================================================
           MAPA
        ====================================================== */

        .map-wrapper {
            flex: 1;
            min-width: 0;
            min-height: 0;
            position: relative;
            background: #e8eaed;
        }

        #map {
            width: 100%;
            height: 100%;
            min-height: 300px;
            background: #e8eaed;
        }

        .map-loading {
            position: absolute;
            left: 50%;
            top: 50%;
            transform: translate(-50%, -50%);
            z-index: 500;
            background: rgba(255,255,255,.94);
            padding: 12px 18px;
            border-radius: 10px;
            box-shadow: 0 3px 14px rgba(0,0,0,.15);
            color: #555;
            font-size: 13px;
            pointer-events: none;
            transition: opacity .3s ease;
        }

        .map-loading.hidden {
            opacity: 0;
        }

        /* =====================================================
           ALERTA
        ====================================================== */

        #alertContainer {
            position: fixed;
            top: 80px;
            right: 20px;
            width: 350px;
            max-width: calc(100vw - 40px);
            z-index: 5000;
            pointer-events: none;
        }

        .arrival-alert {
            background: #fff;
            border-left: 5px solid #291868;
            border-radius: 10px;
            padding: 14px 16px;
            box-shadow: 0 6px 25px rgba(0,0,0,.2);
            animation: alertIn .3s ease;
            pointer-events: auto;
        }

        .arrival-alert-title {
            font-weight: 700;
            color: #291868;
            font-size: 15px;
            margin-bottom: 5px;
        }

        .arrival-alert-message {
            color: #333;
            font-size: 13px;
            line-height: 1.45;
        }

        .arrival-alert-time {
            margin-top: 7px;
            color: #777;
            font-size: 11px;
        }

        @keyframes alertIn {
            from {
                opacity: 0;
                transform: translateY(-12px);
            }

            to {
                opacity: 1;
                transform: translateY(0);
            }
        }

        /* =====================================================
           HISTÓRICO
        ====================================================== */

        .history {
            padding: 16px 18px;
        }

        .history-title {
            font-weight: 700;
            font-size: 14px;
            margin-bottom: 10px;
            color: #222;
        }

        .history-item {
            border-bottom: 1px solid #eee;
            padding: 9px 0;
        }

        .history-item:last-child {
            border-bottom: none;
        }

        .history-item strong {
            display: block;
            color: #291868;
            font-size: 12px;
        }

        .history-item span {
            display: block;
            margin-top: 2px;
            color: #777;
            font-size: 11px;
        }

        /* =====================================================
           BOTÃO SOM
        ====================================================== */

        .sound-button {
            position: fixed;
            right: 20px;
            bottom: 20px;
            z-index: 2000;
            border: none;
            border-radius: 50%;
            width: 48px;
            height: 48px;
            background: #291868;
            color: #fff;
            cursor: pointer;
            font-size: 20px;
            box-shadow: 0 4px 15px rgba(0,0,0,.25);
        }

        .sound-button:hover {
            transform: scale(1.05);
        }

        /* =====================================================
           MARCADORES
        ====================================================== */

        .custom-stop-marker {
            width: 34px;
            height: 34px;
            border-radius: 50%;
            background: #291868;
            border: 4px solid #fff;
            box-shadow: 0 2px 8px rgba(0,0,0,.35);
            display: flex;
            align-items: center;
            justify-content: center;
            color: #fff;
            font-size: 15px;
        }

        .custom-stop-marker.arrival {
            background: #da2618;
            animation: markerPulse 1.2s infinite;
        }

        .custom-bus-marker {
            width: 38px;
            height: 38px;
            border-radius: 50%;
            background: #da2618;
            border: 4px solid #fff;
            box-shadow: 0 2px 10px rgba(0,0,0,.4);
            display: flex;
            align-items: center;
            justify-content: center;
            color: #fff;
            font-size: 17px;
        }

        @keyframes markerPulse {
            0% {
                box-shadow:
                    0 0 0 0 rgba(218,38,24,.6),
                    0 2px 8px rgba(0,0,0,.35);
            }

            70% {
                box-shadow:
                    0 0 0 14px rgba(218,38,24,0),
                    0 2px 8px rgba(0,0,0,.35);
            }

            100% {
                box-shadow:
                    0 0 0 0 rgba(218,38,24,0),
                    0 2px 8px rgba(0,0,0,.35);
            }
        }

        /* =====================================================
           RESPONSIVO
        ====================================================== */

        @media (max-width: 800px) {
            .sidebar {
                width: 280px;
                min-width: 280px;
            }

            .topbar-title h1 {
                font-size: 15px;
            }

            .topbar-title span {
                display: none;
            }
        }

        @media (max-width: 600px) {
            .sidebar {
                display: none;
            }

            .topbar {
                height: 56px;
                min-height: 56px;
                padding: 0 12px;
            }

            #alertContainer {
                top: 66px;
                right: 10px;
                width: calc(100vw - 20px);
            }

            .sound-button {
                right: 15px;
                bottom: 15px;
            }
        }
    </style>
</head>

<body>

<div class="app">

    <!-- =====================================================
         CABEÇALHO
    ====================================================== -->
    <header class="topbar">

        <div class="topbar-title">

            <div class="icon">
                🚌
            </div>

            <div>
                <h1>Sistema de Detecção de Autocarros</h1>
                <span>Av. Eduardo Mondlane — Maputo</span>
            </div>

        </div>

        <div class="system-status">

            <div
                id="systemStatusDot"
                class="status-dot"
            ></div>

            <span id="systemStatusText">
                A ligar...
            </span>

        </div>

    </header>


    <!-- =====================================================
         CONTEÚDO
    ====================================================== -->
    <main class="content">

        <!-- =================================================
             BARRA LATERAL
        ================================================== -->
        <aside class="sidebar">

            <div class="sidebar-header">

                <h2>Paragens monitorizadas</h2>

                <p>
                    Estado de ligação e última chegada detectada.
                </p>

            </div>


            <!-- RONIL -->

            <div class="stop-card">

                <div class="stop-card-header">

                    <div>

                        <div class="stop-name">
                            Ronil
                        </div>

                        <div class="stop-code">
                            RONIL
                        </div>

                    </div>

                    <div
                        id="status-RONIL"
                        class="online-badge offline"
                    >
                        Offline
                    </div>

                </div>

                <div
                    id="info-RONIL"
                    class="stop-info"
                >
                    A aguardar ligação...
                </div>

                <div
                    id="arrival-RONIL"
                    class="arrival-time no-arrival"
                >
                    Nenhuma chegada registada.
                </div>

            </div>


            <!-- PANDORA -->

            <div class="stop-card">

                <div class="stop-card-header">

                    <div>

                        <div class="stop-name">
                            Pandora
                        </div>

                        <div class="stop-code">
                            PANDORA
                        </div>

                    </div>

                    <div
                        id="status-PANDORA"
                        class="online-badge offline"
                    >
                        Offline
                    </div>

                </div>

                <div
                    id="info-PANDORA"
                    class="stop-info"
                >
                    A aguardar ligação...
                </div>

                <div
                    id="arrival-PANDORA"
                    class="arrival-time no-arrival"
                >
                    Nenhuma chegada registada.
                </div>

            </div>


            <!-- HISTÓRICO -->

            <div class="history">

                <div class="history-title">
                    Últimas chegadas
                </div>

                <div id="historyList">
                    <div style="color:#888;font-size:12px;">
                        A carregar...
                    </div>
                </div>

            </div>

        </aside>


        <!-- =================================================
             MAPA
        ================================================== -->

        <section class="map-wrapper">

            <div id="map"></div>

            <div
                id="mapLoading"
                class="map-loading"
            >
                A carregar mapa...
            </div>

        </section>

    </main>

</div>


<!-- =========================================================
     ALERTAS
========================================================== -->

<div id="alertContainer"></div>


<!-- =========================================================
     BOTÃO SOM
========================================================== -->

<button
    id="soundButton"
    class="sound-button"
    title="Activar/desactivar som"
>
    🔊
</button>


<!-- =========================================================
     LEAFLET
========================================================== -->

<script>
/*
 * ============================================================
 * CARREGAMENTO NÃO BLOQUEANTE DO LEAFLET
 * ============================================================
 *
 * Em vez de bloquear o carregamento da página esperando pelo
 * JavaScript do Leaflet, carregamos a biblioteca dinamicamente.
 */

function loadLeaflet() {

    return new Promise(function(resolve, reject) {

        if (window.L) {
            resolve();
            return;
        }

        const script = document.createElement('script');

        script.src =
            'https://unpkg.com/leaflet@1.9.4/dist/leaflet.js';

        script.crossOrigin = '';

        script.onload = function() {
            resolve();
        };

        script.onerror = function() {
            reject(
                new Error('Não foi possível carregar o Leaflet.')
            );
        };

        document.head.appendChild(script);

    });

}
</script>


<script>
/*
 * ============================================================
 * CONFIGURAÇÃO
 * ============================================================
 */

const API_STATE = 'api/state.php';
const API_EVENTS = 'api/events.php';


/*
 * Coordenadas de fallback.
 *
 * O mapa consegue ser desenhado mesmo que o servidor demore
 * a responder.
 *
 * Se as coordenadas na base de dados forem diferentes,
 * serão automaticamente actualizadas pelo state.php.
 */

const STOP_CONFIG = {

    RONIL: {
        codigo: 'RONIL',
        nome: 'Ronil',
        latitude: -25.9641900,
        longitude: 32.5761100
    },

    PANDORA: {
        codigo: 'PANDORA',
        nome: 'Pandora',
        latitude: -25.9663470,
        longitude: 32.5800335
    }

};


/*
 * ============================================================
 * VARIÁVEIS
 * ============================================================
 */

let map = null;

let stopMarkers = {};

let busMarkers = {};

let lastAlertId = 0;

let soundEnabled = true;

let eventSource = null;


/*
 * Guarda a última chegada de cada paragem.
 *
 * Exemplo:
 *
 * lastArrivals.RONIL = {
 *      created_at: "2026-09-27 01:25:10",
 *      bus_code: "BUS001"
 * }
 */

const lastArrivals = {};


/*
 * ============================================================
 * ÍCONE DA PARAGEM
 * ============================================================
 */

function createStopIcon(arrival = false) {

    return L.divIcon({

        className: '',

        html: `
            <div class="custom-stop-marker ${arrival ? 'arrival' : ''}">
                🚏
            </div>
        `,

        iconSize: [34, 34],

        iconAnchor: [17, 17],

        popupAnchor: [0, -19]

    });

}


/*
 * ============================================================
 * ÍCONE DO AUTOCARRO
 * ============================================================
 */

function createBusIcon() {

    return L.divIcon({

        className: '',

        html: `
            <div class="custom-bus-marker">
                🚌
            </div>
        `,

        iconSize: [38, 38],

        iconAnchor: [19, 19],

        popupAnchor: [0, -22]

    });

}


/*
 * ============================================================
 * CONVERSÃO DE DATA
 * ============================================================
 *
 * MySQL normalmente retorna:
 *
 * 2026-09-27 01:25:10
 *
 * O JavaScript precisa transformar em:
 *
 * 2026-09-27T01:25:10
 */

function parseServerDate(value) {

    if (!value) {
        return null;
    }

    if (value instanceof Date) {
        return value;
    }

    let text = String(value).trim();

    /*
     * Se já estiver em formato ISO:
     */
    if (text.includes('T')) {

        const date = new Date(text);

        if (!isNaN(date.getTime())) {
            return date;
        }

    }

    /*
     * MySQL DATETIME:
     */
    text = text.replace(' ', 'T');

    const date = new Date(text);

    if (!isNaN(date.getTime())) {
        return date;
    }

    return null;
}


/*
 * ============================================================
 * TEMPO DECORRIDO
 * ============================================================
 *
 * Exemplos:
 *
 * 0 segundos  -> Agora
 * 12 segundos -> 12 s
 * 75 segundos -> 1 min 15 s
 * 3660 sec    -> 1 h 1 min
 */

function elapsedText(value) {

    const date = parseServerDate(value);

    if (!date) {
        return 'hora desconhecida';
    }

    let seconds = Math.floor(
        (Date.now() - date.getTime()) / 1000
    );

    if (seconds < 0) {
        seconds = 0;
    }


    /*
     * Menos de 10 segundos
     */
    if (seconds < 10) {
        return 'agora';
    }


    /*
     * Segundos
     */
    if (seconds < 60) {

        return (
            seconds +
            ' s'
        );

    }


    /*
     * Minutos
     */
    const minutes = Math.floor(seconds / 60);

    const remainingSeconds = seconds % 60;


    if (minutes < 60) {

        if (remainingSeconds === 0) {

            return (
                minutes +
                (minutes === 1 ? ' min' : ' min')
            );

        }

        return (
            minutes +
            ' min ' +
            remainingSeconds +
            ' s'
        );

    }


    /*
     * Horas
     */

    const hours = Math.floor(minutes / 60);

    const remainingMinutes = minutes % 60;


    if (remainingMinutes === 0) {

        return (
            hours +
            (hours === 1 ? ' h' : ' h')
        );

    }


    return (
        hours +
        ' h ' +
        remainingMinutes +
        ' min'
    );

}


/*
 * ============================================================
 * FORMATAÇÃO DA DATA/HORA
 * ============================================================
 */

function formatDateTime(value) {

    const date = parseServerDate(value);

    if (!date) {
        return 'Data desconhecida';
    }

    return date.toLocaleString(
        'pt-PT',
        {
            day: '2-digit',
            month: '2-digit',
            year: 'numeric',
            hour: '2-digit',
            minute: '2-digit',
            second: '2-digit'
        }
    );

}


/*
 * ============================================================
 * POPUP DA PARAGEM
 * ============================================================
 */

function stopPopupContent(stop) {

    const code = stop.codigo;

    const arrival = lastArrivals[code];

    let arrivalHTML = `
        <div style="
            margin-top:8px;
            padding:8px;
            background:#f5f5f5;
            border-radius:7px;
            color:#777;
        ">
            Nenhuma chegada registada.
        </div>
    `;


    if (arrival) {

        const elapsed = elapsedText(
            arrival.created_at
        );

        arrivalHTML = `
            <div style="
                margin-top:8px;
                padding:9px;
                background:#f5f3fa;
                border-radius:7px;
                color:#291868;
            ">

                <strong>
                    🚌 Última chegada
                </strong>

                <br>

                <span
                    class="popup-elapsed"
                    data-stop-code="${code}"
                >
                    Chegou há ${elapsed}
                </span>

                <br>

                <small style="color:#777;">
                    ${formatDateTime(arrival.created_at)}
                </small>

                <br>

                <small style="color:#777;">
                    Autocarro:
                    ${arrival.bus_code || 'Não identificado'}
                </small>

            </div>
        `;

    }


    const online = stop.online == 1 ||
                   stop.online === true;


    return `

        <div style="
            min-width:210px;
            font-family:Arial, sans-serif;
        ">

            <div style="
                font-size:16px;
                font-weight:700;
                color:#291868;
            ">
                🚏 ${stop.nome}
            </div>

            <div style="
                margin-top:3px;
                color:#777;
                font-size:11px;
            ">
                Av. Eduardo Mondlane
            </div>

            <div style="
                margin-top:8px;
                font-size:12px;
            ">

                <strong>Estado da paragem:</strong>

                <span style="
                    color:${online ? '#16833b' : '#c92a20'};
                    font-weight:700;
                ">
                    ${online ? ' ONLINE' : ' OFFLINE'}
                </span>

            </div>

            ${arrivalHTML}

        </div>

    `;

}


/*
 * ============================================================
 * CRIAR MAPA
 * ============================================================
 *
 * IMPORTANTE:
 * O mapa é criado antes de carregar os dados do servidor.
 * Isso faz com que o utilizador veja o mapa rapidamente.
 */

function initMap() {

    if (map) {
        return;
    }


    map = L.map(
        'map',
        {
            zoomControl: true,
            preferCanvas: true
        }
    );


    /*
     * Centro inicial.
     */

    map.setView(
        [-25.9653, 32.5781],
        16
    );


    /*
     * OpenStreetMap.
     *
     * updateWhenIdle ajuda a reduzir pedidos excessivos.
     */

    L.tileLayer(
        'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
        {
            maxZoom: 19,

            attribution:
                '&copy; OpenStreetMap contributors',

            updateWhenIdle: true,

            keepBuffer: 2,

            updateWhenZooming: false
        }
    ).addTo(map);


    /*
     * Criamos imediatamente as duas paragens usando
     * coordenadas locais de fallback.
     */

    Object.values(STOP_CONFIG).forEach(function(stop) {

        createOrUpdateStopMarker({

            codigo: stop.codigo,

            nome: stop.nome,

            latitude: stop.latitude,

            longitude: stop.longitude,

            online: false

        });

    });


    /*
     * Permite ao Leaflet recalcular correctamente o tamanho
     * depois do container estar visível.
     */

    setTimeout(function() {

        if (map) {
            map.invalidateSize();
        }

    }, 100);


    /*
     * Esconde o indicador de carregamento.
     */

    const loading =
        document.getElementById('mapLoading');

    if (loading) {
        loading.classList.add('hidden');

        setTimeout(function() {
            loading.style.display = 'none';
        }, 350);
    }

}


/*
 * ============================================================
 * CRIAR / ACTUALIZAR MARCADOR DA PARAGEM
 * ============================================================
 */

function createOrUpdateStopMarker(stop) {

    if (!map) {
        return;
    }


    const code = stop.codigo;

    const lat = parseFloat(stop.latitude);

    const lng = parseFloat(stop.longitude);


    if (
        !Number.isFinite(lat) ||
        !Number.isFinite(lng)
    ) {
        return;
    }


    /*
     * Se o marcador ainda não existir:
     */

    if (!stopMarkers[code]) {

        const marker = L.marker(
            [lat, lng],
            {
                icon: createStopIcon(
                    !!lastArrivals[code]
                )
            }
        );


        marker.addTo(map);


        marker.bindPopup(
            stopPopupContent(stop),
            {
                maxWidth: 280
            }
        );


        stopMarkers[code] = marker;

    } else {

        /*
         * Actualiza posição.
         */

        stopMarkers[code].setLatLng(
            [lat, lng]
        );


        /*
         * Actualiza o ícone.
         */

        stopMarkers[code].setIcon(
            createStopIcon(
                !!lastArrivals[code]
            )
        );


        /*
         * Actualiza popup.
         */

        stopMarkers[code].setPopupContent(
            stopPopupContent(stop)
        );

    }

}


/*
 * ============================================================
 * ACTUALIZAR ESTADO DA PARAGEM
 * ============================================================
 */

function updateStopStatus(
    stop,
    arrival = false
) {

    const code = stop.codigo;


    const badge =
        document.getElementById(
            'status-' + code
        );


    const info =
        document.getElementById(
            'info-' + code
        );


    if (!badge) {
        return;
    }


    const online =
        stop.online == 1 ||
        stop.online === true;


    if (online) {

        badge.className =
            'online-badge online';

        badge.textContent =
            'Online';

    } else {

        badge.className =
            'online-badge offline';

        badge.textContent =
            'Offline';

    }


    if (info) {

        let text = online
            ? 'ESP32 da paragem conectado.'
            : 'ESP32 da paragem offline.';

        if (
            stop.ldr_value !== undefined &&
            stop.ldr_value !== null
        ) {

            text +=
                '<br>LDR: ' +
                stop.ldr_value;

        }

        info.innerHTML = text;

    }


    /*
     * Actualiza marcador.
     */

    createOrUpdateStopMarker(stop);


    /*
     * Actualiza o tempo da última chegada.
     */

    updateStopArrivalText(code);

}


/*
 * ============================================================
 * TEXTO DA ÚLTIMA CHEGADA
 * ============================================================
 */

function updateStopArrivalText(code) {

    const element =
        document.getElementById(
            'arrival-' + code
        );


    if (!element) {
        return;
    }


    const arrival =
        lastArrivals[code];


    if (!arrival) {

        element.className =
            'arrival-time no-arrival';

        element.textContent =
            'Nenhuma chegada registada.';

        return;

    }


    element.className =
        'arrival-time';


    element.innerHTML = `
        🚌 Chegada:
        <strong>
            há ${elapsedText(arrival.created_at)}
        </strong>
        <br>
        <span style="
            font-size:10px;
            font-weight:400;
            color:#777;
        ">
            ${formatDateTime(arrival.created_at)}
        </span>
    `;

}


/*
 * ============================================================
 * ACTUALIZAR TODOS OS TEMPOS
 * ============================================================
 *
 * Isto faz com que:
 *
 * "Chegou há 1 min"
 *
 * passe para:
 *
 * "Chegou há 1 min 1 s"
 *
 * etc.
 */

function updateElapsedTimes() {

    Object.keys(lastArrivals).forEach(function(code) {

        updateStopArrivalText(code);

    });


    /*
     * Actualiza também os popups actualmente abertos.
     */

    Object.keys(stopMarkers).forEach(function(code) {

        const marker =
            stopMarkers[code];

        if (
            marker &&
            marker.isPopupOpen()
        ) {

            const popup =
                marker.getPopup();

            if (!popup) {
                return;
            }


            /*
             * Recuperamos a posição e os dados básicos.
             */

            const stop =
                STOP_CONFIG[code];

            if (!stop) {
                return;
            }


            const currentLatLng =
                marker.getLatLng();


            const online =
                marker._stopOnline || false;


            const popupStop = {

                codigo: code,

                nome: stop.nome,

                latitude: currentLatLng.lat,

                longitude: currentLatLng.lng,

                online: online ? 1 : 0

            };


            marker.setPopupContent(
                stopPopupContent(popupStop)
            );

        }

    });

}


/*
 * ============================================================
 * GUARDAR ÚLTIMA CHEGADA
 * ============================================================
 */

function registerArrival(alert) {

    if (!alert) {
        return;
    }


    const code =
        alert.stop_code ||
        alert.codigo;


    if (!code) {
        return;
    }


    lastArrivals[code] = {

        created_at:
            alert.created_at,

        bus_code:
            alert.bus_code || 'Não identificado'

    };


    /*
     * Actualiza o marcador.
     */

    if (stopMarkers[code]) {

        stopMarkers[code].setIcon(
            createStopIcon(true)
        );

    }


    /*
     * Actualiza painel lateral.
     */

    updateStopArrivalText(code);


    /*
     * Se o popup estiver aberto, actualiza imediatamente.
     */

    if (stopMarkers[code]) {

        const popup =
            stopMarkers[code].getPopup();

        if (
            popup &&
            stopMarkers[code].isPopupOpen()
        ) {

            const stop =
                STOP_CONFIG[code];

            if (stop) {

                stopMarkers[code].setPopupContent(
                    stopPopupContent({
                        codigo: code,
                        nome: stop.nome,
                        latitude: stop.latitude,
                        longitude: stop.longitude,
                        online: 1
                    })
                );

            }

        }

    }

}


/*
 * ============================================================
 * ALERTA VISUAL
 * ============================================================
 */

function processArrival(alert) {

    /*
     * Regista a chegada primeiro.
     */

    registerArrival(alert);


    /*
     * Texto da paragem.
     */

    const stopName =
        alert.stop_name ||
        alert.stop_nome ||
        alert.stop_code ||
        'Paragem';


    const message =
        alert.message ||
        'Autocarro detectado na paragem.';


    /*
     * Cria alerta.
     */

    const container =
        document.getElementById(
            'alertContainer'
        );


    if (container) {

        container.innerHTML = `

            <div class="arrival-alert">

                <div class="arrival-alert-title">
                    🚌 Chegada detectada — ${stopName}
                </div>

                <div class="arrival-alert-message">
                    ${message}
                </div>

                <div class="arrival-alert-time">
                    Chegada: ${formatDateTime(alert.created_at)}
                </div>

            </div>

        `;


        /*
         * Remove depois de 10 segundos.
         */

        setTimeout(function() {

            container.innerHTML = '';

        }, 10000);

    }


    /*
     * SOM
     */

    if (soundEnabled) {

        speakArrival(
            `Autocarro chegou à paragem ${stopName}`
        );

    }


    /*
     * Actualiza histórico.
     */

    addHistoryItem(alert);

}


/*
 * ============================================================
 * SOM
 * ============================================================
 */

function speakArrival(text) {

    if (!('speechSynthesis' in window)) {
        return;
    }


    try {

        window.speechSynthesis.cancel();


        const utterance =
            new SpeechSynthesisUtterance(text);


        utterance.lang = 'pt-PT';

        utterance.rate = 0.95;

        utterance.pitch = 1;


        window.speechSynthesis.speak(
            utterance
        );

    } catch (error) {

        console.warn(
            'Erro no som:',
            error
        );

    }

}


/*
 * ============================================================
 * HISTÓRICO
 * ============================================================
 */

function addHistoryItem(alert) {

    const list =
        document.getElementById(
            'historyList'
        );


    if (!list) {
        return;
    }


    const stopName =
        alert.stop_name ||
        alert.stop_code ||
        'Paragem';


    const bus =
        alert.bus_code ||
        'Não identificado';


    const item =
        document.createElement('div');


    item.className =
        'history-item';


    item.innerHTML = `

        <strong>
            🚌 ${stopName}
        </strong>

        <span>
            Autocarro: ${bus}
        </span>

        <span>
            ${formatDateTime(alert.created_at)}
        </span>

    `;


    list.prepend(item);


    /*
     * Mantém somente os últimos 10.
     */

    while (
        list.children.length > 10
    ) {

        list.removeChild(
            list.lastElementChild
        );

    }

}


/*
 * ============================================================
 * ESTADO DO SISTEMA
 * ============================================================
 */

function setSystemStatus(online) {

    const dot =
        document.getElementById(
            'systemStatusDot'
        );

    const text =
        document.getElementById(
            'systemStatusText'
        );


    if (!dot || !text) {
        return;
    }


    if (online) {

        dot.className =
            'status-dot online';

        text.textContent =
            'Sistema online';

    } else {

        dot.className =
            'status-dot offline';

        text.textContent =
            'Sem ligação ao servidor';

    }

}


/*
 * ============================================================
 * CARREGAR ESTADO
 * ============================================================
 */

async function loadState() {

    try {

        const response =
            await fetch(
                API_STATE +
                '?_=' +
                Date.now(),
                {
                    cache: 'no-store'
                }
            );


        if (!response.ok) {
            throw new Error(
                'HTTP ' + response.status
            );
        }


        const data =
            await response.json();


        setSystemStatus(true);


        /*
         * PARAGENS
         */

        if (
            Array.isArray(data.stops)
        ) {

            data.stops.forEach(function(stop) {

                /*
                 * Guarda estado para utilização no popup.
                 */

                if (
                    stop.codigo &&
                    stop.online !== undefined
                ) {

                    if (stopMarkers[stop.codigo]) {

                        stopMarkers[
                            stop.codigo
                        ]._stopOnline =
                            stop.online == 1 ||
                            stop.online === true;

                    }

                }


                updateStopStatus(
                    stop
                );

            });

        }


        /*
         * AUTOCARROS
         */

        if (
            Array.isArray(data.buses)
        ) {

            data.buses.forEach(function(bus) {

                updateBusMarker(bus);

            });

        }


        /*
         * ALERTAS
         */

        if (
            Array.isArray(data.alerts)
        ) {

            data.alerts.forEach(function(alert) {

                /*
                 * Guarda o último ID.
                 */

                const id =
                    parseInt(
                        alert.id || 0,
                        10
                    );


                if (id > lastAlertId) {
                    lastAlertId = id;
                }


                /*
                 * Guarda última chegada.
                 *
                 * Não chamamos processArrival()
                 * para os alertas antigos, pois isso
                 * causaria som novamente.
                 */

                registerArrival(
                    alert
                );

            });


            /*
             * Histórico inicial.
             */

            const list =
                document.getElementById(
                    'historyList'
                );


            if (list) {

                list.innerHTML = '';

                data.alerts
                    .slice()
                    .reverse()
                    .slice(0, 10)
                    .forEach(function(alert) {

                        addHistoryItem(alert);

                    });

            }

        }

    } catch (error) {

        console.error(
            'Erro ao carregar estado:',
            error
        );


        setSystemStatus(false);

    }

}


/*
 * ============================================================
 * MARCADOR DO AUTOCARRO
 * ============================================================
 */

function updateBusMarker(bus) {

    if (!map) {
        return;
    }


    const lat =
        parseFloat(bus.latitude);

    const lng =
        parseFloat(bus.longitude);


    if (
        !Number.isFinite(lat) ||
        !Number.isFinite(lng)
    ) {
        return;
    }


    const code =
        bus.codigo ||
        bus.bus_code ||
        'BUS';


    if (!busMarkers[code]) {

        const marker =
            L.marker(
                [lat, lng],
                {
                    icon: createBusIcon()
                }
            ).addTo(map);


        marker.bindPopup(`

            <strong>
                🚌 ${code}
            </strong>

            <br>

            GPS:
            ${bus.gps_fix ? 'OK' : 'Sem fix'}

        `);


        busMarkers[code] =
            marker;

    } else {

        busMarkers[code].setLatLng(
            [lat, lng]
        );

    }

}


/*
 * ============================================================
 * SERVER-SENT EVENTS
 * ============================================================
 */

function connectEvents() {

    /*
     * Fecha ligação anterior.
     */

    if (eventSource) {

        try {
            eventSource.close();
        } catch (e) {}

    }


    const url =
        API_EVENTS +
        '?last_id=' +
        encodeURIComponent(
            lastAlertId
        );


    try {

        eventSource =
            new EventSource(url);


        /*
         * ALERTA DE CHEGADA
         */

        eventSource.addEventListener(
            'arrival',
            function(event) {

                try {

                    const alert =
                        JSON.parse(
                            event.data
                        );


                    const id =
                        parseInt(
                            alert.id || 0,
                            10
                        );


                    /*
                     * Evita duplicados.
                     */

                    if (
                        id > 0 &&
                        id <= lastAlertId
                    ) {

                        return;

                    }


                    if (
                        id > lastAlertId
                    ) {

                        lastAlertId = id;

                    }


                    processArrival(
                        alert
                    );


                    /*
                     * Actualiza o estado visual
                     * da paragem.
                     */

                    const code =
                        alert.stop_code;


                    if (
                        code &&
                        stopMarkers[code]
                    ) {

                        stopMarkers[code].setIcon(
                            createStopIcon(true)
                        );

                    }

                } catch (error) {

                    console.error(
                        'Erro ao processar alerta:',
                        error
                    );

                }

            }
        );


        /*
         * ABERTURA DA LIGAÇÃO
         */

        eventSource.onopen =
            function() {

                setSystemStatus(true);

            };


        /*
         * ERRO
         */

        eventSource.onerror =
            function() {

                console.warn(
                    'Ligação SSE interrompida.'
                );

                /*
                 * EventSource tenta automaticamente
                 * restabelecer a ligação.
                 */

            };

    } catch (error) {

        console.error(
            'Erro SSE:',
            error
        );

    }

}


/*
 * ============================================================
 * BOTÃO DE SOM
 * ============================================================
 */

function setupSoundButton() {

    const button =
        document.getElementById(
            'soundButton'
        );


    if (!button) {
        return;
    }


    button.addEventListener(
        'click',
        function() {

            soundEnabled =
                !soundEnabled;


            button.textContent =
                soundEnabled
                    ? '🔊'
                    : '🔇';


            button.title =
                soundEnabled
                    ? 'Desactivar som'
                    : 'Activar som';


            /*
             * Alguns browsers só permitem
             * speechSynthesis depois de uma
             * interacção do utilizador.
             */

            if (soundEnabled) {

                speakArrival(
                    'Som activado'
                );

            }

        }
    );

}


/*
 * ============================================================
 * INICIALIZAÇÃO
 * ============================================================
 */

async function init() {

    /*
     * 1. Carrega Leaflet.
     */

    try {

        await loadLeaflet();

    } catch (error) {

        console.error(error);

        const loading =
            document.getElementById(
                'mapLoading'
            );

        if (loading) {

            loading.textContent =
                'Erro ao carregar o mapa.';

        }

        return;

    }


    /*
     * 2. Inicializa o mapa imediatamente.
     */

    initMap();


    /*
     * 3. Som.
     */

    setupSoundButton();


    /*
     * 4. Carrega estado imediatamente.
     */

    loadState();


    /*
     * 5. Liga SSE imediatamente.
     */

    connectEvents();


    /*
     * 6. Actualiza estado a cada 5 segundos.
     *
     * O mapa NÃO é recriado.
     */

    setInterval(
        loadState,
        5000
    );


    /*
     * 7. Actualiza o contador de tempo
     * das chegadas a cada segundo.
     */

    setInterval(
        updateElapsedTimes,
        1000
    );

}


/*
 * Iniciar.
 */

init();

</script>

</body>
</html>