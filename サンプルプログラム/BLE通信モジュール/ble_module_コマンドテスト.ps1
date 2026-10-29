# AP-0820 BLE コマンド動作テスト　2026/10/26
#
# バックグラウンドにてBLEモジュールプログラムを起動し、入力したコマンドの送信およびステータスを受信します。

$deviceName = "AP-0820"  # デバイス名
#$enc = New-Object System.Text.UTF8Encoding $false  # UTF-8の場合
$enc = [System.Text.Encoding]::GetEncoding("shift_jis")  # shift-jisの場合

# BLEモジュール起動
$psi = New-Object System.Diagnostics.ProcessStartInfo

# exeを起動する場合
#$psi.FileName = "$PSScriptRoot\ble_module.exe"
#$psi.Arguments = "`"$deviceName`""
# pythonを起動する場合
$psi.FileName = "python"
$psi.Arguments = "`"$PSScriptRoot\ble_module.py`" `"$deviceName`""

$psi.UseShellExecute = $false
$psi.RedirectStandardInput = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.CreateNoWindow = $true

Write-Host "$deviceName 接続中..." -ForegroundColor Cyan
$process = [System.Diagnostics.Process]::Start($psi)
$writer = new-object System.IO.StreamWriter $process.StandardInput.BaseStream, $enc
$reader = new-object System.IO.StreamReader $process.StandardOutput.BaseStream, $enc

$loopFlag = $true

# BLEモジュール起動確認
Start-Sleep -Seconds 1 # 起動待ち
if ($process.HasExited) {
    Write-Host "❌ BLEモジュールの起動にてエラーが発生しました。" -ForegroundColor Red
    $errMessage = $process.StandardError.ReadToEnd()
    Write-Host $errMessage -ForegroundColor Yellow
    $loopFlag = $false
}

# BLEモジュールの接続待ち
while ($process.HasExited -eq $false -and $loopFlag) {
    $resStr = $reader.ReadLine()
    if (-not [string]::IsNullOrEmpty($resStr)) {
        Write-Host "➔ $resStr" -ForegroundColor Green
        if ($resStr -eq "READY") {
            Write-Host "接続完了。" -ForegroundColor Cyan
            break
        }
        if ($resStr -match "ERROR") {
            $loopFlag = $false
            break
        }
    }
}

# ---------------------------------------------------------
# メインループ
while ($process.HasExited -eq $false -and $loopFlag) {
    $cmd = Read-Host "送信コマンド(未入力で終了)"
    if ([string]::IsNullOrWhiteSpace($cmd)) { break }

    # コマンド送信
    $writer.WriteLine($cmd)  # 改行（CR+LF）を付与して送信
    $writer.Flush()

    # ステータス受信
    $resStr = $reader.ReadLine()
    if (-not [string]::IsNullOrEmpty($resStr)) {
        if ($resStr.StartsWith(":")) {
            Write-Host "➔ 受信ステータス: $($resStr.Substring(1).Replace([char]0x1b, '･'))" -ForegroundColor Green  # :の削除と ESCコードを置換して表示
        } else {
            Write-Host "➔ $resStr" -ForegroundColor Red
        }
    }
}

# 終了処理
$writer.Close()
$reader.Close()
$process.WaitForExit()
Write-Host "処理を終了しました。" -ForegroundColor Cyan
