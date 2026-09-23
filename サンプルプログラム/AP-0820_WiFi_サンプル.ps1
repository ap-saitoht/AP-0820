##################################################
# AP-0820 WiFi サンプル スクリプト 2026/4/3
################################################## 初期設定
$ErrorActionPreference = "stop"   #エラー発生時にスクリプトを中断

# AP-0820の設定
$HostIp = "AP-0820.local"   #IPアドレスまたは、ホスト名
$Port = 9004            #ポート番号

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
Function SendFnc ($Str) {
    Write-Host "送信：$Str"
    $Bytes = [System.Text.Encoding]::Default.GetBytes("$Str")  #SJISバイトエンコード
    $TcpClient.GetStream().Write($Bytes, 0, $Bytes.Length)  #送信（バッファ, オフセット, データサイズ）
}

#---+---+---+---+---+---+---+---+---+---+ 受信処理
Function RecvFnc () {
    Write-Host -NoNewline "受信："
    [byte[]]$Bytes = new-object byte[] $BufSize  #バイト配列を作成
    $RecvSize = 0
    $EnqFlag = $false

    While ($true) {
        While ($true) {
            Try {
                $RecvSize += $TcpClient.GetStream().Read($Bytes, $RecvSize, $BufSize - $RecvSize)  #受信（バッファ, オフセット, サイズ）
                If ($RecvSize -eq 0) {
                    Write-Host "Socketが閉じられました。" -ForegroundColor Red
                    Throw  #処理終了
                }
                If ($Bytes[$RecvSize - 1] -eq 0x0d) { Break }  #データ末尾CR確認
            } Catch [System.IO.IOException] {
                If ($_.Exception.InnerException.SocketErrorCode -eq "TimedOut") {
                    If (-not $EnqFlag) {
                        [byte[]]$EnqCmd = @(0x05, 0x0d)  #応答確認ENQ
                        $TcpClient.GetStream().Write($EnqCmd, 0, 2)
                        $EnqFlag = $true
                    } Else {
                        Write-Host "機器からの応答がありません。" -ForegroundColor Red
                        Throw "ScriptHalted"
                    }
                } Else {
                    Write-Host "Socketエラー：$($_.Exception.InnerException.SocketErrorCode)" -ForegroundColor Red
                    Throw "ScriptHalted"
                }
            } Catch { Throw }
        }

        #接続応答確認
        If ($EnqFlag) {
            If ($RecvSize -ge 3) {
                If ($Bytes[0] -eq 0x1b -and $Bytes[1] -eq 0x06 -and $Bytes[2] -eq 0x0d) {   #先頭ACK確認
                    If ($RecvSize -eq 3) {
                        $RecvSize = 0
                    } Else {
                        $Bytes = $Bytes[3..($RecvSize-1)]
                        $RecvSize -= 3
                        Break
                    }
                } ElseIf ($Bytes[$RecvSize-3] -eq 0x1b -and $Bytes[$RecvSize-2] -eq 0x06 -and $Bytes[$RecvSize-1] -eq 0x0d) {  #末尾ACK確認
                    $RecvSize -= 3
                    Break
                }
            }
            $EnqFlag = $false
        } Else {
            Break
        }
    }
    
    $Str = [System.Text.Encoding]::Default.GetString($Bytes, 0, $RecvSize)  #SJISエンコード（バッファ, オフセット, データサイズ）
    Write-Host $Str.Replace([char]0x1b, '･')  #ESCを変換して表示
    Return $Str
}

#---+---+---+---+---+---+---+---+---+---+ ステータス処理
Function StatusFnc($stat) {
    If ($stat.Length -ge 3) {   #データが3バイト以上か確認
        If ($stat[0] -eq [char]0x1b) {  #先頭ESC確認
            Switch ($stat[1]) {
                "0" {
                    Write-Host "正常応答" -ForegroundColor Green
                }
                "?" {
                    Write-Host "読取エラー" -ForegroundColor Magenta
                }
                "C" {
                    Write-Host "コマンドエラー" -ForegroundColor Magenta
                }
                "W" {
                    Write-Host "書込エラー" -ForegroundColor Magenta
                }
                [char]0x06 {    #ACK
                    Write-Host "接続確認応答" -ForegroundColor Green
                }
                Default {
                    If ($stat.Length -eq 6) {
                        Write-Host "バッテリ電圧レベル" -ForegroundColor Green
                    } ElseIf ($stat.Length -eq 11) {
                        Write-Host "時刻タイマー" -ForegroundColor Green
                    } ElseIf ($stat.Length -eq 13) {
                        Write-Host "ファームウェアバージョン" -ForegroundColor Green
                    } Else {
                        Write-Host "その他ステータス" -ForegroundColor Magenta
                    }
                }
            }
            Return
        }
    }
    Write-Host "データ" -ForegroundColor Green
}

################################################## イニシャル処理
Write-Host "AP-0820 WiFiテスト を開始します。"
Write-Host "CTRL+C を入力すると終了します。"
$ExitFlag = $true

##################################################メイン処理（CTRL+Cで終了）
Do {
    #TCPクライアント接続
    $TcpClient = New-Object System.Net.Sockets.TcpClient
    $TcpClient.ReceiveTimeout = $RecvTimeout
    OpenFnc #接続処理
    Write-Host "接続しました。$(Get-Date -Format 'yyyy/MM/dd HH:mm:ss')"

    Try {
        #---+---+---+---+---+---+---+---+---+---+ ループ処理
        While($ExitFlag) {

            #送信コマンド
            $Commands = @(`
                "I`r"`          #装置リセット
                #,"A`r"`         #QRコード＆RFタグ読み取り待ち
                ,"F`r"`         #QRコード読み取り待ち
                ,"FU5`r"`       #RFIDインベントリ(RFタグ検出待ち 500ms間隔)
                ,"FR0005`r"`    #RFID読み取り（開始00ブロックから05ブロック読み取り）
                #,"W00abcd`r"`   #RFID書き込み（00ブロックから"abcd"を書き込み）
                ,"LA0777777`r"` #LED点灯（0番目から7個を白色に点灯）
                ,"B1`r"`        #ブザー鳴動（ブザーを1回鳴動）
                ,"M1`r"`        #バイブモーター振動（バイブを1回振動）
            )

            #送受信処理
            Foreach ($Cmd in $Commands) {
                SendFnc $Cmd        #送信
                $recvStr = RecvFnc  #受信
                StatusFnc $recvStr  #ステータス処理
            }

            Start-Sleep -s 1  #一時停止
        }

    } Catch {
        #---+---+---+---+---+---+---+---+---+---+ エラー処理
        If ($_.Exception.Message -ne "ScriptHalted") {
            $Error[0] | Out-string | Write-Host -ForegroundColor Red
        }
        Write-Host "再接続をしますか？[Y/N]" -ForegroundColor Yellow -NoNewline
        If ((Read-Host) -ne "y") { $ExitFlag = $false }

    } Finally {
        CloseFnc  #切断処理
    }
} While ($ExitFlag)

################################################## 終了処理
Write-Host "処理終了[Enter]" -NoNewline
$null = Read-Host
Exit
################################################## End Of File