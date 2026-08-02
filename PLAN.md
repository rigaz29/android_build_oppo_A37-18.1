# Rencana Porting LineageOS 18.1 — OPPO A37f (MSM8916)

> **Status:** Fase 1–2 selesai, terverifikasi & lolos tes build (`lunch` + `m nothing` + `m dtimage`).
> Fase 3–4 diverifikasi & lolos `m check-vintf-all` (COMPATIBLE); konfigurasinya ikut
> lolos parse penuh, tapi belum divalidasi compile penuh. Fase 5 diverifikasi & diperbaiki.
> Fase 6–8 diverifikasi & diperbaiki. Tersisa Fase 9: build penuh (`mka bacon`).
> **Target:** LineageOS 18.1 (Android 11) untuk OPPO A37 / A37f / A37fw
> **Baseline:** LineageOS 17.1 (Android 10) — branch `rb`, terbukti boot sampai homescreen (28 Juli 2026)
> **Chipset:** Qualcomm MSM8916 (Snapdragon 410), kernel 3.10.108, 2 GB RAM, Adreno 306
> **Referensi utama:** `LineageOS/android_device_motorola_msm8916-common` diff `lineage-17.1` → `lineage-18.1` (harpia/osprey — device MSM8916 resmi LineageOS)
> **Referensi sekunder:** Branch `lineage-18.1-a6000` dan commit `0fcaa843` di repo yang sama (port a6000, jadikan pembanding bukan base)

---

## Sumber Daya

| Repo | Branch | Status |
|---|---|---|
| `rigaz29/rb_device_oppo_A37` | `lineage-18.1` @ `a2b976b` (port + fix build/VINTF/sepolicy/blob/init) | ✅ Fase 2–7 lolos semua tes |
| `rigaz29/kernel_oppo_msm8939` | `lineage-18.1` @ `675ae89` (dari `lz4-backport` 70ef81d + 6 commit a12-prep + 3 commit verifikasi) | ✅ Fase 1 selesai, lolos build |
| `rigaz29/rb-vendor_oppo_A37` | `lineage-18.1` @ `8349a48` (repo baru, dari `6a64435` + fix Fase 6) | ✅ Fase 6 selesai |
| `LineageOS/android_hardware_sony_timekeep` | `lineage-18.1` | ⬜ Cek ketersediaan |
| `LineageOS/android_external_stlport` | `lineage-15.1` | ⬜ Cek apakah masih diperlukan |

Build manifest: `rigaz29/android_build_oppo_A37-18.1` → `A37.xml` ✅ ditulis & diverifikasi (Fase 8)

File riset tersimpan di `/tmp/a37-research/` (diff resmi, BoardConfig/manifest/device.mk referensi).

---

## Fase 1 — Kernel ✅ SELESAI

Branch `lineage-18.1` dibuat dari `lz4-backport` (70ef81d) + cherry-pick **6 commit** dari `a12-prep`:

- [x] `51b5a87` — defconfig: pre-create 32 loop devices untuk APEX
  - ⚠️ **Koreksi:** commit ini BUKAN no-op secara config — default `BLK_DEV_LOOP_MIN_COUNT`
    di 3.10 adalah **8** (`drivers/block/Kconfig:254`), commit menaikkannya ke 32.
    Yang membuatnya tak berdampak adalah hal lain: di Android 11
    `build/make/core/board_config.mk:619` menyetel `TARGET_FLATTEN_APEX := true`
    sebagai **default**, dan A37 tidak inherit `updatable_apex.mk` → APEX tetap
    flattened → loop device tidak dipakai untuk APEX. Harmless, dipertahankan.
    (Konsekuensi: menghapus `TARGET_FLATTEN_APEX := true` dari BoardConfig — seperti
    yang dilakukan msm8916-common — aman, karena default-nya memang `true`.)
- [x] `1433539` — defconfig: enable disk quota (`CONFIG_QUOTA`)
  - ⚠️ Direkomendasikan, bukan wajib platform. Konsumen = `fs_mgr.cpp:358` (flag `quota`
    di fstab), bukan vold. Fstab A37 saat ini belum punya flag `quota` → belum boot-kritis.
    Referensi resmi msm8916 memakainya. Jangan tambah flag `quota` ke fstab sebelum
    kernel punya CONFIG_QUOTA + CONFIG_QFMT_V2.
- [x] `1ed9c16` — defconfig: enable memory cgroup (`CONFIG_MEMCG`)
  - ✅ Wajib. `lmkd.cpp:79-81` baca `/dev/memcg/memory.usage_in_bytes`. Tanpa memcg
    + tanpa in-kernel LMK → lmkd exit → OOM tak terkendali.
- [x] `9ed22f6` — defconfig: disable in-kernel LMK → pakai lmkd userspace
  - ✅ **Rantai lengkap tervalidasi terhadap source:** `lmkd.cpp:3055` cek
    `/sys/module/lowmemorykiller/parameters/minfree` → tidak ada → `use_inkernel_interface
    = false` → `init_monitors()` (`lmkd.cpp:2975`) coba PSI dulu, gagal (3.10 tanpa PSI),
    **fallback vmpressure berhasil**. Kernel ini memang punya `mm/vmpressure.c`,
    `memory.pressure_level` (`mm/memcontrol.c:6000`) dan `cgroup.event_control`
    (`kernel/cgroup.c:4040`). `ro.lmk.use_psi=false` tetap opsional.
- [x] `d5d353a` — kbuild: mkdir -p output directory (fix build lewat soong)
  - ✅ Wajib. `vendor/lineage/build/soong/Android.bp` modul `generated_kernel_includes`:
    sbox hapus dir → `make O=<dir> headers_install` → kernel 3.10 gagal tanpa mkdir.
- [x] `fbfa62e` — dts: tambah `first_stage_mount` di fstab system
  - ⚠️ No-op secara fungsi di 18.1. `first_stage_mount.cpp:159-173`: filtering flag hanya
    untuk file fstab, A37 pakai DT fstab → semua entri di-mount tanpa filter.
    Baru wajib di Android 12. Harmless, dipertahankan sebagai persiapan.
  - ✅ **Tapi patch-nya kena sasaran.** Commit menyentuh `arch/arm/boot/dts/qcom/msm8916.dtsi`
    padahal kernel di-build `arm64`. Ternyata `arch/arm64/boot/dts/qcom` adalah **symlink**
    ke `../../../arm/boot/dts/qcom/`, jadi DTS itu memang yang dipakai. Terkonfirmasi:
    string `first_stage_mount` / `android,fstab` ada di dalam DTB hasil kompilasi.

> **Kenapa a12-prep gagal boot Android 12 tapi aman untuk 18.1?**
> Ke-6 commit hanya mengubah defconfig/dts/Makefile. Yang membuat Android 12
> gagal boot adalah kernel 3.10 secara arsitektural kekurangan fitur yang Android 12
> wajibkan: PSI (kernel 4.20+), eBPF, cgroup v2, dan kernel version gate di init.
> Android 11 **tidak** mensyaratkan PSI, eBPF, atau cgroup v2.

Pushed ke: https://github.com/rigaz29/kernel_oppo_msm8939/tree/lineage-18.1

### Verifikasi kernel vs LOS 18.1 (dari source tree `/root/los18`)

Commit `7a9d4eb` — 4 config, **diuji ulang dengan build nyata; hanya 1 yang bertahan:**

| Config | Hasil uji | Nasib |
|---|---|---|
| `CONFIG_ENCRYPTED_KEYS=y` | ✅ Mendarat di `.config`, efektif | Dipertahankan |
| `CONFIG_CRYPTO_SHA256=y` | ⚠️ **Redundan** — sudah `=y` di defconfig asli, di-`select` oleh `drivers/crypto/Kconfig:43` | Dibiarkan, harmless |
| `CONFIG_FHANDLE=y` | ⚠️ Mendarat (+ auto-select `EXPORTFS`), **tapi rasionalnya keliru**. Tidak ada satu pun konsumen `open_by_handle_at`/`name_to_handle_at` di `system/` maupun `frameworks/` — hanya muncul di header syscall bionic. AOSP justru **mewajibkan mati**: `# CONFIG_FHANDLE is not set` di `kernel/configs/{q,r}/android-4.14/android-base.config` | **Di-revert** di `675ae89` |
| `CONFIG_DEBUG_SET_MODULE_RONX=y` | ❌ **Tidak pernah mendarat.** `arch/arm64/Kconfig.debug:54` → `depends on MODULES`, sedangkan `CONFIG_MODULES is not set` (kernel monolitik). Dibuang Kconfig tanpa error — pola sama dengan bug `CONFIG_STACKPROTECTOR` | **Dihapus** di `675ae89` |

**Tidak perlu backport source code.** Semua gap kernel 3.10 ditangani fallback userspace:

| Fitur | Status | Fallback |
|---|---|---|
| memfd_create | ✅ Sudah di-backport (`mm/shmem.c:2678`, `__NR_memfd_create 385`) | `TARGET_HAS_MEMFD_BACKPORT` skip version gate ART/perfetto |
| getrandom | ✅ Sudah di-backport (`__NR_getrandom 384`) | — |
| vmpressure | ✅ Ada (`mm/vmpressure.c`, `memory.pressure_level` di `mm/memcontrol.c:6000`) | Jadi tumpuan lmkd, lihat `9ed22f6` |
| BinderFS | ❌ Tidak ada (kernel 5.0+) | Legacy device nodes `binder,hwbinder,vndbinder` cukup |
| BPF/eBPF | ❌ Tidak ada (kernel 3.18+) | netd fallback ke iptables. **Gate sebenarnya bukan versi kernel** — `BpfUtils.cpp:151` cek `api_level < MINIMUM_API_REQUIRED (28)` → `BpfLevel::NONE`. `ro.product.first_api_level=19` yang mematikannya |
| `xt_owner` | ❌ Tidak di-enable | Tidak perlu: **`xt_qtaguid.c:2974` mendaftarkan match bernama `"owner"` revisi 1**, persis yang dipakai `FirewallController.cpp:277` / `BandwidthController.cpp:232` |
| PSI | ❌ Tidak ada (kernel 4.20+) | lmkd fallback ke vmpressure (`lmkd.cpp:2975`, bukan 2877) |
| schedtune | ❌ Tidak ada | Fallback ke cpu cgroup. Mount gagal → `cgroup_map_write.cpp:388` hanya `LOG(WARNING)` lalu lanjut, **non-fatal** |
| cgroup v2 (freezer) | ❌ Tidak ada | Sama — non-fatal, hanya warning |
| `SYNC_FILE` | ❌ Tidak ada | `libsync/sync.c:109` mendukung legacy staging uapi; kernel punya `CONFIG_SYNC`/`SW_SYNC` |
| `FS_ENCRYPTION` (FBE) | ❌ Tidak ada | Device pakai FDE (`fstab.qcom:6` → `encryptable=footer`) + `TARGET_LEGACY_HW_DISK_ENCRYPTION := true` |
| FUSE (scoped storage) | — | `VolumeManager.cpp:388` baca `persist.sys.fuse` default **false**; `CONFIG_SDCARD_FS=y` → tetap jalur sdcardfs yang cepat |
| ION | ✅ Masih supported | DMA-BUF transition baru di Android 12+ |
| FS_VERITY | ❌ Tidak ada (kernel 5.4+) | Opsional, tidak dipakai kecuali fstab flag `fsverity` |
| `OVERLAY_FS`, `UID_SYS_STATS` | ❌ Tidak ada di 3.10 | `adb remount` overlay mati; battery stats per-UID terdegradasi. **Tidak sepadan di-backport** untuk target "boot dulu" |
| Kernel patches LOS | ✅ Tidak ada | `vendor/lineage/patches/` tidak ada |

Audit penuh terhadap `kernel/configs/r/android-4.14/android-base.config` (250 syarat):
**187 terpenuhi, 39 absen, 24 beda nilai** sebelum patch di bawah. Tidak ada yang boot-kritis.

### Patch pengerasan defconfig (commit `35e50af`, disusul `675ae89`)

Diterapkan ke `arch/arm64/configs/lineageos_a37f_defconfig` — **defconfig yang benar-benar
di-build** (`TARGET_KERNEL_ARCH := arm64`).

**Bug nyata yang diperbaiki:**

- `CONFIG_STACKPROTECTOR=y` → `CONFIG_CC_STACKPROTECTOR=y` + `CONFIG_CC_STACKPROTECTOR_REGULAR=y`
  - Commit `e8bab6d7a92` ("...add stack protector") memakai nama symbol yang **tidak ada di
    kernel 3.10** — di sini namanya `CC_STACKPROTECTOR` (`arch/Kconfig:350`); rename ke
    `STACKPROTECTOR` baru terjadi di Linux 4.18. Kconfig membuang baris tak dikenal tanpa
    error, jadi stack protector **tidak pernah aktif** sejak commit itu.

**Tambahan fungsional (semua terverifikasi mendarat di `.config`):**

| Opsi | Alasan |
|---|---|
| `CONFIG_IP_MULTICAST=y` | mDNS / `NsdManager`, Cast, penemuan printer — sebelumnya mati |
| `CONFIG_INET_UDP_DIAG=y` | netd `SockDiag` destroy socket UDP saat ganti network / VPN |
| `CONFIG_VETH=y` | tethering / network stack Android 11 |
| `CONFIG_NET_SCH_INGRESS=y`, `CONFIG_XFRM_STATISTICS=y` | syarat `android-base.config` R |
| `CONFIG_TASKSTATS` + `TASK_XACCT` + `TASK_IO_ACCOUNTING` + `TASK_DELAY_ACCT` | `/proc/<pid>/io` → StorageStats & BatteryStats |
| `CONFIG_MEMCG_SWAP=y` | akunting swap memcg (device pakai zram) |
| `CONFIG_UTS_NS=y`, `CONFIG_PID_NS=y` | syarat `android-base.config` R, biaya nol |
| `CONFIG_IKCONFIG=y` + `IKCONFIG_PROC=y` | `/proc/config.gz` untuk debug (dimatikan `e8bab6d`) |

### Hasil tes build (2 Agu 2026)

Toolchain persis seperti `vendor/lineage/build/tasks/kernel.mk`: GCC 4.9
(`aarch64-linux-android-4.9`) + `HOSTCFLAGS="-fuse-ld=lld"`, tanpa `TARGET_KERNEL_CLANG_COMPILE`.

| Build | Konfigurasi | Hasil |
|---|---|---|
| 1 | defconfig asli @ `fbfa62e` | ✅ Image 16.592.888 B, 4 warning, 0 error |
| 2 | + patch pengerasan (15 opsi) | ✅ Image 16.729.272 B, 4 warning, 0 error |
| 3 | + 4 config dari `7a9d4eb` | ✅ Image 16.729.272 B, 4 warning, 0 error |
| 4 | − `FHANDLE` (+`EXPORTFS`) − `DEBUG_SET_MODULE_RONX` (final, `675ae89`) | ✅ Image 16.729.272 B, 4 warning, 0 error |

- `make dtbs` → `msm8916-mtp-15399.dtb` 207.455 B; node `first_stage_mount` / `android,fstab`
  terkonfirmasi ada di dalam DTB hasil kompilasi
- `make headers_install` ke direktori output baru → exit 0, membuktikan `d5d353a` berfungsi
- `generated_kernel_includes` (`vendor/lineage/build/soong/Android.bp:20`) meng-export
  `usr/audio/include/uapi`, `usr/include/audio`, `usr/techpack/audio/include` yang **tidak
  dihasilkan** kernel 3.10 ini. Aman: `generator.go:131-134` hanya membangun path lewat
  `PathForModuleGen` tanpa cek keberadaan → sekadar `-I` ke direktori kosong

**Kesimpulan: kernel siap. Tidak ada backport source yang wajib.**

### Sisa pekerjaan kernel

- [x] Commit + push patch pengerasan — `35e50af`, branch `lineage-18.1`
- [x] `CONFIG_FHANDLE` di-revert + `CONFIG_DEBUG_SET_MODULE_RONX` dihapus — `675ae89`
- [ ] `arch/arm/configs/lineageos_a37f_defconfig` **sudah basi** — 4 commit defconfig dari
      `a12-prep` hanya menyentuh `arch/arm64/`. Karena `TARGET_KERNEL_ARCH := arm64` itu
      benar, tapi defconfig arm kini tanpa MEMCG/QUOTA/loop-count/disable-LMK.
      Sinkronkan atau hapus supaya tidak menjebak nanti
- [ ] Opsional setelah boot: tambah flag `quota` ke `fstab.qcom` — blocker sudah hilang
      karena kernel kini punya `CONFIG_QUOTA` + `CONFIG_QFMT_V2`

---

## Fase 2 — Device Tree: File Konfigurasi Utama ✅ SELESAI

Branch `lineage-18.1` di-reset ke `rb` (17.1 proven) sebagai base bersih.
Semua perubahan diverifikasi terhadap diff resmi msm8916-common 17.1→18.1.

### BoardConfig.mk (commit `dcae2e98`)

- [x] `TARGET_KERNEL_ADDITIONAL_FLAGS := HOSTCFLAGS="-fuse-ld=lld ..."` — host toolchain 18.1 pakai clang/lld
- [x] `TARGET_HAS_MEMFD_BACKPORT := true` — kernel 3.10 tidak punya memfd_create (baru 3.17)
- [x] `TARGET_VNDK_USE_CORE_VARIANT := true` — dedupe VNDK libs
- [x] `TARGET_DISABLE_POSTRENDER_CLEANUP := true`
- [x] `TARGET_USES_LEGACY_WFD := true`
- [x] `WIFI_HIDL_UNIFIED_SUPPLICANT_SERVICE_RC_ENTRY := true`
- [x] Shim `libcutils_shim.so` untuk `libril-qc-qmi-1.so` (libcutils berubah di R)
- [x] `BOARD_SEPOLICY_DIRS` → `BOARD_VENDOR_SEPOLICY_DIRS`
- [x] Hapus `BOARD_CHARGER_ENABLE_SUSPEND` → properti `ro.charger.enable_suspend=true` di device.mk
- [x] Hapus `WIFI_HIDL_FEATURE_DISABLE_AP_MAC_RANDOMIZATION`

**Dipertahankan (terverifikasi masih valid di 18.1):**
- `PRODUCT_VENDOR_MOVE_ENABLED := true` — resmi masih dipakai
- `include device/qcom/sepolicy-legacy/sepolicy.mk` — repo branch `lineage-18.1-legacy` (snippets/lineage.xml:64)
- `SELINUX_IGNORE_NEVERALLOWS := true` + `androidboot.selinux=permissive`

**Tidak ditambahkan (tidak ada di referensi):**
- ~~`BOARD_VNDK_VERSION := current`~~ — tidak dipakai referensi mana pun
- ~~`BUILD_BROKEN_ELF_PREBUILTS`~~ — tidak ada di tree resmi

### lineage_A37.mk

- [x] `PRODUCT_SHIPPING_API_LEVEL := 19`

### AndroidProducts.mk

- [x] Tidak perlu diubah (format sudah kompatibel)

Pushed ke: https://github.com/rigaz29/rb_device_oppo_A37/tree/lineage-18.1

### Verifikasi & tes Fase 2 (2 Agu 2026)

**Tes yang dijalankan — semua lolos:**

| Tes | Hasil |
|---|---|
| `lunch lineage_A37-userdebug` | ✅ `PLATFORM_VERSION=11`, `LINEAGE_VERSION=18.1-...-A37` |
| `m nothing` (soong analysis + kati parse ±20.700 makefile + packaging rules) | ✅ **build completed successfully** |
| `m dtbToolOppo dtimage` | ✅ `dt.img` 210.944 B dari 4 varian chipset (206/248/249/250), semua `oppoId: 15399` |
| Kernel lewat build system LOS | ✅ `out/.../kernel` 16.745.656 B; `.config`-nya memuat patch Fase 1 (`CC_STACKPROTECTOR`, `IP_MULTICAST`, `VETH`, `UTS_NS`, `# CONFIG_FHANDLE is not set`) |

**3 blocker build ditemukan & diperbaiki:**

1. `BUILD_BROKEN_PHONY_TARGETS := true` → **dihapus**. Obsolete di Android 11
   (`KATI_obsolete_var`); daftar `BUILD_BROKEN_*` yang masih sah ada di
   `build/make/core/board_config.mk:89-94`. Ini hard error, `lunch` pun gagal.
2. `usb/Android.bp` + `lights/Android.bp` bergantung pada `libhidltransport` dan
   `libhwbinder` → **dihapus dari `shared_libs`**. Di Android 11 keduanya dilebur ke
   `libhidlbase` dan visibility-nya dibatasi `:__subpackages__`
   (`system/libhidl/Android.bp:113-119`, `system/libhwbinder/Android.bp:64-69`).
   Catatan: entri `libhidltransport`/`libhwbinder` di `PRODUCT_PACKAGES` (device.mk)
   **tetap benar** — itu stub runtime untuk blob vendor lama, urusan berbeda.
3. `dtbtool/Android.mk` pakai `BUILD_HOST_EXECUTABLE` yang obsolete →
   **dikonversi ke `dtbtool/Android.bp` (`cc_binary_host`)**.
   `dtbToolOppo` **tidak bisa** diganti `dtbToolLineage` (`system/tools/dtbtool`):
   varian OPPO menambah field `oppoId` sehingga entry size jadi 28/44 (bukan 24/40),
   dan bootloader OPPO memakai field itu untuk memilih DT.

**1 escape hatch dipakai:**

- `BUILD_BROKEN_USES_BUILD_COPY_HEADERS := true` — stack GPS device-specific
  (`gps/core`, `gps/utils`, `gps/loc_api/{ds_api,libloc_api_50001,loc_api_v02}`)
  masih memakai `LOCAL_COPY_HEADERS`, hard error di
  `build/make/core/shared_library.mk:59-62`. Flag ini menurunkannya jadi warning.
  Konversi ke `header_libs` Soong = pekerjaan tersendiri, bukan prasyarat boot.

**Rantai separated-DT terverifikasi utuh di 18.1** (sempat dikira hilang karena
`kernel.mk` hanya mengenal `BOARD_KERNEL_SEPARATED_DTB**O**`):
`build/make/core/Makefile:1259` → `--dt dt.img` → dibangun
`vendor/lineage/build/tasks/dt_image.mk` memakai `$(TARGET_CUSTOM_DTBTOOL)`.

**Koreksi klaim Fase 2:**

- `TARGET_USES_LEGACY_WFD := true` — **tidak ada konsumennya** di tree ini (grep
  seluruh tree: hanya muncul di BoardConfig A37 sendiri). Juga tidak ada di
  msm8916-common 18.1; asalnya `ref0-BoardConfig.mk:115`. Harmless tapi mati.
- `PRODUCT_VENDOR_MOVE_ENABLED := true` — masih dipakai, tapi konsumennya cuma satu:
  `hardware/qcom-caf/wlan/wcnss-service/Android.mk`.
- Variabel lain tanpa konsumen (harmless, kandidat bersih-bersih): `DISABLE_APEX_TEST_MODULE`,
  `TARGET_PLATFORM_DEVICE_BASE`, `MAX_EGL_CACHE_KEY_SIZE`, `MAX_EGL_CACHE_SIZE`,
  `TARGET_USES_NEW_ION_API`, `BOARD_SUPPRESS_EMMC_WIPE`, `TARGET_USES_MKE2FS`.

**Temuan untuk fase lain:**

- `BUILD_BROKEN_DUP_RULES := true` **masih dibutuhkan**. Duplicate rule yang tersisa:
  `out/.../vendor/lib/libmm-omxcore.so` — `device.mk:350` memasukkan `libmm-omxcore`
  ke `PRODUCT_PACKAGES` (build dari source) sementara `vendor/oppo/A37/A37-vendor.mk:242`
  menyalin blob prebuilt ke path yang sama. Mana yang menang bergantung urutan parsing.
  Perlu diputuskan di Fase 3/6: buang salah satu.
- `external/stlport` ada di `lineage.dependencies` tapi **tidak ter-sync** dan build
  tetap lolos → kandidat kuat untuk dihapus dari dependencies (lihat Fase 8).
- `dtbtool.c` A37 kehilangan `O_TRUNC` saat membuka output (baris 932; versi kanonik
  `system/tools/dtbtool/dtbtool.c:926` memakainya). Pada rebuild incremental yang
  menghasilkan dt.img lebih kecil, sisa byte lama tertinggal. Belum diperbaiki.

---

## Fase 3 — Device Tree: HAL & Packages (`device.mk`)

**Usaha: Sedang** | **Risiko: Tinggi** (VINTF mismatch = gagal boot)

### Update versi HAL (terverifikasi dari msm8916-common 18.1)

| HAL | 17.1 (rb) | 18.1 (resmi) | Catatan |
|---|---|---|---|
| Audio service | `audio@2.0-service` | **`android.hardware.audio.service`** | Nama baru |
| Audio impl | `audio@5.0*` | **`audio@6.0*`** | Semua naik ke 6.0 |
| Audio effect | `audio.effect@5.0*` | **`audio.effect@6.0*`** | |
| BT audio | `bluetooth.a2dp@1.0-impl` + `audio.a2dp.default` | **`bluetooth.audio@2.0-impl`** + **`audio.bluetooth.default`** | Stack baru |
| Audio policy XML | `a2dp_audio_policy_configuration.xml` | **`bluetooth_audio_policy_configuration.xml`** + **`a2dp_in_audio_policy_configuration.xml`** | |
| DRM clearkey | `drm@1.2-service.clearkey` | **`drm@1.3-service.clearkey`** | `drm@1.0-impl`+`service` tetap |
| Health | `health@2.0-impl/-service` | **`health@2.1-impl/-service`** | + `@2.1-impl.recovery` |
| Power | `power@1.0-impl/-service` | **`power-service-qti` (AIDL)** + **`power.stats@1.0-service.mock`** | Pindah ke AIDL |
| Display composer | `composer@2.1-impl` + service | **`composer@2.1-service`** saja | impl dihapus |
| Gatekeeper | (tidak ada) | **`gatekeeper@1.0-service.software`** | Baru, wajib |
| WiFi | `wifi@1.0-service.legacy` | **`wifi@1.0-service`** | Bukan `.legacy` |
| Sensors | `sensors@1.0-impl` + `sensors@1.0-service` | **`sensors@1.0-impl`** saja | service dihapus |

### Tambah (terverifikasi)

- [ ] `InProcessNetworkStack` + `com.android.tethering.inprocess` — resmi ditambah di 18.1
- [ ] `libhidltransport` + `libhwbinder` (+ varian `.vendor`)
- [ ] `PRODUCT_ENFORCE_VINTF_MANIFEST_OVERRIDE := true`
- [ ] `PRODUCT_ENFORCE_RRO_TARGETS := *` + `WifiOverlay` + `TetheringConfigOverlay` (RRO wajib di R)
- [ ] `libcutils_shim` (untuk RIL blob)
- [ ] `vndservicemanager`
- [ ] `libprotobuf-cpp-lite-v28.so` dari `prebuilts/vndk/v28/` (v28 masih tersedia di 18.1)

### Hapus (terverifikasi)

- [ ] `keystore.msm8916` — dihapus di tree resmi
- [ ] `charger_res_images` — dihapus di tree resmi
- [ ] `renderscript@1.0-service` — dihapus
- [ ] `PRODUCT_DISABLE_SCUDO := true` — flag tidak ada lagi

### Properti baru (terverifikasi)

- [ ] `ro.charger.enable_suspend=true` (pengganti BOARD_CHARGER_ENABLE_SUSPEND)
- [ ] `ro.control_privapp_permissions=enforce`
- [ ] `ro.lmk.use_psi=false` + properti lmkd lain (kernel 3.10 tidak punya PSI)
- [ ] `ro.oem_unlock_supported=false`
- [ ] `persist.bluetooth.disableabsvol=true`

### Seccomp

- [ ] Tambah `mediaextractor.policy` + `mediaswcodec.policy`

### TIDAK perlu (koreksi dari rencana awal)

- ~~`authsecret@1.0-service`~~ — tidak dipasang referensi mana pun (shipping API 19, FCM legacy)
- ~~`fastbootd` + `fastboot@1.0-impl-mock`~~ — tidak dipasang referensi mana pun
- ~~VNDK v28 → v30~~ — v28 masih tersedia dan dipakai tree resmi
- ~~Hapus `InProcessNetworkStack`~~ — justru ditambah di 18.1
- ~~Hapus configstore~~ — tree resmi mempertahankannya

---

## Fase 4 — VINTF Manifest (`manifest.xml`)

**Usaha: Sedang** | **Risiko: Tinggi** (harus sinkron dengan device.mk)

### Perubahan terverifikasi dari msm8916-common 18.1

**Root tag:**
- [ ] Tambah `target-level="legacy"`

**Update versi:**
```
android.hardware.audio:            5.0 → 6.0
android.hardware.audio.effect:     5.0 → 6.0
android.hardware.drm:              clearkey fqname @1.2 → @1.3
```

**Tambah entri baru:**
```xml
android.hardware.bluetooth.a2dp@1.0      (IBluetoothAudioOffload)
android.hardware.bluetooth.audio@2.0     (IBluetoothAudioProvidersFactory)
```

**Hapus entri (diganti VINTF fragment dari paket):**
```xml
android.hardware.health          <!-- paket health@2.1-service bawa fragment sendiri -->
android.hardware.power           <!-- power-service-qti AIDL bawa fragment -->
android.hardware.usb             <!-- paket service bawa fragment -->
android.hardware.wifi            <!-- wifi@1.0-service bawa fragment -->
android.hardware.wifi.hostapd    <!-- hostapd bawa fragment -->
android.hardware.wifi.supplicant <!-- supplicant bawa fragment -->
```

**TETAP (koreksi dari rencana awal):**
- `android.hardware.bluetooth` **@1.0** — BUKAN 1.1 (resmi tetap 1.0)
- `android.hardware.gnss` **@1.0** — BUKAN 2.0 (resmi tetap 1.0)
- `android.hardware.configstore` **@1.1** — TETAP dideklarasikan (tidak dihapus)
- `android.hardware.camera.provider@2.4` passthrough
- `android.hardware.keymaster@3.0`
- `android.hardware.light@2.0`
- `android.hardware.vibrator@1.0`
- `android.hardware.sensors@1.0` passthrough
- `android.hardware.graphics.*` (allocator@2.0, composer@2.1, mapper@2.1)
- `android.hardware.media.omx@1.0`
- `android.hardware.memtrack@1.0`
- `android.hardware.renderscript@1.0`
- `android.hardware.radio@1.0` + keluarga
- `vendor.qti.hardware.cryptfshw@1.0`
- `vendor.lineage.trust@1.0`
- `vendor.lineage.livedisplay@2.0`

**TIDAK ditambah (koreksi):**
- ~~`authsecret@1.0`~~ — tidak ada di referensi MSM8916
- ~~`fastboot@1.0`~~ — tidak ada di referensi MSM8916

### Verifikasi & tes Fase 3–4 (2 Agu 2026, commit `8276fea`)

**Tes:** `m nothing` ✅ · `m check-vintf-all` → **`COMPATIBLE`** ✅

#### BUG boot-kritis yang ditemukan: `vendor.lineage.trust` dideklarasikan dua kali

`m check-vintf-all` awalnya **gagal total**:

```
VINTF parse error: Cannot add manifest fragment
  /vendor/etc/vintf/manifest/vendor.lineage.trust@1.0-service.xml:
  HAL "vendor.lineage.trust" has a conflict.
No device HAL manifest: No such device
```

Paket `vendor.lineage.trust@1.0-service` membawa VINTF fragment sendiri
(`hardware/lineage/interfaces/trust/Android.bp`), sementara `manifest.xml` juga
mendeklarasikannya. `HalManifest::shouldAdd` (`system/libvintf/HalManifest.cpp:44-65`)
menolak `<hal>` yang major version-nya sudah terdaftar — dan penolakan itu
**membatalkan seluruh device manifest**, bukan cuma entri yang bentrok. Device jadi
tanpa manifest VINTF sama sekali. Entri manual dihapus.

> **Aturan sebenarnya (mengoreksi "aturan sinkronisasi" di bawah):** konflik hanya
> terjadi kalau fragment memakai tag `<version>`. Fragment drm clearkey hanya berisi
> `<fqname>` tanpa `<version>`, jadi `shouldAdd` tidak pernah menolaknya — karena itu
> deklarasi paralel drm di `manifest.xml` aman dan memang dipakai msm8916-common 18.1.

#### Fragment yang terpasang (hasil build) vs `manifest.xml`

| Fragment | HAL | Status |
|---|---|---|
| `android.hardware.wifi@1.0-service.xml` | wifi | ✅ tidak di manifest — benar |
| `android.hardware.wifi.hostapd.xml` | hostapd | ✅ tidak di manifest — benar |
| `manifest.xml` (supplicant) | wifi.supplicant | ✅ tidak di manifest — benar |
| `android.hardware.health@2.1.xml` | health | ✅ tidak di manifest — benar |
| `android.hardware.gatekeeper@...software.xml` | gatekeeper | ✅ tidak di manifest — benar |
| `android.hardware.cas@1.2-service.xml` | cas | ✅ tidak di manifest — benar |
| `manifest_...drm@1.3-service.clearkey.xml` | drm | ✅ ada di manifest, aman (tanpa `<version>`) |
| `vendor.lineage.trust@1.0-service.xml` | trust | ❌ **bentrok → diperbaiki** |

#### Improve: interface LiveDisplay yang hilang

Paket livedisplay `-legacymm` dan `-sysfs` **tidak** membawa fragment, jadi tiap
interface harus dideklarasikan manual. Yang tidak dideklarasikan **tidak bisa diambil
sama sekali**: dengan `PRODUCT_ENFORCE_VINTF_MANIFEST`, `getTransport()` mengembalikan
`EMPTY` → `allowLegacy` false → `getService()` langsung `nullptr`
(`system/libhidl/transport/ServiceManagement.cpp:755-771`).

Sebelumnya hanya `IPictureAdjustment` (diwarisi dari 17.1 — **bukan regresi port**),
padahal `-sysfs` mendaftarkan enam interface. Ditambahkan dua yang terbukti register:

- `IDisplayColorCalibration` — butuh `/sys/class/graphics/fb0/rgb`;
  `mdss_livedisplay.c:797` membuat atribut `rgb` **tanpa syarat**
- `IAdaptiveBacklight` — butuh `acl` atau `cabc`; A37 tidak punya `acl` tapi `cabc`
  dibuat karena panel 15399 mendeklarasikan `qcom,mdss-dsi-cabc-*-command`
  (`MODE_CABC`, `mdss_livedisplay.c:801`)

Sisanya (`IDisplayModes`, `ISunlightEnhancement`, `IAutoContrast`, `IColorEnhancement`,
`IReadingEnhancement`) **sengaja tidak** didaftarkan — tidak ada bukti node sysfs /
dukungan `libmm-disp-apis`-nya ada, dan mendeklarasikan HAL yang tak pernah register
membuat `getService()` menunggu lewat jalur `vintfHwbinder` + `Waiter`.

#### Cross-check penyedia: semua 26 `<hal>` punya penyedia

Termasuk yang dilayani blob vendor (`bluetooth.a2dp`, `radio`, `qti.perf`, `qti.iop`)
dan `configstore` yang datang dari `build/make/target/product/base_vendor.mk:73`.

### Aturan sinkronisasi

> Setiap `<hal>` di manifest.xml HARUS punya pasangan di `PRODUCT_PACKAGES` (device.mk),
> KECUALI entri yang dihapus karena sudah di-handle VINTF fragment dari paket.
> Jika manifest mendeklarasikan `audio@6.0` tapi yang di-build `audio@5.0-impl`,
> VINTF check gagal → device tidak boot.

---

## Fase 5 — SEPolicy

**Usaha: Besar** | **Risiko: Sedang** (permissive dulu, enforce nanti)

`device/qcom/sepolicy-legacy` **terverifikasi tetap valid** di 18.1 — disediakan oleh
repo `LineageOS/android_device_qcom_sepolicy` branch `lineage-18.1-legacy`
(snippets/lineage.xml baris 64).

### File baru yang perlu dibuat

- [ ] `hal_bluetooth_audio_default.te`
- [ ] `hal_health_2_1.te` (atau update `hal_health_default.te`)
- [ ] `hal_power_default.te` — update untuk AIDL power-service-qti

### File yang perlu di-update

- [ ] `vendor_init.te` — banyak type/attribute baru
- [ ] `init.te` — domain baru untuk service Android 11
- [ ] `system_server.te` — permission baru
- [ ] `vold.te` — quota, metadata partition
- [ ] `file_contexts` — path binary HAL baru
- [ ] `property_contexts` — properti baru Android 11
- [ ] `genfs_contexts` — filesystem type baru

### Strategi

1. Boot dengan `androidboot.selinux=permissive` + `SELINUX_IGNORE_NEVERALLOWS := true`
2. Kumpulkan `avc: denied` dari `dmesg` / `logcat`
3. Perbaiki bertahap, domain per domain
4. Target akhir: `enforcing` (menyusul setelah semua fitur jalan)

### Verifikasi & tes Fase 5 (2 Agu 2026, commit `e9d1daf`)

**Tes:** `m selinux_policy` ✅ · `m sepolicy_neverallows` ✅ · `m nothing` ✅ ·
`m check-vintf-all` → `COMPATIBLE` ✅

#### BUG: `drm@1.3-service.clearkey` tanpa label file_contexts

Cek coverage otomatis atas **18 HAL service** yang dideklarasikan `device.mk` menemukan
satu biner tanpa entri. AOSP `system/sepolicy/vendor/file_contexts:25-26` hanya melabeli
`drm@1.0-service` dan `-lazy`, sedangkan `device.mk:104` memasang `@1.3-service.clearkey`.
Init `.rc` bawaannya juga **tidak** menyetel `seclabel`, jadi init sepenuhnya bergantung
pada label file. Tanpa entri, biner berlabel `vendor_file` → init gagal transisi domain →
servis DRM jalan di domain `init`.

Ditambal dengan `hal_drm_default_exec`. **Sesudah: 18/18 berlabel.**

#### Kenapa `SELINUX_IGNORE_NEVERALLOWS` tetap wajib (dengan angka)

Komentar lama menyebut alasannya "file_contexts belum lengkap" — itu tidak lagi benar,
tapi flag-nya tetap perlu karena alasan lain. Diukur dengan `m sepolicy_neverallows`:

| Sumber pelanggaran | Jumlah |
|---|---|
| `system/sepolicy/public/property.te` | 626 |
| domain aplikasi (`priv_app`, `untrusted_app`, `radio`, `platform_app`, `system_app`, …) | 46 masing-masing |
| `device/qcom/sepolicy-legacy/**` | ratusan |
| **`device/oppo/A37/sepolicy/timekeep_app.te:7`** (`app_domain(timekeep_app)`) | **8** |
| **Total** | **~1.500** |

Artinya hampir semua pelanggaran berasal dari sepolicy legacy QCOM + platform, **di luar
kendali device tree ini**. Hanya 8 yang milik A37 sendiri. Target `enforcing` realistis
hanya jika `sepolicy-legacy` ditinggalkan — bukan sekadar menambal `.te` device.

> ⚠️ **Jebakan pengukuran:** `device/qcom/sepolicy-legacy/sepolicy.mk:11` menyetel
> `SELINUX_IGNORE_NEVERALLOWS := true` **tanpa syarat**. Override apa pun yang ditulis
> *sebelum* baris `include`-nya di BoardConfig akan ditimpa, sehingga pengukuran tampak
> "lolos" padahal cek-nya tidak pernah berjalan. Override harus **setelah** include.
> Selain itu `m selinux_policy` **tidak** membangun modul `sepolicy_neverallows` — dan
> modul itu di-cache, jadi artefaknya (`out/target/product/A37/fake_packages/
> sepolicy_neverallows`) harus dihapus dulu agar cek benar-benar dijalankan.

#### Terverifikasi sudah benar (tidak perlu diubah)

- `file.te` / `property.te` mendeklarasikan `proc_touchpanel` dan `vendor_timekeep_prop`
  yang dipakai `genfs_contexts` / `property_contexts` — policy compile bersih
- Biner `livedisplay@2.0-service-{legacymm,sysfs}` **sudah** berlabel lewat
  `device/lineage/sepolicy/{qcom,common}/vendor/file_contexts`
- `IAdaptiveBacklight` + `IDisplayColorCalibration` (ditambahkan di Fase 4) sudah punya
  entri `hwservice_contexts` dari sepolicy LineageOS — jadi perubahan Fase 4 aman
- Entri `usb@1.0-service.cyanogen_8916` memakai bentuk `/system/vendor/...` tanpa
  alternasi; sah untuk layout `PRODUCT_VENDOR_MOVE_ENABLED` device ini, hanya tidak seragam

#### Catatan untuk fase enforcing

22 properti yang di-set `device.mk` belum punya `property_contexts` (mis. `ro.usb.id.*`,
`persist.hwc.*`, `rild.libpath`, `ro.sys.sdcardfs`). Semuanya properti **build-time** di
`build.prop`, bukan ditulis runtime, jadi bukan blocker boot — tapi akan jadi `avc: denied`
terhadap `default_prop` saat enforcing.

---

## Fase 6 — Vendor Blobs (`vendor/oppo`)

**Usaha: Sedang** | **Risiko: Sedang**

- [ ] Fork branch `lineage-17.1` → `lineage-18.1`
- [ ] Update `A37-vendor.mk`:
  - [ ] Path `$(TARGET_COPY_OUT_SYSTEM)/etc/` → `$(TARGET_COPY_OUT_VENDOR)/etc/`
    untuk file yang seharusnya di partisi vendor
  - [ ] `libbase-v28.so` **tetap v28** (v28 masih tersedia di 18.1, tidak perlu v30)
  - [ ] Tambah `libprotobuf-cpp-lite-v28.so` jika blob DRM butuh
- [ ] Cek prebuilt HIDL services terhadap library yang berubah:
  - [ ] `perf@1.0-service`
  - [ ] `iop@1.0/2.0`
  - [ ] `bluetooth@1.0-service-qti`
  - [ ] `time_daemon`
  - [ ] DRM Widevine blob — cek apakah butuh `libprotobuf-cpp-lite-v29.so`
- [x] Verifikasi semua file di `proprietary-files.txt` masih ada dan benar path-nya

### Verifikasi & tes Fase 6 (2 Agu 2026 — device `3c9651b`, vendor `8349a48`)

**Tes:** `m nothing` ✅ · `m selinux_policy` ✅ · `m check-vintf-all` → `COMPATIBLE` ✅
· konsistensi daftar blob ✅ · analisis `DT_NEEDED` atas **302 blob ELF** ✅

#### 2 bug ditemukan

**`libmmcamera_tuning.so` ada di repo tapi tidak pernah dipasang.** Tidak terdaftar di
`proprietary-files.txt` maupun `A37-vendor.mk`, padahal `libmm-qcamera.so` dan
`liboemcamera.so` mem-`dlopen`-nya lewat nama (terlihat dari `strings`). Sudah didaftarkan.

**`sensors.a6000.so` — sisa port Lenovo A6000.** Disalin ke `/system/lib/` (bukan
`/vendor/lib/hw/`) dengan nama device yang salah. HAL sensor yang benar-benar dipakai
adalah `sensors.msm8916` dari source (`device.mk:625`). Pola sama dengan bug lights
`-service.a6000` sebelumnya. Blob + semua referensinya dihapus.

**Hasil: 338 entri terdaftar = 338 file di disk, nol selisih dua arah.**

#### Dependensi blob: 6 library hilang, 1 bisa ditambal

Dari ROM LineageOS 18.1 A37 yang beredar (tipzbuilds 2022-03-08, dipastikan ELF32/ARM):

| Library hilang | Dibutuhkan oleh | Status |
|---|---|---|
| `libthermalclient.so` | `libqti-perfd.so` ← `libqti-perfd-client.so` | ✅ **diambil dari ROM referensi** |
| `libvcel.so` | `lib-imsvt.so` (IMS video telephony) | ❌ tidak ada di ROM referensi juga |
| `libmmsw_math/platform/opencl/detail_enhancement.so` | `libvpplibrary.so` ← `libOmxVpp.so` | ❌ tidak ada di ROM referensi juga |

ROM referensi menyelesaikannya dengan **tidak memasang** `libvpplibrary.so` maupun
`libqti-perfd.so` sama sekali. Tree ini masih memasang keduanya → `libOmxVpp` gagal
`dlopen` dan video post-processing mati diam-diam. Tidak menghalangi boot; ditinjau ulang
setelah device hidup.

#### Terverifikasi sudah benar

- **Tidak ada** blob `proprietary/vendor/...` yang salah disalin ke partisi `SYSTEM` (0 kasus)
- 9 entri ke `TARGET_COPY_OUT_SYSTEM` semuanya memang library sisi system (media/omx/iop)
- `libbase-v28.so` tetap v28 lewat `device.mk:215` dari `prebuilts/vndk/v28` — sesuai rencana
- Tidak ada blob yang membutuhkan `libprotobuf-cpp-lite-v28/v29`, jadi item itu **tidak perlu**

#### Duplicate rule `libmm-omxcore`: didokumentasikan, sengaja belum diubah

`BUILD_BROKEN_DUP_RULES` dipicu tepat **satu** target: `vendor/lib/libmm-omxcore.so`.
Diverifikasi dari perintah ninja bahwa **salinan blob yang menang**, sehingga modul hasil
build source dikompilasi lalu dibuang.

> Menghapusnya dari `PRODUCT_PACKAGES` **sudah dicoba dan gagal** — modulnya tetap ditarik
> sebagai dependensi `libOmx*` lain, dan build langsung gagal begitu `BUILD_BROKEN_DUP_RULES`
> dilepas. Satu-satunya jalan adalah membuang salinan prebuilt dari `A37-vendor.mk`, tapi itu
> **mengganti biner terpasang** dari blob ke hasil build source — padahal kombinasi blob +
> `libOmx*` source itulah yang terbukti boot di 17.1. Ditinjau ulang setelah boot.

#### Repo vendor sendiri sudah dibuat

Sebelumnya `vendor/oppo/A37` menunjuk `meghs-playground/rb-vendor_oppo_A37` (bukan milik
`rigaz29`) sehingga tidak bisa di-push. Repo baru dibuat dan branch di-push:

**`rigaz29/rb-vendor_oppo_A37` branch `lineage-18.1` @ `8349a48`**

`A37.xml` di Fase 8 harus diarahkan ke sini, bukan lagi ke pin `6a64435` milik
`meghs-playground`.

---

## Fase 7 — Init Scripts & Rootdir

**Usaha: Sedang** | **Risiko: Sedang**

- [ ] `fstab.qcom`:
  - [ ] Cek flag `fileencryption=` / `encryptable=`
  - [ ] Tambah entri `metadata` partition jika diperlukan
  - [ ] Salin ke `$(TARGET_COPY_OUT_RAMDISK)/fstab.qcom` untuk first-stage init
- [ ] `init.target.rc` / `init.qcom.rc`:
  - [ ] Android 11 lebih ketat: `mkdir`, `chown`, `chmod` harus di phase yang benar
  - [ ] Service baru perlu `seclabel` yang sesuai
  - [ ] Cek trigger `on property:` yang berubah
- [ ] `ueventd.qcom.rc`:
  - [ ] Android R mewajibkan naming vendor (`ueventd.qcom.rc`, bukan `ueventd.rc`)
- [x] `init.recovery.qcom.rc`:
  - [x] Cek kompatibilitas dengan recovery 18.1

### Verifikasi & tes Fase 7 (2 Agu 2026, commit `c8dc9ab`)

**Tes utama: `host_init_verifier`** — validator init bawaan Android 11. Ia otomatis
dijalankan untuk modul yang nama file terpasangnya cocok pola `init%rc`
(`build/make/core/misc_prebuilt_internal.mk:27`), jadi keenam `init*.rc` device ini
memang diperiksa saat build. Ditambah `m nothing` ✅ · `m selinux_policy` ✅ ·
`m check-vintf-all` → `COMPATIBLE` ✅.

#### 2 bug ditemukan & diperbaiki

**`load_system_props` → build gagal.**

```
host_init_verifier: Command 'load_system_props' (init.target.rc:102) failed:
  'load_system_props' is deprecated
```

Dihapus. Aman: di runtime pun sudah no-op — `do_load_system_props`
(`system/core/init/builtins.cpp:1084`) hanya mencatat log lalu `return`.

**`/firmware` tidak pernah berlabel `firmware_file`.** vfat tidak mendukung xattr, jadi
labelnya dari genfscon, dan platform menyetel `genfscon vfat / u:object_r:vfat:s0`
(`system/sepolicy/private/genfs_contexts:315`) → seluruh isi `/firmware` berlabel `vfat`.
Padahal policy device memberi izin terhadap **`firmware_file`**: `vendor_init.te:1,7`,
`keystore.te:3,4`, `mediacodec.te:2`, `priv_app.te:16`, plus `hal_drm`/`esepmdaemon` di
`sepolicy-legacy`. Aturan itu tidak pernah cocok → baca firmware modem/DRM ditolak saat
enforcing. Ditambahkan `context=u:object_r:firmware_file:s0` ke opsi mount, sama seperti
ROM 18.1 A37 yang beredar.

#### Terverifikasi benar (tidak diubah)

| Item | Bukti |
|---|---|
| 8 modul rootdir semuanya di `PRODUCT_PACKAGES` | dicek satu per satu |
| init mengimpor `/vendor/etc/init/hw/init.${ro.hardware}.rc` | `system/core/rootdir/init.rc:10` — cocok dengan `LOCAL_MODULE_PATH` |
| 4 baris `import` di `init.qcom.rc` cocok path terpasang | dibandingkan dengan isi `out/.../init/hw/` |
| `ueventd` di `/vendor/ueventd.rc` | salah satu path yang dibaca `ueventd.cpp:291`. **Klaim rencana keliru** — yang berubah di 18.1 adalah nama *modul*, bukan nama file terpasang |
| `init.recovery.qcom.rc` di `/` | `bootable/recovery/etc/init.rc:1` → `import /init.recovery.${ro.hardware}.rc` |
| `mount_all` + `swapon_all` → `/vendor/etc/fstab.qcom` | cocok urutan cari `fs_mgr_fstab.cpp:416` |
| 16 service di rc menunjuk biner yang benar-benar terpasang | dicek terhadap ninja graph + blob vendor |

#### Tidak berlaku untuk device ini

- **Partisi `metadata`** — hanya untuk FBE/metadata encryption. A37 pakai FDE
  (`encryptable=footer`), konsisten dengan kernel tanpa `FS_ENCRYPTION`
- **Salin fstab ke ramdisk** — first-stage mount lewat DT fstab, sudah terkonfirmasi ada
  di dalam DTB hasil kompilasi (lihat Fase 1)

#### Catatan metodologi

Cek label SELinux service sempat melaporkan 15 dari 16 service "tanpa domain". Itu
**false positive**: matcher menganggap aturan luas `plat_file_contexts:79`
(`/system(/.*)?` → `system_file`) menang atas entri spesifik. Diverifikasi dengan membaca
xattr `security.selinux` asli dari image ROM referensi:
`/vendor/bin/rmt_storage` → `rmt_storage_exec`, `qseecomd` → `tee_exec`,
`rild` → `rild_exec`. Entri spesifik memang menang; tidak ada bug.

> Konsekuensinya untuk Fase 5: label fallback `drm@1.3-service.clearkey` sebelum ditambal
> sebenarnya `system_file`, bukan `vendor_file` seperti tertulis di sana. Temuan dan
> perbaikannya tetap benar — binernya memang tidak punya entri spesifik di mana pun
> sehingga init tidak bisa transisi ke domain `hal_drm_default`.

#### Perbandingan dengan ROM 18.1 A37 yang beredar

Layout init identik (5 rc di `/vendor/etc/init/hw/`). Perbedaan fstab yang belum diadopsi,
bukan bug tapi layak dipertimbangkan setelah boot: `reservedsize=128M` dan `latemount`
pada `/data`, serta `journal_async_commit`. Sebaliknya ROM itu **tidak** punya
`/vendor/ueventd.rc` sama sekali — device tree ini lebih lengkap di sisi itu.

---

## Fase 8 — Build Manifest (`A37.xml`)

**Usaha: Kecil** | **Risiko: Rendah**

- [x] Update semua `revision` ke branch `lineage-18.1`
- [x] `hardware/sony/timekeep` → `lineage-18.1`
- [x] Cek apakah `external/stlport` masih diperlukan — **tidak**, sudah dihapus
- [x] `device/qcom/sepolicy-legacy` sudah di-handle oleh snippet LOS (branch `lineage-18.1-legacy`)
- [x] Repo init: `repo init -u https://github.com/LineageOS/android.git -b lineage-18.1`

### Verifikasi & tes Fase 8 (2 Agu 2026)

`A37.xml` ditulis ke repo manifest (sebelumnya repo ini hanya berisi PLAN.md) dan
disalin ke `.repo/local_manifests/` tree kerja.

**Tes:** XML well-formed ✅ · `repo manifest` parse ✅ · setiap `project@revision` resolve
di remote ✅ · `m nothing` + `m selinux_policy` + `m check-vintf-all` ✅

| Path | Project | Revision | SHA terverifikasi |
|---|---|---|---|
| `device/oppo/A37` | `rigaz29/rb_device_oppo_A37` | `lineage-18.1` | `a2b976b` |
| `vendor/oppo` | `rigaz29/rb-vendor_oppo_A37` | `lineage-18.1` | `8349a48` |
| `kernel/oppo/msm8939` | `rigaz29/kernel_oppo_msm8939` | `lineage-18.1` | `675ae89` |
| `hardware/sony/timekeep` | `LineageOS/android_hardware_sony_timekeep` | `lineage-18.1` | `858c544` |

> Path vendor adalah **`vendor/oppo`**, bukan `vendor/oppo/A37` — repo-nya berisi
> subdirektori `A37/`.

#### Sengaja TIDAK dimasukkan ke manifest

- **`device/qcom/sepolicy-legacy`** — sudah disediakan LineageOS lengkap dengan revision
  yang benar (`snippets/lineage.xml:64` → `android_device_qcom_sepolicy @ lineage-18.1-legacy`).
  Mendeklarasikan ulang justru berisiko bentrok revision.
- **`external/stlport`** — tidak ada di manifest LOS mana pun, tidak pernah ter-sync, dan
  seluruh build lolos tanpanya. Dihapus juga dari `lineage.dependencies` (commit `a2b976b`).

#### ⚠️ Tree lama perlu `--force-sync` sekali

Karena nama project vendor berubah (`meghs-playground/…` → `rigaz29/…`), `repo sync` biasa
pada tree yang **sudah ada** akan menolak:

```
--force-sync not enabled; cannot overwrite a local work tree.
```

repo mengikat metadata git di `.repo/projects/vendor/oppo.git` ke nama project lama.
Solusinya sekali jalan: `repo sync --force-sync vendor/oppo` — pastikan dulu tidak ada
commit lokal di `vendor/oppo` yang belum di-push. `repo init` baru dari nol tidak
terpengaruh. Sudah didokumentasikan di komentar `A37.xml`.

---

## Fase 9 — Build & Debug Pertama

**Strategi: boot dulu, fitur menyusul**

1. [ ] `repo sync` dengan manifest baru
2. [ ] `source build/envsetup.sh && breakfast lineage_A37-userdebug`
3. [ ] `mka bacon` — perbaiki error kompilasi satu per satu
4. [ ] Flash, target: **boot sampai homescreen**
5. [ ] Kumpulkan log: `logcat -b all`, `dmesg`, `cat /proc/last_kmsg`
6. [ ] Identifikasi HAL yang gagal register → perbaiki manifest.xml / device.mk
7. [ ] Iterasi sampai stabil

### Masalah umum yang diantisipasi

| Gejala | Kemungkinan Penyebab |
|---|---|
| Bootloop di logo | VINTF mismatch (manifest.xml vs device.mk) |
| Crash di `system_server` | Properti hilang / salah, sepolicy terlalu ketat |
| Wi-Fi tidak jalan | `wifi@1.0-service` perlu WifiOverlay RRO |
| Audio mati | `audio@6.0` butuh `audio_policy_configuration.xml` format baru |
| Kamera crash | Blob HAL1 vs framework Android 11 — cek `camera.provider@2.4` |
| SIM tidak terdeteksi | RIL blob butuh `libcutils_shim` |
| Bluetooth gagal | Prebuilt `bluetooth@1.0-service-qti` vs `bluetooth.audio@2.0` |
| lmkd tidak jalan | CONFIG_MEMCG belum enable di kernel (wajib jika in-kernel LMK dimatikan) |

---

## Urutan Pengerjaan

```
Fase 1 (Kernel) ✅
    │
    ▼
Fase 2 (BoardConfig, lineage_A37.mk) ✅
    │
    ▼
Fase 3 (device.mk — HAL & packages)  ◄──┐
    │                                    │
    ▼                                    │ iterasi
Fase 4 (manifest.xml — VINTF)  ◄────────┘
    │
    ▼
Fase 8 (A37.xml) → repo sync → BUILD PERTAMA
    │
    ▼
Fase 9 (debug boot)
    │
    ├──► Fase 5 (SEPolicy) — paralel dengan debug
    ├──► Fase 6 (Vendor blobs) — jika ada blob crash
    └──► Fase 7 (Init scripts) — jika ada masalah mount/init
```

---

## Yang TIDAK Berubah

Hal-hal berikut sudah benar di 17.1 dan tidak perlu dimodifikasi
(dikonfirmasi oleh referensi msm8916-common 18.1):

- Arsitektur: tetap 32-bit (`TARGET_ARCH := arm`, `cortex-a53`)
- `TARGET_USES_64_BIT_BINDER := true`
- Kernel base/tags/ramdisk offset
- Display: gralloc@2.0, composer@2.1, memtrack@1.0 (versi HAL tetap)
- Camera HAL1 legacy path (`camera.provider@2.4` passthrough)
- Bluetooth HCI **@1.0** (tetap, bukan 1.1)
- GNSS **@1.0** (tetap, bukan 2.0)
- ConfigStore **@1.1** (tetap dideklarasikan)
- Sensors `@1.0` passthrough
- Vibrator `@1.0`
- Keymaster `@3.0`
- `PRODUCT_VENDOR_MOVE_ENABLED := true` (masih valid)
- `device/qcom/sepolicy-legacy` (masih valid, branch `lineage-18.1-legacy`)
- VNDK prebuilt **v28** (masih tersedia, tidak perlu migrasi v30)
- `ro.product.first_api_level=19`
- Dalvik VM tuning (heapgrowthlimit 192m, dll.)
- LZ4 zram compression
- Interactive governor tuning
- Double-tap-to-wake (Synaptics OPPO driver)

---

## Log Perubahan Rencana

| Tanggal | Perubahan |
|---|---|
| 2 Agu 2026 | Rencana awal dibuat (banyak asumsi belum terverifikasi) |
| 2 Agu 2026 | Fase 1 selesai: kernel lineage-18.1 (6 commit cherry-pick) |
| 2 Agu 2026 | **Revisi besar**: riset terhadap msm8916-common resmi mengoreksi banyak asumsi. Fase 2 diulang dari base `rb` (bukan a6000). authsecret/fastboot dihapus dari rencana. bluetooth/gnss/configstore/VNDK dikoreksi. |
| 2 Agu 2026 | **Verifikasi Fase 1**: semua 6 commit kernel diverifikasi terhadap source LOS 18.1 (lmkd.cpp, fs_mgr.cpp, first_stage_mount.cpp, apexd_loop.cpp, vendor/lineage/build/soong). Koreksi: first_stage_mount = no-op di 18.1 (DT fstab), CONFIG_QUOTA = direkomendasikan bukan wajib, lmkd fallback vmpressure otomatis tanpa ro.lmk.use_psi. |
| 2 Agu 2026 | **Fase 3+4 selesai**: device.mk + manifest.xml di-port dan diverifikasi. 3 paket dihapus (tidak ada di LOS 18.1: tethering.inprocess, WifiOverlay, TetheringConfigOverlay). USB VINTF gap di-fix. |
| 2 Agu 2026 | **Verifikasi kernel penuh** dari source tree `/root/los18`: tidak perlu backport source code. 4 defconfig baru ditambahkan (FHANDLE, ENCRYPTED_KEYS, CRYPTO_SHA256, DEBUG_SET_MODULE_RONX). Commit `7a9d4eb`. |
| 2 Agu 2026 | **Kernel diuji build sungguhan** (commit `35e50af`) (3 build, semua exit 0) dengan toolchain LOS 18.1 (GCC 4.9 + lld host). Audit terhadap `android-base.config` R: 187/250 terpenuhi, tidak ada yang boot-kritis. Ditemukan & diperbaiki bug `CONFIG_STACKPROTECTOR` (symbol tidak valid di 3.10 → stack protector tidak pernah aktif). Ditambah 15 opsi pengerasan (IP_MULTICAST, INET_UDP_DIAG, VETH, TASKSTATS, MEMCG_SWAP, UTS_NS/PID_NS, IKCONFIG, dll). Koreksi atas `7a9d4eb`: DEBUG_SET_MODULE_RONX tidak mendarat (butuh CONFIG_MODULES), CRYPTO_SHA256 redundan, FHANDLE rasionalnya keliru & AOSP mewajibkan mati. Koreksi atas `51b5a87`: bukan no-op config (default loop count = 8), yang membuatnya tak berdampak adalah TARGET_FLATTEN_APEX default `true` di R. |
| 2 Agu 2026 | **Fase 8 dikerjakan & diuji**: `A37.xml` ditulis ke repo manifest (sebelumnya cuma berisi PLAN.md) dan dipasang di `.repo/local_manifests/`. Keempat `project@revision` diverifikasi resolve di remote dengan SHA yang cocok persis dengan tree kerja. `device/qcom/sepolicy-legacy` sengaja tidak dideklarasikan karena sudah disediakan `snippets/lineage.xml:64` lengkap dengan revision `lineage-18.1-legacy`. `external/stlport` terbukti tidak diperlukan dan dihapus dari `lineage.dependencies` (`a2b976b`). Ditemukan: tree lama butuh `repo sync --force-sync vendor/oppo` sekali karena nama project vendor berubah — sudah didokumentasikan di komentar manifest. |
| 2 Agu 2026 | **Fase 7 dikerjakan & diuji** (commit `c8dc9ab`) memakai `host_init_verifier`, validator init bawaan Android 11. Dua bug: `load_system_props` deprecated bikin build gagal (dihapus; di runtime pun sudah no-op), dan `/firmware` tidak pernah berlabel `firmware_file` karena vfat tanpa xattr jatuh ke `genfscon vfat -> vfat` sementara policy device memberi izin ke `firmware_file` — ditambahkan opsi mount `context=`. Terverifikasi benar: import path, `ueventd` di `/vendor/ueventd.rc`, `init.recovery.qcom.rc` di `/`, `mount_all`/`swapon_all`, dan 16 service menunjuk biner yang ada. Klaim rencana soal penamaan `ueventd.qcom.rc` dikoreksi: yang berubah nama modul, bukan file terpasang. Cek label service sempat false-positive; dikoreksi dengan membaca xattr asli dari image ROM referensi. |
| 2 Agu 2026 | **Fase 6 dikerjakan & diuji** (device `3c9651b`, vendor `8349a48`): analisis `DT_NEEDED` atas 302 blob ELF menemukan 6 library hilang; `libthermalclient.so` diambil dari ROM 18.1 A37 yang beredar (rantai `libqti-perfd-client` → `libqti-perfd` → `libthermalclient`), 5 sisanya juga absen di ROM referensi. Dua bug daftar blob: `libmmcamera_tuning.so` ada di repo tapi tak pernah dipasang padahal di-`dlopen` `libmm-qcamera`/`liboemcamera`, dan `sensors.a6000.so` sisa port Lenovo A6000 disalin ke direktori salah. Hasil: 338 terdaftar = 338 di disk. Duplicate rule `libmm-omxcore` ditelusuri sampai tuntas (blob yang menang; menghapus dari PRODUCT_PACKAGES tidak menolong karena ditarik lewat dependensi) lalu didokumentasikan, bukan diubah. Repo vendor sendiri dibuat: `rigaz29/rb-vendor_oppo_A37`. |
| 2 Agu 2026 | **Fase 5 diverifikasi & diuji** (commit `e9d1daf`): cek coverage otomatis menemukan `drm@1.3-service.clearkey` tanpa entri `file_contexts` — AOSP hanya melabeli `drm@1.0-service`/`-lazy`, dan `.rc`-nya tak menyetel `seclabel`, jadi binernya berlabel `vendor_file` dan servis DRM jalan di domain `init`. Ditambal → 18/18 HAL service berlabel. Diukur juga alasan sebenarnya `SELINUX_IGNORE_NEVERALLOWS` masih wajib: ~1.500 pelanggaran, 626 dari `property.te` platform dan ratusan dari `sepolicy-legacy` QCOM, hanya 8 milik A37 (`timekeep_app.te:7`). Dicatat dua jebakan pengukuran: override flag harus SETELAH `include sepolicy-legacy` (yang memaksa `:= true`), dan artefak `sepolicy_neverallows` harus dihapus dulu karena `m selinux_policy` tidak membangunnya. |
| 2 Agu 2026 | **Fase 3–4 diverifikasi & diuji** (commit `8276fea`): `m check-vintf-all` awalnya **gagal total** — `vendor.lineage.trust` dideklarasikan di `manifest.xml` sekaligus dibawa VINTF fragment paketnya, dan `HalManifest::shouldAdd` menolaknya sehingga **seluruh device manifest batal** ("No device HAL manifest"). Entri manual dihapus → **COMPATIBLE**. Diklarifikasi kenapa drm tidak ikut bentrok: fragment clearkey tanpa tag `<version>`. Improve: `IDisplayColorCalibration` + `IAdaptiveBacklight` ditambahkan ke livedisplay (paketnya tak bawa fragment; tanpa deklarasi `getService()` langsung null karena `PRODUCT_ENFORCE_VINTF_MANIFEST`), dipilih hanya yang terbukti register lewat node sysfs kernel A37. Cross-check: semua 26 `<hal>` punya penyedia. |
| 2 Agu 2026 | **Fase 2 diverifikasi & diuji build**: `lunch` + `m nothing` (soong + kati ±20.700 makefile) + `m dtbToolOppo dtimage` semuanya lolos; dt.img 210.944 B dengan `oppoId: 15399` terisi, dan kernel yang dibangun build system memuat patch Fase 1. Tiga blocker Android 11 diperbaiki: `BUILD_BROKEN_PHONY_TARGETS` obsolete (dihapus), `libhidltransport`/`libhwbinder` visibility di `usb`+`lights` Android.bp (dihapus dari shared_libs), `BUILD_HOST_EXECUTABLE` obsolete di dtbtool (dikonversi ke `cc_binary_host`). Escape hatch `BUILD_BROKEN_USES_BUILD_COPY_HEADERS` dipakai untuk stack GPS. Koreksi: `TARGET_USES_LEGACY_WFD` ternyata tanpa konsumen. Temuan untuk fase lain: duplicate rule `libmm-omxcore.so` (device.mk vs A37-vendor.mk), `external/stlport` tidak diperlukan, `dtbtool.c` A37 kehilangan `O_TRUNC`. |
| 2 Agu 2026 | **Bersih-bersih `7a9d4eb`** (commit `675ae89`, build ke-4 exit 0): `CONFIG_FHANDLE` di-revert — tanpa konsumen di `system/`/`frameworks/` dan AOSP mewajibkannya mati di Q maupun R; ikut menghapus `EXPORTFS` yang di-`select`-nya. `CONFIG_DEBUG_SET_MODULE_RONX` dihapus — tidak pernah mendarat karena `depends on MODULES` sedangkan kernel monolitik. Dari 4 config `7a9d4eb`, tersisa `ENCRYPTED_KEYS` (efektif) dan `CRYPTO_SHA256` (redundan, dibiarkan). |

---

*Dokumen ini hidup — update status checkbox seiring progress.*
