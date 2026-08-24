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

**`MaxConnections=2`.** Každá instance si nahraje vlastní kopii sítě do VRAM.
Na 8GB kartě se víc než dvě souběžné partie nevejdou. Stockfish tenhle strop
nemá, protože RAM je 46 GB.

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

## Když je desktop vypnutý

NAS běží pořád, desktop ne. Syn ho probudí přes `desktop-on-off.skybit.cz`
(WoL), počká ~minutu a teprve pak spustí engine. Platí pro oba enginy stejně.

## Související

- `lc0-amd-setup.md` — build lc0 s ROCm akcelerací (bez toho port 3457 nemá co obsluhovat)
- `optional/chess-relay/` — unit files, relay skripty a `setup.sh`
- `fspi-server` repo — NAS strana, SSH klíč, `docs/chess-remote-engine.md`
