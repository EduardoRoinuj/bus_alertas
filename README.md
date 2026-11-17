# Bus Alertas — Detecção de chegada de autocarros

```
ESP32 autocarro (GPS + LED) ──HTTPS──┐
ESP32 paragem Ronil (LDR)  ──HTTPS──┼──►  Servidor Python (Flask) no Render (grátis)
ESP32 paragem Pandora (LDR) ─HTTPS──┘        │  estado ao vivo em memória
                                             │  chegadas gravadas no Postgres (Neon, grátis)
                                             ▼
                       Painel web (PWA)   +   App Android (Flutter)
```

O servidor fica num **endereço fixo** (`https://bus-alertas.onrender.com`).
Os ESP32 apontam para esse endereço, por isso **nunca mais é preciso voltar a gravar o código
quando o IP do computador muda**.

| Pasta | Conteúdo |
|---|---|
| `server/` | Servidor Flask + painel web (HTML/CSS/JS, Leaflet, Font Awesome) |
| `android_app/` | App Android (Flutter) — mapa, paragens, histórico, notificações e voz |
| `esp32_autocarro/` | Firmware do autocarro (HTTPS, envio numa tarefa separada) |
| `esp32_paragem/`, `esp32_paragem_pandora/` | Firmware das paragens (igual, só muda `STOP_CODE`) |
| `index.php`, `api/`, `config/`, `sql/` | Versão antiga em PHP (já não é usada; pode apagar) |

---

## 1. Testar no computador

```bash
cd server
pip install -r requirements.txt
python app.py
```
Abra http://localhost:5000. Sem `DATABASE_URL` usa SQLite local (`bus_alertas.db`).

Para ver o painel a mexer sem hardware, noutro terminal:
```bash
python simulate.py
```

---

## 2. Publicar grátis (uma vez só)

### 2.1 Base de dados — Neon (Postgres grátis, não expira)
1. Crie conta em https://neon.tech → **New project** (região *Frankfurt*).
2. Copie a **connection string** (`postgresql://...neon.tech/neondb?sslmode=require`).

> O servidor só escreve na base de dados quando há uma **chegada**.
> A telemetria de 2 em 2 s fica em memória, por isso o plano grátis chega e sobra.

### 2.2 Código no GitHub
1. Crie um repositório **privado** no GitHub (ex.: `bus_alertas`).
2. Envie esta pasta. O `.gitignore` já exclui o firmware (que tem a password do Wi-Fi e o token).
   ```bash
   git init
   git add .
   git commit -m "Bus Alertas em Python"
   git branch -M main
   git remote add origin https://github.com/<seu-utilizador>/bus_alertas.git
   git push -u origin main
   ```

### 2.3 Servidor — Render (web service grátis)
1. Crie conta em https://render.com (entre com o GitHub).
2. **New → Blueprint** → escolha o repositório. O `render.yaml` configura tudo.
3. Quando pedir as variáveis:
   - `API_TOKEN` = o valor de `API_TOKEN` que está nos `.ino` (têm de ser iguais)
   - `DATABASE_URL` = a connection string do Neon
4. Depois do deploy, o endereço será `https://bus-alertas.onrender.com`.
   - Se o nome `bus-alertas` já estiver ocupado, o Render dá outro (ex.: `bus-alertas-x1y2.onrender.com`).
     Nesse caso altere `SERVER_URL` nos 3 `.ino` e o servidor na app (ícone ⚙).

> **Plano grátis do Render:** o serviço "adormece" após 15 min sem pedidos e demora ~50 s a acordar.
> Com os ESP32 ligados (enviam a cada 2 s) ele nunca adormece. Se quiser mantê-lo acordado mesmo
> com tudo desligado, crie um monitor grátis em https://uptimerobot.com para `https://.../health` a cada 5 min.

### 2.4 Gravar os ESP32 (última vez!)
No Arduino IDE abra cada `.ino`, confirme `SERVER_URL` e `API_TOKEN` e grave:
- `esp32_autocarro/esp32_autocarro.ino`
- `esp32_paragem/esp32_paragem.ino` (`STOP_CODE = "RONIL"`)
- `esp32_paragem_pandora/esp32_paragem_pandora.ino` (`STOP_CODE = "PANDORA"`)

No Serial Monitor (115200) deve ver `HTTP 200`.

---

## 3. App Android

APK pronto: `android_app/build/app/outputs/flutter-apk/app-release.apk` → copie para o telemóvel e instale
(permita "instalar apps de fontes desconhecidas").

Para recompilar:
```bash
cd android_app
flutter build apk --release
```

Funcionalidades: mapa escuro com autocarro animado, estado das paragens (LDR, distância, última chegada),
histórico, **notificação do sistema + voz em português + vibração** quando o autocarro chega,
e ⚙ para mudar o endereço do servidor sem recompilar.

O painel web também pode ser "instalado" no telemóvel (Chrome → *Adicionar ao ecrã principal*).

---

## API

| Método | Rota | Quem usa |
|---|---|---|
| `POST` | `/api/telemetry` | ESP32 do autocarro (`X-API-Token`) |
| `POST` | `/api/stop` | ESP32 das paragens (`X-API-Token`) |
| `GET` | `/api/state?since=<id>` | Painel web e app (devolve estado + alertas novos) |
| `GET` | `/health` | Monitorização |

As rotas antigas `.php` continuam a funcionar (compatibilidade).

## Calibração do LDR
Abra o Serial Monitor e observe o valor do LDR com a luz normal e com o LED do autocarro a incidir.
Ajuste `SIGNAL_THRESHOLD`. A detecção exige o padrão ON-OFF-ON-OFF longo completo e tem *cooldown* de 20 s;
o servidor também ignora chegadas repetidas na mesma paragem durante 20 s.

## Nota sobre Pandora
A coordenada de Pandora é uma referência próxima da Av. Eduardo Mondlane. Substitua pela coordenada GPS
exacta da paragem em `server/app.py` (`STOPS`).
