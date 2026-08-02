# Rencana — LineageOS 18.1 (Android 11) untuk OPPO A37

Status: **rencana, belum dikerjakan.** Ditulis 2 Agustus 2026.

Build kit di `/root/a37-18.1`. Source tree nanti di `/root/los18`.

---

## Kenapa 18.1, dan kenapa sekarang

Percobaan 19.1 sebelumnya berhasil menghasilkan ROM yang terbangun, lalu **stuck di logo
OPPO** dan dihentikan. Sepanjang percobaan itu saya memverifikasi sumber tiga versi
sekaligus, dan hasilnya menunjuk 18.1 sebagai titik yang jauh lebih murah — bukan tebakan,
melainkan pembacaan kode:

| Kebutuhan | 18.1 (Android 11) | 19.1 (Android 12) |
|---|---|---|
| Gerbang eBPF di `bpfloader` | **ada** — `BpfLoader.cpp:83` `if (!isBpfSupported()) return 0;` | dibuang |
| Penjaga eBPF di `netd` | **ada** — `TrafficController.cpp:252` + 9 titik lain | dibuang; `Controllers.cpp` `sleep(60); exit(1)` |
| sdcardfs | dipakai (`Utils.cpp:1010`) | dipakai juga |
| FDE (`encryptable=footer`) | ada (`vold/cryptfs.cpp`) | ada juga |
| lmkd | `use_inkernel_interface = true`, PSI opsional | sama |
| `sysfs_disk_stat` | **dideklarasikan** di `system/sepolicy/public/file.te` | dibuang AOSP |
| `libbfqio` | **ada** di `vendor/lineage` | dibuang |

Empat baris pertama itu yang menentukan: di 18.1 **tidak perlu W1 maupun W2 sama sekali**.
Kernel 3.10 tanpa syscall `bpf` sudah ditangani oleh gerbang bawaan, tanpa fork
`system/bpf`, tanpa fork `system/netd`, tanpa properti `ro.kernel.ebpf.supported`.

Dua baris terakhir mencoret dua perbaikan lain yang kemarin harus dibuat sendiri.

---

## Yang sudah diverifikasi tersedia

Semua dicek 2 Agustus 2026, bukan diasumsikan:

| Komponen | Sumber | Branch |
|---|---|---|
| device tree | `meghs-playground/rb_device_oppo_A37` | `lineage-18.1` (commit terakhir 31 Jan 2024) |
| vendor | `meghs-playground/rb-vendor_oppo_A37` | `lineage-18.1` — **repo yang sama dengan 17.1**, dan 18.1 adalah branch terbarunya |
| kernel | `rigaz29/kernel_oppo_msm8939` | `a12-prep` (lihat catatan di bawah) |
| audio/display/media CAF | `LineageOS/android_hardware_qcom_*` | `lineage-18.1-caf-msm8916` |
| sepolicy legacy | `LineageOS/android_device_qcom_sepolicy` | `lineage-18.1-legacy` — **repo resmi**, tidak perlu fork LineageOS-UL |
| timekeep | `LineageOS/android_hardware_sony_timekeep` | `lineage-18.1` |
| stlport | `LineageOS/android_external_stlport` | `lineage-15.1` (tidak punya branch 18.1) |

---

## Beda struktural yang harus ditangani di manifest

**18.1 memakai `hardware/qcom/<komponen>`, bukan `hardware/qcom-caf/<soc>/<komponen>`.**
Manifest 18.1 sudah menyediakan `hardware/qcom/audio`, `display`, dan `media` tanpa revisi
eksplisit (ikut default branch). Untuk MSM8916 ketiganya harus diarahkan ke varian CAF, jadi
polanya **bukan menambah project baru** seperti di 19.1, melainkan `<remove-project>` lalu
daftarkan ulang dengan branch `lineage-18.1-caf-msm8916`.

**`device/qcom/sepolicy-legacy` tetap tidak ada di manifest**, padahal `BoardConfig.mk:182`
meng-include `sepolicy.mk` dari sana. Bedanya dengan 19.1: untuk 18.1 sumbernya ada di repo
resmi LineageOS, jadi tidak perlu bergantung pada fork pihak ketiga.

---

## Kernel: pakai `a12-prep` apa adanya

Branch `a12-prep` di `rigaz29/kernel_oppo_msm8939` (5 commit di atas `70ef81d`) dipakai
langsung. Namanya menyesatkan untuk proyek 18.1, tapi isinya relevan:

| Commit | Untuk 18.1 |
|---|---|
| `BLK_DEV_LOOP_MIN_COUNT` 8 → 32 | **wajib** — Android 11 juga memasang banyak APEX, dan default 8 membuat `apexd` gagal |
| `CONFIG_QUOTA` + `QFMT_V2` | berguna (statistik penyimpanan installd) |
| `CONFIG_MEMCG` | berguna, tidak wajib |
| matikan LMK in-kernel | **opsional** — lmkd A11 masih mendukung antarmuka in-kernel (`use_inkernel_interface = true`) |
| `Makefile` `mkdir -p` output soong | **wajib** — soong menghapus direktori `gen` lalu memanggil `make O=<gen>`; kernel 3.10 tidak membuatnya sendiri |

Kalau nanti perlu memisahkan, commit LMK adalah satu-satunya yang bisa dilepas tanpa
konsekuensi build (`49766c1` = tanpa dia).

---

## Cacat device tree: enam gugur, dua tersisa

Delapan cacat yang kemarin menghalangi build 19.1 sudah saya periksa langsung ke tree 18.1:

| Cacat 19.1 | Di 18.1 |
|---|---|
| `libshims_ril` kembar `.mk`/`.bp` | **tidak ada** |
| `init.recovery.qcom.rc` kembar | **tidak ada** (hanya satu definisi) |
| `libbfqio` hilang | **tidak berlaku** — masih ada di `vendor/lineage` 18.1 |
| `sysfs_disk_stat` tidak terdeklarasi | **tidak berlaku** — masih ada di `system/sepolicy` |
| spesifikasi gatekeeper kembar | **tidak ada** di `sepolicy/private/` |
| kernel tidak membuat direktori output | **berlaku** — sudah tertangani di `a12-prep` |
| `power_profile.xml` diawali `0x0a` | **ADA** — perbaikannya satu byte |
| properti bentrok nilai | **ADA** — 3 pasang (19.1 punya 4) |

Jadi tree 18.1 memang lebih sering dilalui orang. Dua yang tersisa sudah diketahui bentuk
perbaikannya persis, jadi bukan lagi penemuan melainkan penerapan.

---

## Perbedaan pendekatan dari percobaan 19.1

Kemarin kelima belas commit `rb` ditumpuk ke basis 19.1 **sebelum** build pertama. Akibatnya
ketika ROM stuck di logo, tersangkanya ada dua puluh sekaligus dan tidak ada titik pijak.

Kali ini dibalik:

1. **Bangun sestok dulu** — device tree 18.1 apa adanya, hanya dengan dua perbaikan yang
   memang menghalangi build. Flash. Cari tahu apakah boot.
2. **Baru port perbaikan `rb`** satu per satu di atas basis yang sudah terbukti boot.

Kalau boot pertama gagal, tersangkanya sedikit dan lognya bermakna. Kalau berhasil, tiap
commit `rb` yang ditambahkan punya baseline untuk dibandingkan.

---

## Langkah

1. **Siapkan build kit** di `/root/a37-18.1`: `A37.xml` (manifest 18.1 sesuai tabel di atas),
   dan `build.sh` diadaptasi dari `/root/a37/build.sh` (`BRANCH="lineage-18.1"`).
2. `repo init -b lineage-18.1 --git-lfs` ke `/root/los18`, pasang local manifest, `repo sync`.
   Disk bebas 278 GB — cukup, tidak perlu `--reference` maupun menghapus apa pun.
3. `lunch lineage_A37-eng`. Kalau gagal, perbaiki dan catat — pola kegagalannya sudah
   dikenali dari 19.1.
4. `m bacon`. Dua cacat yang diperkirakan (`power_profile.xml`, properti bentrok) diperbaiki
   saat muncul, di fork `rigaz29/rb_device_oppo_A37` branch baru untuk 18.1.
5. Flash. **Backup `boot.img` yang terpasang lebih dulu** — ROM 17.1 di `/root/a37-dl`
   adalah jalan pulang.
6. Kalau stuck: boot ke recovery 18.1 (kernelnya sama persis dengan `boot.img`, jadi langsung
   memisahkan kernel dari userspace), lalu ambil ramoops lewat reboot hangat
   (`/sys/fs/pstore/console-ramoops-0`). Kernel sudah punya `CONFIG_PSTORE_RAM` dan cmdline
   membawa `ramoops.mem_address=0x9ff00000`.

---

## Yang tetap tidak dijanjikan

Verifikasi di atas semuanya soal **sumber**, bukan perangkat. Yang terbukti: 18.1 tidak
menuntut eBPF, komponennya tersedia, dan tree-nya lebih bersih. Yang **tidak** terbukti:
bahwa ROM-nya akan boot di A37.

19.1 juga "seharusnya bisa" sampai ia stuck di logo. Bedanya sekarang: empat blocker yang
kemarin harus ditambal sendiri memang tidak ada di jalur ini, dan kalau gagal, rencana
diagnosisnya sudah disiapkan di langkah 6 — bukan dipikirkan setelah gagal.

Perkiraan yang jujur: sampai ROM terbangun kemungkinan besar lancar. Boot pertama tetap
lemparan dadu, sama seperti kemarin.
