# Vzdálené šachové enginy — desktopová strana (Stockfish + Lc0)

Desktop (`192.168.1.10`) vystavuje šachové enginy po TCP, aby se na ně dalo
připojit ze slabšího notebooku přes NAS. Tenhle dokument popisuje **jen
desktopovou půlku**; celý řetězec (ChessBase → plink → NAS → desktop) je
popsaný v repu `fspi-server`:

> <https://github.com/bardolf/fspi-server/blob/master/docs/chess-remote-engine.md>
> a serverový krok `steps/28_chess_relay.sh` + `config/chess/jachym.authorized_keys`.

Nasazuje `optional/chess-relay/setup.sh` (není součástí `install.sh`).

## Přehled

| Engine | Port | Výpočet | Služba |
| --- | --- | --- | --- |
| Stockfish 18 | 3456 | CPU (22 vláken, 8 GB hash) | `stockfish.socket` + `stockfish@.service` |
| Lc0 v0.33 | 3457 | GPU (Radeon RX 6600 XT přes ROCm) | `lc0.socket` + `lc0@.service` |

Obojí přes **systemd socket-activation**: na Fedoře je `xinetd` mrtvý, tohle je
čistá náhrada. `Accept=yes` znamená, že každé TCP spojení dostane **vlastní
instanci** enginu se `stdin`/`stdout` napojeným rovnou na socket. UCI je prostý
textový protokol, takže se nic nepřekládá — jen protahuje rourou.

Dokud se nikdo nepřipojí, neběží nic.

## Firewall

Porty naslouchají na všech rozhraních, ale firewalld je pouští **jen z NASu**
(`192.168.1.11`). Ne plošným `--add-port`, ale rich rule vázanou na zdrojovou
adresu:

```bash
sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="192.168.1.11" port port="3456" protocol="tcp" accept'
sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="192.168.1.11" port port="3457" protocol="tcp" accept'
sudo firewall-cmd --reload
```

Kontrola: `sudo firewall-cmd --list-rich-rules`

## Vynucení parametrů na serveru

Obě služby volají wrapper v `/usr/local/bin/`, ne engine přímo. Důvod je
u Stockfishe zásadní: **ChessBase ořezává `Threads` na počet jader notebooku**,
takže bez wrapperu by se výkon desktopu vůbec nevyužil. Wrapper proto natvrdo
nastaví hodnoty a **zahodí, co pošle klient**.

`stockfish-relay` injektuje `setoption` na začátek vstupu a filtruje klientské
`Threads`/`Hash`. `lc0-relay` má to jednodušší — lc0 umí všechny volby vzít
z příkazové řádky, takže se nic neinjektuje a filtr jen zahazuje.

U lc0 filtr navíc pokrývá volby, které berou **cestu do souborového systému**
(`WeightsFile`, `ConfigFile`, `LogFile`, `SyzygyPath`) a `Backend`. Služba je
dostupná po síti a bez toho by klient mohl přimět engine číst nebo zapisovat
kamkoli.

## Rozdíly Lc0 proti Stockfishi

Tři věci, ve kterých se lc0 záměrně odchyluje od zavedeného vzoru:

**Neběží jako root.** `lc0@.service` má `User=milan`. Root nepotřebuje —
GPU zařízení (`/dev/kfd`, `/dev/dri/renderD128`) mají na Fedoře 44 práva `0666`.
Kdyby ROCm někdy práva zpřísnil, je potřeba přidat uživatele do skupiny
`render`. (`stockfish@.service` root zdědil historicky; klidně by mohl taky
běžet neprivilegovaně.)

**`MaxConnections=6`.** Aktivně hledající instance si nahraje vlastní kopii
sítě do VRAM, takže víc než ~2 souběžné *partie* se na 8GB kartu nevejdou —
nečinná instance ale drží jen ~12 MB. Původní strop 2 se ukázal jako
nebezpečný: stačily dva mrtvé spoje a socket přestal přijímat úplně (viz
„Engine error" níže). Stockfish žádný strop nemá, protože RAM je 46 GB.

**Pomalý první tah.** Než lc0 vrátí první `bestmove`, staví ONNX graf a
kompiluje ROCm kernely — desítky sekund. `uci` a `isready` odpoví hned, takže
GUI se připojí normálně a čeká se až na `go`. Není to zamrznutí.

## Serverová strana (NAS) — hotovo

Engine se volí **uživatelským jménem**, ne portem. Syn cílový port nezná ani nezadává:

| SSH uživatel | → | Desktop |
| --- | --- | --- |
| `jachym` | | `192.168.1.10:3456` Stockfish |
| `jachym-lc0` | | `192.168.1.10:3457` Lc0 |

Oba uživatelé na NASu mají **týž veřejný klíč** a liší se jen forced commandem
v `authorized_keys`, který spustí `nc` na příslušný port. Nasazeno v repu
`fspi-server` (`config/chess/jachym-lc0.authorized_keys`, `steps/28_chess_relay.sh`);
na NASu stačí spustit `bash steps/28_chess_relay.sh`.

Na notebooku pak druhá kopie `inbetween.exe` s vlastním `.ini`, kde se v plink
řádku mění **jen uživatel**:

```
plink.exe -no-antispoof -ssh -C -P 22 -i C:\…\jachym-private-key.ppk jachym-lc0@skybit.cz
```

V ChessBase se přidá jako druhý UCI engine vedle Stockfishe.

### Pozor na starší popis řetězce

Dokumentace v `fspi-server` dříve tvrdila, že klient používá `plink -nc` a cíl
si volí sám (server ho jen povoluje přes `permitopen`). **Není to tak.**
V `journalctl` na NASu u synových připojení vzniká PAM session — jedna běžela
45 minut, tedy partie — a direct-tcpip kanál z `-nc` žádnou PAM session
nezakládá. Provoz tedy jde přes **forced command**; `permitopen` je nepoužitá
záložní větev pro případ, že by někdo `-nc` použil. Opraveno 2026-08-24.

## Ověření

```bash
# Naslouchá obojí?
ss -tlnp | grep -E '3456|3457'

# Lokální self-test (musí vrátit 'id name … uciok')
printf 'uci\nquit\n' | nc 127.0.0.1 3456      # → id name Stockfish 18
printf 'uci\nquit\n' | nc 127.0.0.1 3457      # → id name Lc0 v0.33.0-dev

# Z NASu (desktop musí běžet)
printf 'uci\nquit\n' | nc 192.168.1.10 3457

# Logy instancí
journalctl -u 'stockfish@*' -u 'lc0@*' -n 50
```

U testu, který má vrátit `bestmove`, musí být mezi `go` a `quit` prodleva —
jinak engine skončí dřív, než něco spočítá:

```bash
{ printf 'uci\nisready\nposition startpos moves e2e4 c7c5\ngo nodes 300\n'; \
  sleep 180; printf 'quit\n'; } | nc 127.0.0.1 3457
```

## „Engine error" v ChessBase — vyčerpané spojení

**Toto je porucha, na kterou dojde znovu, když se něco pokazí.** Příznak:
ChessBase při volbě Lc0 hlásí `engine error`, ruční test plinkem nic nevrátí,
ale lokální `nc 127.0.0.1 3457` na desktopu funguje.

Řetěz příčin:

1. Synovi zmizí klient (spadlý ChessBase, zavřený plink, přerušená síť).
2. **sshd na NASu má `ClientAliveInterval` ve výchozím stavu 0**, takže si toho
   nikdy nevšimne. Session žije dál — i bez jediného TCP spojení na port 22.
3. S ní žije forced command `nc`, takže TCP na desktop zůstává `ESTAB` a
   instance enginu nikdy nedostane EOF. (Lc0 ani Stockfish za to nemůžou —
   oba se na EOF korektně ukončí, jen ten EOF nepřijde.)
4. Nasčítané mrtvé instance vyčerpají `MaxConnections` na `lc0.socket`. Socket
   přestane přijímat, `nc` dostane odmítnuté spojení, stream se okamžitě zavře
   → **ChessBase to ohlásí jako chybu enginu.**

Stockfish tím netrpěl jen proto, že `stockfish.socket` žádný strop nemá —
mrtvé instance mu žraly RAM (a s `Hash=8192` to není málo), ale provoz
neblokovaly.

### Opraveno

- **NAS:** `config/ssh/sshd_config.d/20-chess-relay.conf` v repu `fspi-server`
  posílá relay uživatelům keepalive a po ~2 minutách bez odpovědi session
  ukončí (30 s × 4). Globální nastavení zůstává nedotčené — ověř přes
  `sudo sshd -T -C user=jachym-lc0,host=x,addr=1.2.3.4 | grep clientalive`.
- **Desktop:** `MaxConnections` zvednuto z 2 na 6, aby jeden mrtvý spoj
  neznamenal výpadek. Není to náhrada za keepalive, jen rezerva.

### Diagnostika, kdyby se to vrátilo

```bash
# Desktop — obsazené sloty a stav spojení
systemctl list-units 'lc0@*' --all
ss -tnp | grep 3457                    # ESTAB bez provozu = mrtvý spoj
systemctl show lc0.socket -p MaxConnections

# NAS — visící session a nc procesy
ssh server 'ps -eo etime,user,args | grep "[n]c 192.168.1.10"'
ssh server 'ss -tnp | grep sshd-session | grep ":22 "'   # prázdné = klient je pryč

# Okamžitá náprava (uvolní sloty)
ssh server 'sudo pkill -u jachym-lc0 -f sshd-session'
```

## Lc0 se při ručním testu nehlásí — a je to správně

Při připojení plinkem se Stockfish ohlásí sám, Lc0 mlčí:

```
$ plink … jachym@skybit.cz
Server refused to allocate pty
Stockfish 18 by the Stockfish developers (see AUTHORS file)     ← banner přišel
info string Using 22 threads

$ plink … jachym-lc0@skybit.cz
Server refused to allocate pty
                                                                ← nic
```

Vypadá to, že Lc0 nenaběhl. Naběhl. **Stockfish píše banner na stdout, Lc0 na
stderr** — a `lc0@.service` má `StandardError=journal`, takže logo skončí
v journalu, ne v socketu. Na stdout Lc0 neřekne nic, dokud nedostane příkaz.

Napiš `uci` a Enter → `id name Lc0 v0.33.0-dev … uciok`.

Že instance skutečně běžela, se ověří na desktopu:

```bash
sudo journalctl -b | grep lc0-relay
# Started lc0@2-8193-192.168.1.10:3457-192.168.1.11:33150.service
# lc0-relay[14174]: |_ |_ |_| v0.33.0-dev+git.d8ce482        ← banner ze stderr
```

Zdrojová adresa v názvu instance (`192.168.1.11`) potvrzuje, že spojení přišlo
z NASu, tedy celým řetězcem.

**Pro ChessBase to nehraje roli** — `inbetween.exe` pošle `uci` hned po startu.
Kdyby se ale ukázalo, že nějaká klientská vrstva čeká na výstup už při startu
a bez něj se zasekne, řešení je přidat do `lc0-relay` echo jednoho řádku na
stdout před spuštěním enginu. Zatím není potřeba a UCI stream je čistší bez
toho.

Ono „Server refused to allocate pty" je u obou enginů v pořádku — dělá to
`no-pty` v `authorized_keys` záměrně.

## Když je desktop vypnutý

NAS běží pořád, desktop ne. Syn ho probudí přes `desktop-on-off.skybit.cz`
(WoL), počká ~minutu a teprve pak spustí engine. Platí pro oba enginy stejně.

## Související

- `lc0-amd-setup.md` — build lc0 s ROCm akcelerací (bez toho port 3457 nemá co obsluhovat)
- `optional/chess-relay/` — unit files, relay skripty a `setup.sh`
- `fspi-server` repo — NAS strana, SSH klíč, `docs/chess-remote-engine.md`
