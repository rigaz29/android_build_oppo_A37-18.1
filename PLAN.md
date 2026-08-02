# Rencana Porting LineageOS 18.1 — OPPO A37f (MSM8916)

> **Status:** Perencanaan
> **Target:** LineageOS 18.1 (Android 11) untuk OPPO A37 / A37f / A37fw
> **Baseline:** LineageOS 17.1 (Android 10) yang sudah terbukti boot sampai homescreen (28 Juli 2026)
> **Chipset:** Qualcomm MSM8916 (Snapdragon 410), kernel 3.10.108, 2 GB RAM, Adreno 306

---

## Sumber Daya

| Repo | Branch Asal | Branch Target |
|---|---|---|
| `rigaz29/rb_device_oppo_A37` | `rb` (pin `547f8ca`) | `lineage-18.1` (baru) |
| `rigaz29/kernel_oppo_msm8939` | `lz4-backport` (pin `70ef81d`) | `lineage-18.1` (baru, dari `lz4-backport` + cherry-pick `a12-prep`) |
| `meghs-playground/rb-vendor_oppo_A37` | `lineage-17.1` (pin `6a64435`) | `lineage-18.1` (baru) |
| `LineageOS/android_hardware_sony_timekeep` | `lineage-17.1` | `lineage-18.1` |
| `LineageOS/android_external_stlport` | `lineage-15.1` | Cek apakah masih diperlukan |

Build manifest: `rigaz29/android_build_oppo_A37` → `A37.xml` (update semua revision)

---

## Fase 1 — Kernel

**Usaha: Kecil** | **Risiko: Rendah** (sudah diverifikasi build-clean di a12-prep)

Branch `a12-prep` punya 4 commit di atas `70ef81d` yang dibuat untuk persiapan LOS 19.1.
Keempatnya sudah diverifikasi build Image + System.map bersih, tapi **belum pernah di-flash**.

> **Kenapa a12-prep gagal boot Android 12 tapi tetap aman di-cherry-pick untuk 18.1?**
> Ke-4 commit hanya mengubah defconfig dan perubahannya benar (QUOTA, MEMCG,
> disable LMK memang wajib untuk Android 11 maupun 12). Yang membuat Android 12
> gagal boot adalah kernel 3.10 secara arsitektural kekurangan fitur yang Android 12
> wajibkan: PSI (baru ada di kernel 4.20+), eBPF (untuk network traffic control),
> cgroup v2 (3.10 hanya punya v1), dan kernel version gate di init yang menolak
> boot di bawah 4.9. Masalah-masalah itu tidak bisa diperbaiki lewat defconfig.
> Android 11 **tidak** mensyaratkan PSI, eBPF, atau cgroup v2, sehingga kernel 3.10
> + 4 commit defconfig sudah cukup untuk LOS 18.1.

- [ ] Buat branch `lineage-18.1` dari `lz4-backport` (70ef81d)
- [ ] Cherry-pick 4 commit dari `a12-prep`:
  - [ ] `CONFIG_BLK_DEV_LOOP` — sudah `=y` di base defconfig, kemungkinan no-op
  - [ ] `CONFIG_QUOTA` — wajib untuk vold quota-based storage accounting
  - [ ] `CONFIG_MEMCG` — wajib untuk lmkd dan ActivityManager Android 11
  - [ ] Disable `CONFIG_ANDROID_LOW_MEMORY_KILLER` — ganti ke lmkd userspace
- [ ] Build Image + DTB, verifikasi tidak ada error
- [ ] (Opsional) Flash test terpisah sebelum integrasi penuh

**Catatan:** Kernel tetap 3.10.108. Tidak perlu naik ke 4.x — device MSM8916 lain
(Lenovo A6010, Xiaomi Redmi 2) sudah terbukti boot Android 11 dengan kernel 3.10.

---

## Fase 2 — Device Tree: File Konfigurasi Utama

**Usaha: Sedang** | **Risiko: Sedang**

### 2a. `BoardConfig.mk`

- [ ] Tambah `BUILD_BROKEN_ELF_PREBUILTS := true`
- [ ] Tambah `BOARD_VNDK_VERSION := current`
- [ ] Hapus `PRODUCT_VENDOR_MOVE_ENABLED := true` (deprecated di 18.1)
- [ ] Cek path sepolicy: `device/qcom/sepolicy-legacy` → mungkin tidak ada di 18.1.
  Jika gagal, ganti ke `device/qcom/sepolicy` + set `BOARD_SEPOLICY_VERS`
- [ ] Tetap pertahankan:
  - `SELINUX_IGNORE_NEVERALLOWS := true`
  - `BOARD_KERNEL_CMDLINE += androidboot.selinux=permissive`
  - `BUILD_BROKEN_PHONY_TARGETS := true`
  - `BUILD_BROKEN_DUP_RULES := true`

### 2b. `lineage_A37.mk`

- [ ] Tambah `PRODUCT_SHIPPING_API_LEVEL := 19`
- [ ] Pastikan `product_launched_with_k.mk` masih ada di tree 18.1
- [ ] Sisanya tidak berubah (PRODUCT_DEVICE, fingerprint, dll.)

### 2c. `AndroidProducts.mk`

- [ ] Cek apakah format masih kompatibel dengan 18.1
- [ ] Pastikan `PRODUCT_MAKEFILES` dan `COMMON_LUNCH_CHOICES` benar

---

## Fase 3 — Device Tree: HAL & Packages (`device.mk`)

**Usaha: Sedang** | **Risiko: Tinggi** (VINTF mismatch = gagal boot)

### Update versi HAL

| HAL | 17.1 | 18.1 | Catatan |
|---|---|---|---|
| `android.hardware.health` | 2.0 | **2.1** | Wajib. Hapus impl+service lama, pasang yang baru |
| `android.hardware.drm` (clearkey) | 1.2 | **1.3** | `android.hardware.drm@1.3-service.clearkey` |
| `android.hardware.bluetooth.audio` | — | **2.0** | Baru di Android 11. Tambah `@2.0-impl` |
| `android.hardware.authsecret` | — | **1.0** | Baru. Tambah `@1.0-service` |
| `android.hardware.fastboot` | — | **1.0** | Tambah `fastbootd` + `@1.0-impl-mock` |

### Hapus / ganti

- [ ] `android.hardware.wifi@1.0-service.legacy` → `android.hardware.wifi@1.0-service`
- [ ] Hapus `InProcessNetworkStack` (tidak ada di 18.1)
- [ ] Hapus `PRODUCT_DISABLE_SCUDO := true` (flag tidak ada lagi)
- [ ] Cek `android.hardware.usb@1.0-service.cyanogen_8916` — jika tidak ada di 18.1,
  ganti ke `android.hardware.usb@1.0-service`
- [ ] ConfigStore: jangan pasang `android.hardware.configstore@1.1-service` (deprecated)

### Tambah

- [ ] `vndservicemanager`
- [ ] `android.hardware.bluetooth.audio@2.0-impl`
- [ ] `android.hardware.authsecret@1.0-service`
- [ ] `fastbootd` + `android.hardware.fastboot@1.0-impl-mock`

### Properti

- [ ] Tambah `ro.control_privapp_permissions=enforce`
- [ ] Tambah `ro.telephony.iwlan_operation_mode=legacy`
- [ ] Cek semua `PRODUCT_PROPERTY_OVERRIDES` — yang vendor-specific sebaiknya
  pindah ke `PRODUCT_VENDOR_PROPERTIES` (deprecated tapi masih jalan di 18.1)
- [ ] VNDK: `libbase-v28.so` → `libbase-v30.so` (path prebuilts/vndk/v30/)

---

## Fase 4 — VINTF Manifest (`manifest.xml`)

**Usaha: Sedang** | **Risiko: Tinggi** (harus sinkron dengan device.mk)

### Update versi

```
android.hardware.audio:            5.0 → 6.0
android.hardware.audio.effect:     5.0 → 6.0
android.hardware.bluetooth:        1.0 → 1.1
android.hardware.health:           2.0 → 2.1
android.hardware.wifi:             1.3 → 1.4
android.hardware.wifi.hostapd:     1.1 → 1.2
android.hardware.wifi.supplicant:  1.2 → 1.3
android.hardware.gnss:             1.0 → 2.0 (atau tetap 1.0, tambah 2.0)
android.hardware.drm:              tambah fqname @1.3
```

### Tambah entri baru

```xml
android.hardware.bluetooth.audio@2.0
android.hardware.authsecret@1.0
android.hardware.fastboot@1.0
```

### Hapus

```xml
android.hardware.configstore   <!-- deprecated di Android 11 -->
```

### Aturan sinkronisasi

> Setiap `<hal>` di manifest.xml HARUS punya pasangan di `PRODUCT_PACKAGES` (device.mk).
> Jika manifest mendeklarasikan `audio@6.0` tapi yang di-build `audio@5.0-impl`,
> VINTF check gagal → device tidak boot.

---

## Fase 5 — SEPolicy

**Usaha: Besar** | **Risiko: Sedang** (permissive dulu, enforce nanti)

Android 11 menambah banyak domain, type, dan neverallow rule baru.

### File baru yang perlu dibuat

- [ ] `hal_authsecret_default.te`
- [ ] `hal_bluetooth_audio_default.te`
- [ ] `hal_health_2_1.te` (atau update `hal_health_default.te`)
- [ ] `hal_fastboot_default.te`

### File yang perlu di-update

- [ ] `vendor_init.te` — banyak type/attribute baru
- [ ] `init.te` — domain baru untuk service Android 11
- [ ] `system_server.te` — permission baru
- [ ] `vold.te` — quota, metadata partition
- [ ] `file_contexts` — path binary HAL baru
- [ ] `property_contexts` — properti baru Android 11
- [ ] `genfs_contexts` — filesystem type baru
- [ ] `seapp_contexts` — cek format baru

### Strategi

1. Boot dengan `androidboot.selinux=permissive` + `SELINUX_IGNORE_NEVERALLOWS := true`
2. Kumpulkan `avc: denied` dari `dmesg` / `logcat`
3. Perbaiki bertahap, domain per domain
4. Target akhir: `enforcing` (tapi ini bisa menyusul setelah semua fitur jalan)

---

## Fase 6 — Vendor Blobs (`vendor/oppo`)

**Usaha: Sedang** | **Risiko: Sedang**

- [ ] Fork branch `lineage-17.1` → `lineage-18.1`
- [ ] Update `A37-vendor.mk`:
  - [ ] Path `$(TARGET_COPY_OUT_SYSTEM)/etc/` → `$(TARGET_COPY_OUT_VENDOR)/etc/`
    untuk file yang seharusnya di partisi vendor
  - [ ] `libbase-v28.so` → `libbase-v30.so`
- [ ] Cek prebuilt HIDL services terhadap library yang berubah:
  - [ ] `perf@1.0-service`
  - [ ] `iop@1.0/2.0`
  - [ ] `bluetooth@1.0-service-qti`
  - [ ] `time_daemon`
  - [ ] DRM Widevine blob (mungkin perlu update untuk `drm@1.3`)
- [ ] Verifikasi semua 328 file di `proprietary-files.txt` masih ada dan benar path-nya

---

## Fase 7 — Init Scripts & Rootdir

**Usaha: Sedang** | **Risiko: Sedang**

- [ ] `fstab.qcom`:
  - [ ] Cek flag `fileencryption=` / `encryptable=`
  - [ ] Tambah entri `metadata` partition jika diperlukan
- [ ] `init.target.rc` / `init.qcom.rc`:
  - [ ] Android 11 lebih ketat: `mkdir`, `chown`, `chmod` harus di phase yang benar
  - [ ] Service baru perlu `seclabel` yang sesuai
  - [ ] Cek trigger `on property:` yang berubah
- [ ] `ueventd.qcom.rc`:
  - [ ] Permission node device mungkin perlu update
- [ ] `init.recovery.qcom.rc`:
  - [ ] Cek kompatibilitas dengan recovery 18.1

---

## Fase 8 — Build Manifest (`A37.xml`)

**Usaha: Kecil** | **Risiko: Rendah**

- [ ] Update semua `revision` ke branch `lineage-18.1`
- [ ] `hardware/sony/timekeep` → `lineage-18.1`
- [ ] Cek apakah `external/stlport` masih diperlukan (kemungkinan tidak)
- [ ] Tambah `device/qcom/sepolicy` jika roomservice tidak otomatis ambil
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
| Wi-Fi tidak jalan | `wifi@1.0-service` (bukan `.legacy`) perlu config berbeda |
| Audio mati | `audio@6.0` butuh `audio_policy_configuration.xml` format baru |
| Kamera crash | Blob HAL1 vs framework Android 11 — cek `camera.provider@2.4` |
| SIM tidak terdeteksi | RIL blob vs `radio@1.0` — mungkin perlu update manifest |
| Bluetooth gagal | `bluetooth@1.1` vs prebuilt `bluetooth@1.0-service-qti` |

---

## Urutan Pengerjaan

```
Fase 1 (Kernel)
    │
    ▼
Fase 2 (BoardConfig, lineage_A37.mk)
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

Hal-hal berikut sudah benar di 17.1 dan tidak perlu dimodifikasi:

- Arsitektur: tetap 32-bit (`TARGET_ARCH := arm`, `cortex-a53`)
- `TARGET_USES_64_BIT_BINDER := true`
- Kernel base/tags/ramdisk offset
- Display: gralloc, hwcomposer, memtrack (versi HAL tetap)
- Camera HAL1 legacy path
- Power HAL `power@1.0` (masih diterima di 18.1)
- Sensors `@1.0` passthrough
- Vibrator `@1.0`
- Keymaster `@3.0`
- `ro.product.first_api_level=19`
- Dalvik VM tuning (heapgrowthlimit 192m, dll.)
- LZ4 zram compression
- Interactive governor tuning
- Double-tap-to-wake (Synaptics OPPO driver)

---

*Dokumen ini hidup — update status checkbox seiring progress.*
