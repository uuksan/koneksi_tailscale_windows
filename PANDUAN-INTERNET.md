# Panduan Menyambungkan Website ke Internet (Windows + Tailscale Funnel)

Tutorial langkah demi langkah untuk mempublikasikan website statis (misalnya KoranKu) ke internet dari komputer Windows Anda sendiri, tanpa hosting berbayar, menggunakan **Tailscale Funnel**.

Hasil akhir: website Anda online di `https://<nama-mesin>.<tailnet>.ts.net/` dan bisa diakses siapa saja dari browser mana pun.

---

## Ringkasan Cara Kerjanya

```
Pengunjung internet
      │  https://mesin.tailxxxx.ts.net  (publik, HTTPS)
      ▼
Tailscale Funnel  ──►  Tailscale di PC Anda (port 443)
      │  proxy lokal
      ▼
Server web statis (node server.js, port 8080)
      │
      ▼
Folder website (index.html, dst.)
```

Yang Anda butuhkan:
- Windows 10/11 dengan koneksi internet
- [Node.js](https://nodejs.org) (LTS) — untuk server statis
- Akun [Tailscale](https://tailscale.com) (gratis)

---

## Langkah 1 — Install Node.js

1. Buka https://nodejs.org, unduh installer **LTS** untuk Windows.
2. Jalankan installer, biarkan semua opsi default, klik *Next* sampai selesai.
3. Buka **Command Prompt** (Win+R → ketik `cmd` → Enter), verifikasi:

   ```cmd
   node --version
   ```

   Jika muncul versi (misal `v22.x.x`), Node.js sudah terpasang.

## Langkah 2 — Install Tailscale

1. Unduh dari https://tailscale.com/download/windows (atau lewat Microsoft Store).
2. Jalankan installer, biarkan default.
3. Setelah selesai, klik ikon Tailscale di system tray → **Log in** → browser terbuka, login dengan akun Google/Microsoft/GitHub atau akun tailnet Anda.
4. Verifikasi di Command Prompt:

   ```cmd
   tailscale status
   ```

   Harus muncul daftar perangkat tailnet Anda dan IP `100.x.x.x` milik mesin ini.

## Langkah 3 — Siapkan Server Web Statis

Buat folder website Anda (contoh: `C:\Users\<kamu>\website_koran`) yang berisi `index.html`, lalu buat file `server.js` di folder yang sama:

```js
const http = require("http");
const fs = require("fs");
const path = require("path");

const ROOT = __dirname;
const PORT = process.env.PORT || 8080;

const mime = {
  ".html": "text/html; charset=utf-8",
  ".css": "text/css",
  ".js": "text/javascript",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".svg": "image/svg+xml",
  ".ico": "image/x-icon"
};

http.createServer((req, res) => {
  let urlPath = decodeURIComponent(req.url.split("?")[0]);
  if (urlPath === "/") urlPath = "/index.html";
  const filePath = path.normalize(path.join(ROOT, urlPath));
  if (!filePath.startsWith(ROOT)) {
    res.writeHead(403); res.end("Forbidden"); return;
  }
  fs.readFile(filePath, (err, data) => {
    if (err) { res.writeHead(404); res.end("Not found"); return; }
    res.writeHead(200, { "Content-Type": mime[path.extname(filePath).toLowerCase()] || "application/octet-stream" });
    res.end(data);
  });
}).listen(PORT, () => console.log(`Serving ${ROOT} on http://localhost:${PORT}`));
```

Jalankan:

```cmd
cd C:\Users\<kamu>\website_koran
node server.js
```

Buka http://localhost:8080 di browser — website harus tampil. Biarkan jendela ini tetap terbuka (atau jalankan tersembunyi: `start /min node server.js`).

## Langkah 4 — Aktifkan Funnel di Tailnet (sekali saja)

Funnel harus diizinkan dulu di level tailnet:

1. Buka https://login.tailscale.com/admin → login.
2. Menu **Funnel** → klik **Enable funnel**.
3. Jika tailnet Anda memakai **Access Control (ACL)**, tambahkan aturan yang mengizinkan funnel, contoh:

   ```json
   { "Action": "accept", "Source": ["autogroup:member"], "Destination": ["autogroup:private(autogroup:self)"], "Proto": "tcp", "Args": ["tcp:443"] }
   ```

   Cara tercepat: di halaman enable Funnel, ikuti tautan *"update your ACLs"* dan terima perubahan yang disarankan Tailscale.

## Langkah 5 — Publikasikan dengan Funnel

Di Command Prompt (PowerShell juga bisa):

```cmd
tailscale funnel 8080
```

Perintah ini membuat proxy: `https://<mesin>.<tailnet>.ts.net` → `localhost:8080`.
Tunggu sampai muncul tulisan:

```
Available on the internet:

https://mesin.tailxxxx.ts.net/
|-- proxy http://127.0.0.1:8080
```

Cek URL yang diberikan, lalu buka dari perangkat lain (HP dengan data seluler, bukan WiFi yang sama) untuk memastikan akses publik berhasil.

> Konfigurasi funnel tersimpan di tailnet, jadi akses tetap ada meski jendela CLI ditutup. Yang harus tetap jalan hanyalah `node server.js` dan aplikasi Tailscale.

## Langkah 6 — Menghentikan / Mengubah

```cmd
tailscale funnel status    # cek konfigurasi saat ini
tailscale funnel 9090      # pindah ke port lain
tailscale funnel reset     # matikan akses publik
```

---

## Pemecahan Masalah

| Gejala | Penyebab & Solusi |
|---|---|
| `Funnel is not enabled on your tailnet` | Belum melakukan Langkah 4. Buka URL yang ditampilkan CLI dan enable. |
| HTTP 502 saat membuka URL publik | Server lokal mati. Pastikan `node server.js` jalan; cek `curl http://localhost:8080`. |
| `listener already exists for port 443` | Ada konfigurasi lama. Jalankan `tailscale serve reset` lalu ulangi `tailscale funnel 8080`. |
| `tailscale status` kosong/error | Aplikasi Tailscale belum login atau service `tailscaled` mati. Login ulang / restart dari system tray. |
| URL bisa dibuka tapi lama | Normal untuk Funnel (proxy Tailscale). Untuk produksi lebih serius, gunakan hosting statis. |
| Situs mati setelah restart PC | Jalankan lagi `node server.js`. Agar otomatis, buat Task Scheduler yang menjalankan Node + `tailscale funnel 8080` saat login. |

## Catatan Keamanan

- Server hanya mengekspor folder website; jangan taruh file rahasia (`.env`, kunci API) di folder yang sama.
- Port 8080 hanya listen di `127.0.0.1` via proxy Tailscale — tidak terbuka di jaringan lokal.
- Funnel = akses **publik tanpa login**. Semua orang yang tahu URL bisa melihat situs.

## Alternatif Sebanding

Jika tidak ingin PC menyala terus, situs statis seperti ini bisa di-host gratis di Cloudflare Pages, Netlify, atau GitHub Pages — tinggal upload `index.html`, tanpa perlu Tailscale.
