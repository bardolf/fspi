# Autodesk Fusion pod Wine na Sway — neúspěšný pokus

Zkoušeno 26. 11. 2026: Fedora 44 Sway, Ryzen 7 8700G jen s integrovanou
Radeon 780M (RADV / radeonsi), monitor 3840×2160 se scale 1.3, Wine 11.21
Staging z Fedora updates, instalátor cryinkfly 2.1.5-Alpha
(codeberg.org/cryinkfly/Autodesk-Fusion-360-on-Linux, commit `53b0203`),
Fusion 2706.1.17, licence Personal Use.

Žádný step ani `optional/` — záměrně. Fusion se nainstaluje, přihlásí a
otevře návrh, ale na Sway se v tom pracovat nedá: dialogy a panely se
rozpadají a za okny zůstávají černé plochy. Všechno bylo po pokusu odinstalováno.
Fusion teď běží ve Windows ve VMware Workstation s 3D akcelerací pro hosta,
viz `vmware-win11-setup.md` a `optional/vmware/`.

## Co bylo potřeba, než to vůbec naběhlo

Kdyby to někdy někdo zkoušel znovu — tohle jsou pasti, na které se narazilo,
v pořadí, jak přicházely.

1. **Wine z Fedory, ne z instalátoru.** Instalátor umí přidat Wine repo jen pro
   Fedoru 43 a Rawhide; na 44 jen vypíše „not supported“ a pokračuje bez Wine.
   Předem `dnf install wine cabextract samba-winbind-clients` (instalátor chce
   Wine ≥ 11.1, `wbinfo` a `cabextract`; zbytek jeho požadavků Sway spin má),
   pak `./autodesk_fusion_installer_x86-64.sh --install --default`. Prefix je
   v `~/.autodesk_fusion`, celkem ~15 GB, plus ~1,9 GB `~/.cache/winetricks`.
   Instalátor si sám stáhne Fusion přímým odkazem od Autodesku — web Autodesku
   na Linuxu nic nestáhne, tlačítko „try again“ nedělá nic.

2. **Přihlášení: obsluha `adskidmgr://` je zaregistrovaná špatně.** Instalátor
   dá `adskidmgr-opener.desktop` do podadresáře
   `~/.local/share/applications/wine/Programs/Autodesk/1/`, takže jeho ID je
   `wine-Programs-Autodesk-1-adskidmgr-opener.desktop`, ale do
   `mimeapps.list` zapíše `adskidmgr-opener.desktop`. Navíc `Exec` s
   `sh -c '…$(find …)…'` neprojde `desktop-file-validate`. Vivaldi pak po
   přihlášení neukáže žádný dialog. Pomohl vlastní desktop soubor přímo v
   `~/.local/share/applications/` s `Exec=<wrapper> %u`, kde wrapper spustí
   `AdskIdentityManager.exe` v prefixu s URL jako argumentem. Kód z URL je
   jednorázový — další „retry“ na stránce už nic neudělá, i když přihlášení
   prošlo (ověří se v `…/AppData/Local/Autodesk/Identity Services/Log/IdServices.log`:
   `User … logged in`).

3. **Nový účet bez teamu visí na „Connecting to your data“.** Fusion zjistí
   `hasTeamHub=0` a otevře webový team picker, který se pod Wine nevykreslí.
   Team je potřeba založit v prohlížeči
   (`https://login.autodesk360.com/g/teampicker?workflow=new_user_to_team`)
   a Fusion restartovat.

4. **Černé plátno při spuštění z menu: FremontJS padá na EBADF.** Fusion
   přibaluje `node.exe` (Node 22), na kterém běží FremontJS — lokální služba,
   bez které se návrh neotevře. Pod Wine `node.exe` spadne s
   `Error: open EBADF` (`createWritableStdioStream`), kdykoli je jeho stdout
   roura nebo socket. Spuštění z menu Sway dává aplikaci stdout do journald
   (socket), takže FremontJS umře hned po startu; z terminálu s výstupem do
   souboru běží. Reprodukce:

   ```bash
   export WINEPREFIX=~/.autodesk_fusion/wineprefixes/default
   NODE=".../webdeploy/production/<hash>/NODEJS/node.exe"
   wine "$NODE" -e 'console.log(1)' > /tmp/out.txt   # OK
   wine "$NODE" -e 'console.log(1)' | cat             # EBADF
   ```

   Oprava: spouštět launcher přes wrapper s `>"$log" 2>&1 </dev/null`.
   V logu Fusionu (`…/Autodesk Fusion 360/<user>/logs/AppLogFile*.log`) je
   pak `[pim.core] PIMJsService/onConnect: Connected to FremontJsLib`
   místo `Could not bring FremontJsLib back up`.

5. **Launcher cryinkfly končí `wineserver -k`.** Druhé spuštění, které hned
   skončí (Fusion hlídá jednu instanci), tím zabije i běžící Fusion. A po
   zavření okna občas v prefixu visí `Fusion360.exe` + `msedgewebview2.exe`
   bez oken — nutný `wineserver -k`.

## Na čem to padlo

- **DXVK (DirectX 11 → Vulkan na RADV):** 3D plátno se mezi snímky nemaže,
  při zoomu se mřížky vrší přes sebe, až je plocha skoro bílá.
- **OpenGL** (Preferences → General → Graphics driver, v
  `NMachineSpecificOptions.xml` `VirtualDeviceGLCore`): plátno kreslí
  správně, ale dialogy jsou rozbité, panel Browser nejde chytit, občas jen
  černé okno.
- **Virtuální plocha Wine** (`HKCU\Software\Wine\Explorer` `Desktop=Fusion`,
  `…\Explorer\Desktops` `Fusion=2945x1623`): okna jdou přesouvat, ale za nimi
  zůstává černá plocha a překreslí se až časem. Pro práci nepoužitelné.

Příčina je nejspíš kombinace XWayland + tiling WM + vnořená OpenGL/Vulkan
okna Wine. Nezkoušeno: `--install-fix` (Wine od cryinkfly s patchem na
captionless popupy a named pipes — předbuilděná binárka z GitHubu Lolig4,
nebo build přes Docker), nativní Wayland driver Wine (bez `DISPLAY`) a
X11 relace GNOME/KDE.

## Úklid

Instalátor má `--uninstall`, ale jednodušší bylo ručně: `wineserver -k`,
smazat `~/.autodesk_fusion`, `~/.cache/winetricks`, desktop soubory
(`~/.local/share/applications/wine/`, `wine-extension-*.desktop`, vlastní
`autodesk-fusion.desktop` a `adskidmgr-opener.desktop`), `x-wine-extension-*.xml`
v `~/.local/share/mime/packages/` (+ `update-mime-database`), Wine ikony z
`~/.local/share/icons/hicolor/*/apps/`, `wine-*.directory` a `wine-*.menu`,
řádek `x-scheme-handler/adskidmgr` v `~/.config/mimeapps.list`, a
`dnf history undo` transakce s Wine (114 balíků).
