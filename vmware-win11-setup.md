# Windows 11 ve VMware Workstation (Autodesk Fusion)

Zprovozněno 26. 11. 2026: Fedora 44 Sway, jádro 7.1.9, Ryzen 7 8700G jen
s integrovanou Radeon 780M, 60 GB RAM bez swapu, `/home` na btrfs
(`compress=zstd:1`). VMware Workstation Pro 26.0.1 (26H1u1), Windows 11 Pro
build 26300, Fusion pod licencí Personal Use.

Proč VMware: Fusion pod Wine na Sway je nepoužitelný (`fusion-wine-attempt.md`)
a KVM (virt-manager, quickemu, dockur) nedá Windows 3D akceleraci, takže by
Fusion kreslil softwarově. VMware předá hostovi DirectX 11 (Shader Model 5)
přes Vulkan na hostiteli (RADV). Workstation Pro je zdarma i komerčně.

Skripty jsou v `optional/vmware/`. Nainstaluje se jedna volitelná komponenta
(`./optional.sh vmware`), virtuálku pak založí samostatný skript.

## Postup

1. **Stáhnout ručně** (obojí je za přihlášením nebo za formulářem, skript to
   neumí):
   - VMware: <https://support.broadcom.com/group/ecx/free-downloads> →
     VMware Workstation Pro → … for Linux → `VMware-Workstation-Full-*.x86_64.bundle`
     do `~/Downloads`. Potřebuje účet Broadcom. Poprvé chce i adresu kvůli
     exportní kontrole. Stará veřejná úložiště VMware (`softwareupdate.vmware.com`)
     vrací 404.
   - Windows: <https://www.microsoft.com/software-download/windows11> →
     „Windows 11 (multi-edition ISO for x64 devices)“, English, do `~/Downloads`.
2. `bash optional/vmware/setup.sh`
   - Doinstaluje `gcc`, `make`, `elfutils-libelf-devel` a `kernel-devel`
     pro běžící jádro.
   - Spustí bundle s `--console --required --eulas-agreed` (EULA se tím odsouhlasí).
   - Přeloží `vmmon`/`vmnet` přes `vmware-modconfig --console --install-all`.
   - Zapne `vmware.service` a `vmware-USBArbitrator.service`.
   - Nastaví KVM (viz níže).
3. `bash optional/vmware/new-win11-vm.sh [cesta/k/Win11.iso]` vytvoří
   `~/vmware/win11`:
   - 8 vCPU, 12 GB RAM, 128 GB NVMe disk, který roste podle potřeby,
   - UEFI se Secure Boot a softwarovým vTPM, 3D akcelerace s 8 GB grafické paměti,
   - NAT a sdílená složka `~/vmware/shared`.

   Mění se proměnnými `VM_DIR`, `SHARED_DIR`, `VM_MEM_MB`, `VM_CPUS` a `DISK_SIZE`.
   Existující virtuálku skript nepřepíše.
4. `vmware ~/vmware/win11/win11.vmx` → **Power on**. Klikni do okna virtuálky
   a při „Press any key to boot from CD or DVD…“ stiskni klávesu. Máš na to
   asi 5 s. Když to nestihneš, vypni virtuálku a zkus to znovu.
5. Dál už běží všechno samo. Windows se instalují asi 20 minut, pak proběhne
   automatické přihlášení a `vm-setup.ps1` (VMware Tools, stažení a tichá
   instalace Fusionu) a restart, to je dalších asi 15 minut. Log je ve Windows
   v `C:\Windows\Temp\vm-setup.log`.

### Co dělá bezobslužná instalace

`files/autounattend.xml` a `files/vm-setup.ps1` jsou zabalené v
`unattend.iso` (`xorriso`). Windows Setup hledá `autounattend.xml` v kořeni
všech jednotek. Nastaví:

- Windows 11 Pro s generickým klíčem `VK7JG-…`, veřejným klíčem Microsoftu,
  který jen vybere edici a nic neaktivuje,
- přeskočené kontroly TPM, Secure Boot a RAM (`HKLM\SYSTEM\Setup\LabConfig`),
- smazaný disk 0 rozdělený na EFI, MSR a C:,
- anglické UI, české formáty, klávesnice US + CZ QWERTY a časovou zónu
  Central Europe,
- lokální účet `$USER` bez hesla a bez Microsoft účtu, OOBE celé přeskočené,
  jedno automatické přihlášení,
- při prvním přihlášení `vm-setup.ps1` z té jednotky, kde leží:
  - VMware Tools z `/usr/lib/vmware/isoimages/windows.iso`, které je připojené
    jako třetí CD. Instalátor se hledá podle ProductName, protože i ISO
    Windows má v kořeni `setup.exe`.
  - Vypnuté uspávání monitoru i systému.
  - `Fusion Admin Install.exe` z `dl.appstreaming.autodesk.com` s `--quiet`.
  - Restart.

## Pasti

- **KVM drží virtualizaci.** Od jádra 6.12 je `kvm.enable_virt_at_load=Y`:
  KVM zapne AMD-V/VT-x hned při načtení modulu a drží ho, i když žádná KVM
  virtuálka neběží. Out-of-tree hypervisory (VMware, VirtualBox) ho pak
  nedostanou. `setup.sh` dá do `/etc/modprobe.d/kvm-virt-on-demand.conf`
  `enable_virt_at_load=0` a `kvm` přenačte. Nastaveno předem, chybu s `Y` jsem
  tu nezkoušel. KVM virtuálky (dockur, libvirt) fungují dál, jen ne současně
  s VMware.
- **btrfs: copy-on-write a komprese.** Obraz disku virtuálky a `.vmem` se
  neustále přepisují na místě. S CoW a zstd se soubor rozdrobí a každý zápis
  jde přes kompresi. Projevilo se to zátěží CPU a I/O tlakem na hostiteli.
  `new-win11-vm.sh` proto dává adresáři `chattr +C`, ještě když je prázdný.
  Soubory v něm vzniklé to zdědí a NOCOW soubory btrfs ani nekomprimuje.
  Existující disk se dá převést jen kopií do nového souboru:
  ```bash
  touch new.vmdk && chattr +C new.vmdk
  cp --reflink=never --sparse=always win11.vmdk new.vmdk
  cmp win11.vmdk new.vmdk && mv new.vmdk win11.vmdk && chmod 600 win11.vmdk
  ```
- **Paměť virtuálky je v souboru `.vmem` na disku a bez swapu jinak nejde.**
  VMware na Linuxu mapuje RAM hosta ze souboru vedle disku.
  `mainMem.useNamedFile = "FALSE"` by ji dal do paměti, kterou jde odložit do
  swapu. Bez swapu na hostiteli ale VMware tohle nastavení ignoruje:
  `vmware.log` vypíše `msg.mainMem.backing.noSwap` a stejně otevře
  `…/<uuid>.vmem`. Ověřeno na malé testovací virtuálce. Nepomohlo ani
  `prefvmx.minVmMemPct = "100"` (Preferences → Memory → „Fit all virtual
  machine memory into reserved host RAM“) v `~/.vmware/config` ani v
  `~/.vmware/preferences`. Plánovač paměti si to nastavení ale nejspíš
  přečte, jen když žádná virtuálka neběží (log ukazoval `mempct 50`), takže
  to ještě není úplně vyloučené. Ve `.vmx` to nastavení zůstává pro případ,
  že by swap někdy byl. Díky NOCOW adresáři je aspoň `.vmem` bez CoW a bez
  komprese. Když po vypnutí virtuálky soubor zůstane (tady se to stalo),
  dá se smazat.
- **Kolik RAM.** Hostitel bez virtuálky zabírá kolem 42 GB z 60. Při 16 GB pro
  virtuálku stoupl tlak na paměť (PSI) v průměru na 66 % a stroj se dusil.
  Proto 12 GB, `MemTrimRate = "0"` (VMware nevrací paměť hosta) a
  `sched.mem.pshare.enable = "FALSE"` (neskenuje stránky kvůli sdílení).
  `earlyoom` (krok 06b) by při nedostatku paměti nejspíš sestřelil právě
  `vmware-vmx`, protože je největší a není v `--avoid`.
- **GUI přepisuje `.vmx`.** Do `.vmx` zapisuj jen při zavřeném VMware
  (File → Exit). Jinak ho GUI při zavření přepíše svou verzí. Po prvním
  otevření virtuálky v GUI se objevilo `isolation.tools.hgfs.disable = "TRUE"`
  a sdílená složka byla vypnutá. V GUI se to opraví volbou
  VM → Settings → Options → Shared Folders → Always enabled.
- **Po aktualizaci jádra** chybí `vmmon`/`vmnet` a virtuálka nenaběhne. Pomůže
  znovu spustit `bash optional/vmware/setup.sh`, který je přeloží jen tehdy,
  když pro běžící jádro chybí. VMware při startu nabízí vlastní překlad, ten
  jsem nezkoušel. U jádra novějšího, než VMware zná, se překlad může rozbít.
  Pak pomůžou záplaty z `github.com/mkubecek/vmware-host-modules`.

## Ve Windows

- **3D:** VMware Tools dodají ovladač SVGA 3D. Ve `.vmx` se pak objeví
  `vmotion.svga.sm5 = "1"` (DirectX 11). Ve Fusionu se to nastavuje
  v Preferences → General → Graphics driver: DirectX 11 nebo Auto.
- **Prvních asi 60 minut po instalaci** Windows vytěžují CPU sami (Defender,
  Windows Update, indexování, optimalizace .NET). Fusion se při prvním
  spuštění k tomu ještě stahuje. Vytížení CPU proto hodnoť až potom.
- **Přihlášení do Fusionu přes Edge nefungovalo** (Edge nešel přihlásit do
  Googlu). Pomůže nastavit Firefox jako výchozí prohlížeč
  (Settings → Apps → Default apps → Firefox → Set default). Odkaz
  `adskidmgr://` pak otevři v Autodesk Identity Manager. Edge se mimo EEA
  odinstalovat nedá a **WebView2 Runtime** musí zůstat, Fusion ho používá
  na vložené webové panely.
- **Aktivace:** Windows běží neaktivované bez časového omezení. Je vidět
  vodoznak, personalizace je zamčená a občas se objeví připomínka. Klíč se dá
  zadat kdykoli v Settings → System → Activation.
- **Sdílená složka:** `~/vmware/shared` je ve Windows
  `\\vmware-host\Shared Folders\shared`.

## Odinstalace

Virtuálku smažeš jako adresář `~/vmware/win11`. VMware odinstaluješ přes
`sudo vmware-installer -u vmware-workstation`. Pak ještě smaž
`/etc/modprobe.d/kvm-virt-on-demand.conf`, `~/.vmware` a případně
`~/vmware/shared`.
