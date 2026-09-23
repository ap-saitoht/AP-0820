##################################################
# AP-0820 WiFi コマンドテスト スクリプト 2026/4/3
################################################## 初期設定
$ErrorActionPreference = "stop"   #エラー発生時にスクリプトを中断

# AP-0820の設定
$HostIp = "AP-0820.local"   #IPアドレスまたは、ホスト名
$Port = 9004

# 動作設定
$RecvTimeout = 5000 #受信タイムアウト ms（無制限は0）
$BufSize = 1024     #受信バッファサイズ byte

################################################## 関数定義
#---+---+---+---+---+---+---+---+---+---+ ネットワーク接続処理
Function OpenFnc() {
    Write-Host "ネットワーク接続中...（HostIp=$HostIp Port=$Port）"
    While ($true) {
        Try {
            $TcpClient.Connect($HostIp, $Port)  #TCPクライアント接続（IPアドレス, ポート番号）
            Break
        } Catch {
            Write-Host "接続タイムアウト。リトライします。" -ForegroundColor Red
            Start-Sleep -s 5
            Continue
        }
    }
}

#---+---+---+---+---+---+---+---+---+---+ ネットワーク切断処理
Function CloseFnc() {
    Write-Host "ネットワークを切断します。"
    Try {
        $TcpClient.Client.Shutdown([System.Net.Sockets.SocketShutdown]::Both)
    } Catch {}
    $TcpClient.Close()
    $TcpClient.Dispose()
}

#---+---+---+---+---+---+---+---+---+---+ 送信処理
Function SendSub ($Str) {
    Write-Host "送信：$Str"
    $Bytes = [System.Text.Encoding]::Default.GetBytes("$Str")  #SJISバイトエンコード
    $TcpClient.GetStream().Write($Bytes, 0, $Bytes.Length)  #送信（バッファ, オフセット, データサイズ）
}

#---+---+---+---+---+---+---+---+---+---+ 受信処理
Function RecvSub () {
    Write-Host -NoNewline "受信："

    # 受信待ち
    while (-not $TcpClient.GetStream().DataAvailable) { Start-Sleep -m 1 }

    [byte[]]$Bytes = new-object byte[] $BufSize  #バイト配列を作成
    $RecvSize = 0

    Do {
        Try {
            $RecvSize += $TcpClient.GetStream().Read($Bytes, $RecvSize, $BufSize - $RecvSize)  #受信（バッファ, オフセット, サイズ）
        } Catch {
            Write-Host "受信タイムアウトが発生しました。" -ForegroundColor Yellow
            Break
        }
    } While ($Bytes[$RecvSize - 1] -ne 13)  #CRが来るまでループ

    If ($RecvSize -gt 0) {
        $Str = [System.Text.Encoding]::Default.GetString($Bytes, 0, $RecvSize)  #バイト配列からSJISエンコード（バッファ, オフセット, データサイズ）
        $Str = $Str.Replace([char]0x1b, '･')
    } Else {
        $Str = ""
    }
    Return $Str
}

################################################## イニシャル処理
Write-Host "AP-0820 WiFiコマンドテスト を開始します。"
Write-Host "CTRL+C を入力すると終了します。"
$ExitFlag = $true

##################################################メイン処理（CTRL+Cで終了）
#TCPクライアント接続
$TcpClient = New-Object System.Net.Sockets.TcpClient
$TcpClient.ReceiveTimeout = $RecvTimeout
OpenFnc #接続処理
Write-Host "接続しました。$(Get-Date -Format 'yyyy/MM/dd HH:mm:ss')"

Try {
    #---+---+---+---+---+---+---+---+---+---+ ループ処理
    While($ExitFlag) {
        $cmd = Read-Host "コマンド入力 (end で終了)"
        If ($cmd -match 'end') { break }

        SendSub "$cmd`r"    #送信
        $recvStr = RecvSub  #受信
        Write-Host $recvStr #受信ステータス＆データ表示
    }

} Catch {
    #---+---+---+---+---+---+---+---+---+---+ エラー処理
    If ($_.Exception.Message -ne "ScriptHalted") {
        $Error[0] | Out-string | Write-Host -ForegroundColor Red
    }

} Finally {
    CloseFnc  #切断処理
}

################################################## 終了処理
Write-Host "処理終了[Enter]" -NoNewline
$null = Read-Host
Exit
################################################## End Of File