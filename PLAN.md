# Rencana Porting LineageOS 18.1 — OPPO A37f (MSM8916)

> **Status:** Fase 1–2 selesai, Fase 3–9 belum dikerjakan
> **Target:** LineageOS 18.1 (Android 11) untuk OPPO A37 / A37f / A37fw
> **Baseline:** LineageOS 17.1 (Android 10) — branch `rb`, terbukti boot sampai homescreen (28 Juli 2026)
> **Chipset:** Qualcomm MSM8916 (Snapdragon 410), kernel 3.10.108, 2 GB RAM, Adreno 306
> **Referensi utama:** `LineageOS/android_device_motorola_msm8916-common` diff `lineage-17.1` → `lineage-18.1` (harpia/osprey — device MSM8916 resmi LineageOS)
> **Referensi sekunder:** Branch `lineage-18.1-a6000` dan commit `0fcaa843` di repo yang sama (port a6000, jadikan pembanding bukan base)

---

## Sumber Daya

| Repo | Branch | Status |
|---|---|---|
| `rigaz29/rb_device_oppo_A37` | `lineage-18.1` (dari `rb` 547f8ca + 1 commit port) | ✅ Fase 2 selesai |
| `rigaz29/kernel_oppo_msm8939` | `lineage-18.1` (dari `lz4-backport` 70ef81d + 6 commit a12-prep) | ✅ Fase 1 selesai |
| `meghs-playground/rb-vendor_oppo_A37` | `lineage-17.1` (pin `6a64435`) | ⬜ Perlu branch `lineage-18.1` |
| `LineageOS/android_hardware_sony_timekeep` | `lineage-18.1` | ⬜ Cek ketersediaan |
| `LineageOS/android_external_stlport` | `lineage-15.1` | ⬜ Cek apakah masih diperlukan |

Build manifest: `rigaz29/android_build_oppo_A37-18.1` → `A37.xml`

File riset tersimpan di `/tmp/a37-research/` (diff resmi, BoardConfig/manifest/device.mk referensi).

---

## Fase 1 — Kernel ✅ SELESAI

Branch `lineage-18.1` dibuat dari `lz4-backport` (70ef81d) + cherry-pick **6 commit** dari `a12-prep`:

- [x] `51b5a87` — defconfig: pre-create 32 loop devices untuk APEX (sudah `=y` di base, no-op)
- [x] `1433539` — defconfig: enable disk quota (`CONFIG_QUOTA`)
- [x] `1ed9c16` — defconfig: enable memory cgroup (`CONFIG_MEMCG`)
- [x] `9ed22f6` — defconfig: disable in-kernel LMK → pakai lmkd userspace
- [x] `d5d353a` — kbuild: mkdir -p output directory (fix build lewat soong)
- [x] `fbfa62e` — dts: tambah `first_stage_mount` di fstab system (Android 11+)

> **Kenapa a12-prep gagal boot Android 12 tapi aman untuk 18.1?**
> Ke-6 commit hanya mengubah defconfig/dts/Makefile. Yang membuat Android 12
> gagal boot adalah kernel 3.10 secara arsitektural kekurangan fitur yang Android 12
> wajibkan: PSI (kernel 4.20+), eBPF, cgroup v2, dan kernel version gate di init.
> Android 11 **tidak** mensyaratkan PSI, eBPF, atau cgroup v2.

Pushed ke: https://github.com/rigaz29/kernel_oppo_msm8939/tree/lineage-18.1

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
- [ ] Verifikasi semua 328 file di `proprietary-files.txt` masih ada dan benar path-nya

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
- [ ] `init.recovery.qcom.rc`:
  - [ ] Cek kompatibilitas dengan recovery 18.1

---

## Fase 8 — Build Manifest (`A37.xml`)

**Usaha: Kecil** | **Risiko: Rendah**

- [ ] Update semua `revision` ke branch `lineage-18.1`
- [ ] `hardware/sony/timekeep` → `lineage-18.1`
- [ ] Cek apakah `external/stlport` masih diperlukan (kemungkinan tidak)
- [ ] `device/qcom/sepolicy-legacy` sudah di-handle oleh snippet LOS (branch `lineage-18.1-legacy`)
- [ ] Repo init: `repo init -u https://github.com/LineageOS/android.git -b lineage-18.1`

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
| lmkd crash | `ro.lmk.use_psi=false` belum diset (kernel 3.10 tanpa PSI) |

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

---

*Dokumen ini hidup — update status checkbox seiring progress.*
