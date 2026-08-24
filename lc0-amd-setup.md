# Lc0 (Leela Chess Zero) na AMD Radeon — Fedora Sway

Postup zprovoznění šachového enginu **lc0** s GPU akcelerací na AMD kartě.
Ověřeno na Radeonu RX 6600 XT (Navi 23, **gfx1032**) na Fedoře 44,
lc0 `v0.33.0-dev+git.d8ce482`, 24. 8. 2026.

Není součástí `install.sh` — je to jednorázová věc mimo hlavní pipeline.

## Shrnutí pro netrpělivé

Dvě věci, které nejsou nikde pořádně napsané a stojí za nimi celé odpoledne:

1. **OpenCL backend v lc0 je pro moderní sítě mrtvý.** Nespustí ani jednu
   dnešní síť. Nepoužívej ho, i když se to jako první nabízí.
2. **`HSA_OVERRIDE_GFX_VERSION=10.3.0` je povinný**, jinak backend spadne
   (core dump). Consumer RDNA2 karty nemají v ROCm předkompilované kernely.

Funkční kombinace je **`onnx-rocm`** backend nad Fedorou balíčkovaným
`onnxruntime-rocm`.

## Hardware a rozpoznání

```bash
lspci -nn | grep -i vga        # → Navi 23 [Radeon RX 6600/6600 XT/6600M] [1002:73ff]
```

| Karta | Architektura | gfx target | ROCm oficiálně |
| --- | --- | --- | --- |
| RX 6600 / 6600 XT | Navi 23 (RDNA2) | `gfx1032` | ne |
| RX 6800 / 6900 | Navi 21 (RDNA2) | `gfx1030` | ano |

Právě ten rozdíl vynucuje override níže. Na Navi 21 (gfx1030) by nebyl potřeba.

## Slepá ulička: OpenCL backend

Vypadá to jako zjevná volba pro AMD a je dobře zdokumentovaná po internetu.
Nefunguje. Lc0 zkompiluje `-Dopencl=true` bez problému, OpenCL runtime kartu
korektně vidí, ale při načtení sítě skončí na:

```
Network format NETWORK_ATTENTIONBODY_WITH_HEADFORMAT is not supported by OpenCL backend.
```

Po výměně za starší reziduální síť (T79, `NETWORK_SE_WITH_HEADFORMAT`) narazí
hned na další zeď:

```
Policy format POLICY_ATTENTION is not supported by OpenCL backend.
```

Attention policy má **každá** síť zhruba od T74 dál, takže by bylo nutné jít
na roky staré sítě. OpenCL backend nikdo neudržuje. Přeskoč to.

## Balíčky

### Povinné

```bash
sudo dnf install -y onnxruntime-rocm-devel gcc-c++ meson ninja-build git
```

`onnxruntime-rocm-devel` si přitáhne celý ROCm stack — `miopen` (446 MB),
`rocm-hip`, `rocm-runtime`, `roctracer` a samotné `onnxruntime-rocm` (2,3 GB).
Počítej řádově s **3 GB**.

### Nepovinné (diagnostika, pro lc0 netřeba)

```bash
sudo dnf install -y clinfo rocm-smi rocminfo
```

### Past: dva ICD loadery

Pokud bys sahal po OpenCL (viz slepá ulička výše), `ocl-icd-devel` koliduje
s `OpenCL-ICD-Loader`, který Fedora instaluje jako výchozí:

```
installed package OpenCL-ICD-Loader ... conflicts with ocl-icd provided by ocl-icd-2.3.4
```

Neřeš to přes `--allowerasing`. Správně je použít devel balíček toho loaderu,
který už v systému je: **`OpenCL-ICD-Loader-devel`**.

### Ověřené verze (Fedora 44)

```
onnxruntime-rocm      1.22.2-2.fc44
miopen                7.1.0-6.fc44
rocm-hip-devel        7.1.1-3.fc44
rocm-runtime          7.1.1-6.fc44
gcc-c++               16.2.1-2.fc44
meson                 1.11.2-1.fc44
ninja-build           1.13.2-2.fc44
```

## Přístup ke GPU

ROCm potřebuje `/dev/kfd` a `/dev/dri/renderD128`. Na Fedoře 44 mají obojí
`crw-rw-rw-`, takže **členství ve skupině `render`/`video` není potřeba**:

```bash
ls -l /dev/kfd /dev/dri/renderD128
```

Na jiné distribuci (nebo kdyby Fedora práva zpřísnila) to bývá `crw-rw----`
`root:render` a pak je nutné:

```bash
sudo usermod -aG render,video "$USER"   # a odhlásit/přihlásit
```

## Build lc0

`lc0` není v žádném repozitáři (ani RPM Fusion), musí se ze zdrojů.

```bash
mkdir -p ~/opt && cd ~/opt
git clone --recurse-submodules --depth 1 https://github.com/LeelaChessZero/lc0.git
cd lc0

meson setup build/rocm --buildtype=release -Donnx=true \
  -Donnx_libdir=/usr/lib64/rocm/lib \
  -Donnx_include=/usr/lib64/rocm/include/onnxruntime

ninja -C build/rocm
```

Fedora dává onnxruntime-rocm do **`/usr/lib64/rocm/`**, ne do systémových
adresářů — lc0 by ho jinak nenašel (výchozí hodnoty jsou `/usr/lib/`
a `/usr/include/onnxruntime/`). Meson si sám stáhne subprojekty
(abseil-cpp, eigen, gtest), takže build potřebuje síť.

Ověření, že se ONNX opravdu zalinkoval:

```bash
ldd build/rocm/lc0 | grep onnx
# → libonnxruntime.so.1 => /usr/lib64/rocm/lib/libonnxruntime.so.1
```

Backendy, které z toho vzejdou:

```
onnx-rocm  onnx-cpu  onnx-cuda  onnx-trt  onnx-coreml
eigen  trivial  random  check  roundrobin  recordreplay  multiplexing  demux
```

`onnx-migraphx` se do buildu **nedostane**, i když `migraphx` balíček ve
Fedoře existuje a lc0 ho v kódu podporuje. Nezkoumal jsem proč — `onnx-rocm`
funguje, tak jsem to nechal být.

## Síť s váhami

Bez sítě engine nenaběhne. Sítě jsou na <https://storage.lczero.org/files/>.

```bash
mkdir -p ~/opt/lc0/networks && cd ~/opt/lc0/networks
NET=768x15x24h-t82-swa-11264000.pb.gz
curl -sSL -C - -o "$NET" "https://storage.lczero.org/files/$NET"
```

Pozor na `curl -#` v pipe — progress bar způsobí SIGPIPE a stahování se
utne v půlce. Buď `-s`, nebo bez pipe.

Kontrola architektury sítě před použitím:

```bash
~/opt/lc0/build/rocm/lc0 describenet --weights=.../sit.pb.gz
```

## Výkon — a jedno překvapení

Měřeno `lc0 benchmark --nodes=20000` na RX 6600 XT:

| Síť | Architektura | Velikost | Backend | nps |
| --- | --- | --- | --- | --- |
| BT4 1024x15x32h | transformer, embedding 1024 | 365 MB | `onnx-rocm` | 728 |
| **768x15x24h-t82** | transformer, embedding 768 | 163 MB | `onnx-rocm` | **1453** |
| 512x15-t79_9 | SE-ResNet | 114 MB | `onnx-rocm` | 407 |
| 768x15x24h-t82 | transformer | 163 MB | `onnx-cpu` | 6 |

Dvě věci, které stojí za pozornost:

**Transformer je rychlejší než starší reziduální síť.** T82 je 3,5× rychlejší
než menší T79, přestože má víc parametrů. ONNX Runtime má maticové operace
transformerů mnohem lépe optimalizované než konvoluce se SE bloky. Nesnaž se
tedy „ušetřit" starší sítí — bude pomalejší i slabší.

**BT4 stojí jen 2× nodů.** Na 2,2× větší síť je to malá daň, protože GPU je
u těchhle rozměrů limitované spíš propustností paměti než výpočtem. Když je
absolutní počet nodů takhle nízký (stovky až tisíce), rozhoduje o síle hry
hlavně kvalita sítě, ne hloubka stromu — zdvojnásobení nodů odpovídá zhruba
+50 až 60 Elo, což je míň, než kolik dělá rozdíl mezi generacemi sítí. Na
tomhle hardwaru je proto **BT4 pravděpodobně silnější volba než T82**, navzdory
polovičnímu nps. (Neověřeno zápasem — je to úvaha z naměřeného nps, ne měření
síly hry.)

GPU proti CPU vychází zhruba **240×**, takže akcelerace rozhodně stojí za tu
námahu s ROCm.

## Wrapper a konfigurace

`~/opt/lc0/lc0.config`:

```
--weights=/home/milan/opt/lc0/networks/768x15x24h-t82-swa-11264000.pb.gz
--backend=onnx-rocm
```

`~/.local/bin/lc0` (spustitelný, `~/.local/bin` je v PATH):

```bash
#!/usr/bin/env bash
export HSA_OVERRIDE_GFX_VERSION=10.3.0
exec /home/milan/opt/lc0/build/rocm/lc0 --config=/home/milan/opt/lc0/lc0.config "$@"
```

Ten export je jádro celé věci — proto wrapper existuje. Šachová GUI (CuteChess,
Arena, Scid) se na engine odkazují právě na `~/.local/bin/lc0` a env proměnnou
by jinak nenastavila.

Cesty jsou absolutní a s natvrdo zadaným `/home/milan` — **na jiném stroji je
přepiš.**

## Ověření

```bash
# 1. Vidí ROCm kartu?
clinfo | grep -E "Device Name|Board Name"        # → gfx1032, AMD Radeon RX 6600 XT

# 2. Běží backend?
HSA_OVERRIDE_GFX_VERSION=10.3.0 ~/opt/lc0/build/rocm/lc0 benchmark \
  --backend=onnx-rocm --weights=<sit> --nodes=20000

# 3. Mluví UCI? (GUI ho takhle řídí)
{ printf 'uci\nisready\nposition startpos moves e2e4 e7e5\ngo nodes 500\n'; sleep 120; \
  printf 'quit\n'; } | lc0 | grep -E "id name|bestmove"
# → id name Lc0 v0.33.0-dev...
# → bestmove g1f3 ponder b8c6
```

U testu UCI musí být ta prodleva před `quit`. Když `quit` přijde hned za `go`,
engine skončí dřív, než něco spočítá, a `bestmove` nikdy nepřijde — vypadá to
jako chyba, ale je to jen chybně vedený test.

## Řešení potíží

### Core dump hned po načtení sítě

Chybí `HSA_OVERRIDE_GFX_VERSION=10.3.0`. Typický průběh: síť se načte,
onnxruntime vypíše varování o přiřazení uzlů k execution providerům a proces
spadne. Na gfx1030/gfx1100 (oficiálně podporované) se to neděje.

### `Network format ... is not supported by OpenCL backend`

Používáš OpenCL backend. Přejdi na `onnx-rocm` (viz výše).

### Varování `Some nodes were not assigned to the preferred execution providers`

Neškodné. ONNX Runtime nechává některé operace (typicky práci s tvary) na CPU
záměrně. Objevuje se při každém spuštění.

### Dlouhý start

První inference po spuštění trvá desítky sekund — staví se ONNX graf
a kompilují ROCm kernely. Není to zamrznutí. GUI na to nechej čas.

## Poznámky k replikaci

- Cesty v `lc0.config` a wrapperu jsou absolutní → přepsat.
- `HSA_OVERRIDE_GFX_VERSION` se řídí **cílovou** kartou:
  gfx1032/gfx1031 → `10.3.0`; na gfx1030 a gfx110x se dá vynechat.
  Aktuální target zjistíš přes `clinfo | grep "Device Name"`.
- Instalace zabere ~3 GB balíčků + ~520 MB v `~/opt/lc0` (z toho ~280 MB sítě).
- ROCm stack se při aktualizacích Fedory občas rozbije. Kdyby lc0 po
  aktualizaci spadl, zkus přestavět: `ninja -C ~/opt/lc0/build/rocm`.

## Odkazy

- Lc0: <https://github.com/LeelaChessZero/lc0>
- Sítě: <https://storage.lczero.org/files/>
- Backendy v lc0: <https://github.com/LeelaChessZero/lc0/wiki/Backends>
- HSA_OVERRIDE_GFX_VERSION: <https://github.com/ROCm/ROCm/issues/1743>
