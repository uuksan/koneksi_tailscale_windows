# KoranKu — Website Penjualan Koran Digital

Website sederhana (single HTML) untuk penjualan koran digital, disajikan lewat server Node statis dan dipublikasikan ke internet menggunakan Tailscale Funnel.

**URL publik:** https://asus.tail89c518.ts.net/

## Struktur

| File | Fungsi |
|---|---|
| `index.html` | Seluruh website (tampilan + logika keranjang) |
| `server.js` | Server web statis, listen di `localhost:8080` |
| `site.ps1` / `site.cmd` | Script kontrol layanan |

## Kontrol Layanan

Jalankan dari folder ini:

```
site.cmd start     # nyalakan server + funnel → situs online
site.cmd stop      # matikan funnel + server → situs offline
site.cmd status    # cek status server lokal & funnel publik
site.cmd monitor   # lihat pemakaian RAM & CPU layanan + sistem
```

## Prasyarat

- Node.js (menjalankan `server.js`)
- Tailscale sudah login dan Funnel diaktifkan di tailnet

## Catatan

- Setelah restart komputer, jalankan `site.cmd start` lagi.
- Situs hanya bisa online jika komputer ini menyala dan terhubung internet.
