# site.ps1 - Kelola layanan website KoranKu (server lokal + Tailscale Funnel)
# Cara pakai:
#   powershell -ExecutionPolicy Bypass -File site.ps1 start
#   powershell -ExecutionPolicy Bypass -File site.ps1 stop
#   powershell -ExecutionPolicy Bypass -File site.ps1 status
#   powershell -ExecutionPolicy Bypass -File site.ps1 monitor

param(
    [Parameter(Position = 0)]
    [ValidateSet("start", "stop", "status", "monitor")]
    [string]$Command = "status"
)

$ErrorActionPreference = "SilentlyContinue"
$Root = $PSScriptRoot
$Port = 8080
$FunnelUrl = "https://asus.tail89c518.ts.net/"

function Test-PortOpen {
    $conn = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
    return $null -ne $conn
}

function Get-ServerPids {
    Get-CimInstance Win32_Process -Filter "Name='node.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like "*server.js*" } |
        Select-Object -ExpandProperty ProcessId
}

function Get-FunnelPids {
    Get-Process tailscale -ErrorAction SilentlyContinue |
        Where-Object { $_.Id -ne (Get-Process tailscaled -ErrorAction SilentlyContinue).Id } |
        Where-Object { (Get-CimInstance Win32_Process -Filter "ProcessId=$($_.Id)").CommandLine -like "*funnel*" } |
        Select-Object -ExpandProperty Id
}

function Show-ProcStats($pids, $label) {
    $rows = foreach ($procId in $pids) {
        $p = Get-Process -Id $procId -ErrorAction SilentlyContinue
        if ($p) {
            [PSCustomObject]@{
                Layanan = $label
                PID     = $p.Id
                RAM_MB  = [math]::Round($p.WorkingSet64 / 1MB, 1)
                CPU_Sek = [math]::Round($p.TotalProcessorTime.TotalSeconds, 1)
            }
        }
    }
    return $rows
}

switch ($Command) {

    "start" {
        # 1. Server Node lokal
        if (Test-PortOpen) {
            Write-Host "[OK]  Server lokal sudah jalan di port $Port" -ForegroundColor Green
        } else {
            Start-Process node -ArgumentList "server.js" -WorkingDirectory $Root -WindowStyle Hidden
            Start-Sleep -Seconds 2
            if (Test-PortOpen) {
                Write-Host "[OK]  Server lokal aktif di http://localhost:$Port" -ForegroundColor Green
            } else {
                Write-Host "[ERR] Gagal menjalankan server Node. Cek server.js." -ForegroundColor Red
                exit 1
            }
        }

        # 2. Tailscale funnel (konfig tersimpan di tailnet; proses CLI hanya watcher)
        $status = tailscale funnel status 2>&1 | Out-String
        if ($status -match "https://") {
            Write-Host "[OK]  Funnel sudah aktif" -ForegroundColor Green
        } else {
            Start-Process tailscale -ArgumentList "funnel", "$Port" -WindowStyle Hidden
            Start-Sleep -Seconds 4
            Write-Host "[OK]  Funnel diaktifkan" -ForegroundColor Green
        }
        Write-Host ""
        Write-Host "Website live: $FunnelUrl" -ForegroundColor Cyan
    }

    "stop" {
        # 1. Matikan funnel
        tailscale funnel reset 2>&1 | Out-Null
        foreach ($fp in Get-FunnelPids) { Stop-Process -Id $fp -Force -ErrorAction SilentlyContinue }
        Write-Host "[OK]  Funnel dinonaktifkan (akses publik mati)" -ForegroundColor Yellow

        # 2. Matikan server Node
        $pids = Get-ServerPids
        if ($pids) {
            foreach ($procId in $pids) { Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue }
            Write-Host "[OK]  Server Node dihentikan" -ForegroundColor Yellow
        } else {
            Write-Host "[--]  Server Node tidak berjalan" -ForegroundColor Gray
        }
    }

    "status" {
        Write-Host "=== Status Layanan KoranKu ===" -ForegroundColor Cyan
        if (Test-PortOpen) {
            Write-Host "[ON ] Server lokal (port $Port)" -ForegroundColor Green
        } else {
            Write-Host "[OFF] Server lokal (port $Port)" -ForegroundColor Red
        }
        $status = tailscale funnel status 2>&1 | Out-String
        if ($status -match "(https://\S+ts\.net\S*)") {
            Write-Host "[ON ] Funnel publik: $($Matches[1])" -ForegroundColor Green
        } else {
            Write-Host "[OFF] Funnel publik belum aktif" -ForegroundColor Red
        }
    }

    "monitor" {
        Write-Host "=== Penggunaan RAM & CPU ===" -ForegroundColor Cyan
        $serverPids = Get-ServerPids
        $rows = @()
        if ($serverPids) { $rows += Show-ProcStats $serverPids "Web server (node)" }
        $tsd = Get-Process tailscaled -ErrorAction SilentlyContinue
        if ($tsd) { $rows += Show-ProcStats $tsd.Id "Tailscale daemon" }
        $tsui = Get-Process tailscale-ipn -ErrorAction SilentlyContinue
        if ($tsui) { $rows += Show-ProcStats $tsui.Id "Tailscale app" }

        if ($rows.Count -gt 0) {
            $rows | Format-Table -AutoSize
            $totalRam = ($rows | Measure-Object RAM_MB -Sum).Sum
            Write-Host ("Total RAM layanan ini: {0} MB" -f $totalRam) -ForegroundColor Cyan
        } else {
            Write-Host "Tidak ada layanan yang berjalan. Jalankan: site.ps1 start" -ForegroundColor Yellow
        }

        # Ringkasan sistem
        $os = Get-CimInstance Win32_OperatingSystem
        $ramPakai = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1KB, 0)
        $ramTotal = [math]::Round($os.TotalVisibleMemorySize / 1KB, 0)
        $cpuBeban = (Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
        Write-Host ""
        Write-Host ("Sistem: RAM {0} MB / {1} MB terpakai | CPU {2}%" -f $ramPakai, $ramTotal, $cpuBeban) -ForegroundColor Gray
    }
}
