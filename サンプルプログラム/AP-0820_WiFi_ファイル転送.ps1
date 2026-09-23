##################################################
# AP-0820 ファイルデータ転送 2026/6/5
################################################## 初期設定
$ErrorActionPreference = "SilentlyContinue"    #エラー発生時は無視

# AP-0820のネットワーク設定
$HostIp = "AP-0820.local"   #IPアドレスまたは、ホスト名
$Port = 9004            #ポート番号

$RecvTimeout = 5000 #受信タイムアウト ms（無制限は0）
$BufSize = 1024     #受信バッファサイズ byte
[byte[]]$RecvBuf = new-object byte[] $BufSize  #受信データバッファ(バイト)

Add-Type -AssemblyName System.Windows.Forms    #アセンブリのロード

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

#---+---+---+---+---+---+---+---+---+---+ 受信処理　戻り値：受信バイト数、未受信またはエラー時は 0
Function RecvByteFnc {
    $RecvSize = 0
    While ($true) {
        Try {
            $RecvSize += $TcpClient.GetStream().Read($RecvBuf, $RecvSize, $BufSize - $RecvSize)  #受信（バッファ, オフセット, サイズ）
            If ($RecvSize -eq 0) {
                Write-Host "Socketが閉じられました。" -ForegroundColor Red
                Throw  #処理終了
            }
            If ($RecvBuf[$RecvSize - 1] -eq 0x0d) { Break }  #データ末尾CR確認
        } Catch [System.IO.IOException] {
            If ($_.Exception.InnerException.SocketErrorCode -eq "TimedOut") {
                Write-Host "機器からの応答がありません。" -ForegroundColor Red
                Throw "ScriptHalted"
            } Else {
                Write-Host "Socketエラー：$($_.Exception.InnerException.SocketErrorCode)" -ForegroundColor Red
                Throw "ScriptHalted"
            }
        } Catch { Throw }
    }
    Return $RecvSize
}

#---+---+---+---+---+---+---+---+---+---+ 送信処理　文字列送信
Function SendStrFnc($SendStr) {
    $RecvBuf = [System.Text.Encoding]::UTF8.GetBytes("$SendStr")  #UTF-8バイトエンコード
    #$RecvBuf = [System.Text.Encoding]::Default.GetBytes("$SendStr")  #シフトJISバイトエンコード
    $TcpClient.GetStream().Write($RecvBuf, 0, $RecvBuf.Length)  #送信（バッファ, オフセット, データサイズ）
}

#---+---+---+---+---+---+---+---+---+---+ 受信データバッファ ⇒ エンコード　戻り値：エンコード文字列
Function RecvBufEnc($Len) {
    $Str = [System.Text.Encoding]::UTF8.GetString($RecvBuf, 0, $Len)  #バイナリをUTF-8に変換
    #$Str = [System.Text.Encoding]::Default.GetString($RecvBuf, 0, $Len)  #バイナリをシフトJISに変換
    Return $Str.Replace([char]0x1b, "･")  #ESCを置き換え
}

################################################## イニシャル処理
Write-Host "AP-0820 ファイル転送を開始します。"
Write-Host "CTRL+C を入力すると終了します。"

################################################## メイン処理
#TCPクライアント接続
$TcpClient = New-Object System.Net.Sockets.TcpClient
$TcpClient.ReceiveTimeout = $RecvTimeout
OpenFnc #接続処理
Write-Host "接続しました。$(Get-Date -Format 'yyyy/MM/dd HH:mm:ss')"
    
Try {
    #AP-0820 設定情報取得
    SendStrFnc "conf`r"
    $Str = RecvBufEnc (RecvByteFnc)  #設定受信
    Foreach ($Line in $Str.Split("`n")) {  #LFで区切って表示
        if ($Line -match "name=") {
            Write-Host "デバイス名：$($Line.Remove(0, $Line.indexOf("name=") + 5))"  #デバイス名表示
        }
    }
    
    While($true) {
        $Filename = Read-Host "転送先のファイル名を入力してください。（f00～f99）q:終了"
        If ($Filename -eq "q") { Break }
        If ($Filename -notmatch "f[0-9][0-9]") {
            Write-Host "不正なファイル名です。" -ForegroundColor Magenta
            Continue
        }
    
        Write-Host "転送するファイルを選択してください。キャンセル:終了"
        #ファイル選択ダイアログ
        $DialogFile = New-Object System.Windows.Forms.OpenFileDialog
        $DialogFile.Filter = 'テキストファイル(*.csv,*.txt)|*.csv;*.txt|全てのファイル(*.*)|*.*'  #フィルタ条件の設定
        $DialogFile.Title = "転送するファイルを選択してください。"    #タイトルの設定
        $DialogFile.InitialDirectory = 'Desktop'    #デフォルト選択ディレクトリの設定
        $DialogFile.MultiSelect = $true    #複数ファイルを選択する。
        if ($DialogFile.ShowDialog() -ne "OK") { Break }
    
        #ファイル削除
        Write-Host "ファイルを削除します。（$Filename=）"
        SendStrFnc ($Filename + "=`r")
        $Len = RecvByteFnc  #データ受信
    
        # テキストファイルを1行ずつ読み込みして送信
        $Count = 0
        $Size = 0
        $Flag = $true
        Foreach ($Line in Get-Content $DialogFile.FileName -Encoding UTF8) {  #UTF-8でファイル読み込み
        #Foreach ($Line in Get-Content $DialogFile.FileName -Encoding Default) {  #シフトJISでファイル読み込み
            $Count++
            Write-Host "$Count：$Line"
            $Size += $Line.length + 1
            SendStrFnc ($Filename + "+" + $Line + "`r")  #送信
            $Len = RecvByteFnc  #データ受信
            If ($RecvBuf[0] -ne 0x1b -or $RecvBuf[1] -ne [byte][char]"0" -or $RecvBuf[2] -ne 0x0d) {  #ESC 0 CR
                $Str = (RecvBufEnc $Len)
                Write-Host "送信エラーが発生しました。（$Str）処理を中断します。" -ForegroundColor Magenta
                $Flag = $false
                Break
            }
        }
        Write-Host "送信データサイズ＝ $Size byte"
        If ($Flag) {
            Write-Host "正常に転送されました。（$($DialogFile.FileName) -> $Filename）"
        }
    }

################################################## エラー処理
} Catch {
    If ($_.Exception.Message -ne "ScriptHalted") {
        $Error[0] | Out-string | Write-Host -ForegroundColor Red
    }

################################################## 終了処理
} Finally {
    CloseFnc  #切断処理
}
Write-Host "処理終了"
Exit    #スクリプト終了
################################################## End Of File