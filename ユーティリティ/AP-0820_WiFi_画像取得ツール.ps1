##################################################
# AP-0820 QRスキャナ画像取得ツール 2025/12/30
################################################## 初期設定
$ErrorActionPreference = "SilentlyContinue"    #エラー発生時は無視
# TCP通信パラメータ設定
$HostIp = "AP-0820.local"
#$HostIp = "192.168.11.2"
#$HostIp = "localhost"
$Port = 9004

$TcpClient = New-Object System.Net.Sockets.TcpClient  #TCPクライアント インスタンス
#$TcpClient.SendTimeout = 5000        #送信タイムアウト ms　規定値は0で無制限
$TcpClient.ReceiveTimeout = 1000     #受信タイムアウト ms　規定値は0で無制限
#$TcpClient.SendBufferSize = 8192     #送信バッファー サイズ byte　規定値は8192
#$TcpClient.ReceiveBufferSize = 8192  #受信バッファー サイズ byte　規定値は8192

$BufSize = 1024 * 1024
[byte[]]$RecvBuf = new-object byte[] $BufSize  #受信データバッファ(バイト)

$CmdG = ""  #画像取得コマンド
$ImgCnt = 0  #画像枚数

################################################## 関数定義
#---+---+---+---+---+---+---+---+---+---+ 送信処理
Function SendFnc ($Str) {
    If ($TcpClient.Connected) {  #接続確認
        Write-Host "送信：$Str"
        $Bytes = [System.Text.Encoding]::Default.GetBytes("$Str")  #SJISエンコード後にバイト配列へ
        $TcpClient.GetStream().Write($Bytes, 0, $Bytes.Length)  #送信（バッファ, オフセット, データサイズ）
    } Else {
        Write-Host "回線が切断されました。"  -ForegroundColor yellow -NoNewline
        $null = Read-Host "Enterキーで終了します。"
        Throw  #終了エラー
    }
}

#---+---+---+---+---+---+---+---+---+---+ 受信処理
Function RecvFnc () {
    Write-Host -NoNewline "受信："
    # 受信待ち
    while (-not $TcpClient.GetStream().DataAvailable) { Start-Sleep -m 1 }

    $RecvSize = 0
    While($true) {  #タイムアウトまで受信
        Try {
            $RecvSize += $TcpClient.GetStream().Read($RecvBuf, $RecvSize, $BufSize - $RecvSize)  #受信（バッファ, オフセット, サイズ）
        } Catch {
            Break
        }
    }
    Return $RecvSize
}

#---+---+---+---+---+---+---+---+---+---+ 受信データバッファ ⇒ エンコード　戻り値：エンコード文字列
Function RecvBufEnc($Len) {
    $SjisStr = [System.Text.Encoding]::Default.GetString($RecvBuf, 0, $Len)  #バイナリをシフトJISに変換
    $Str = $SjisStr.Replace([char]0x1b, "･")  #ESCを置き換え
    $Str = $Str.Replace([char]0x0d, " ")  #CRを置き換え
    Return $Str
}

################################################## イニシャル処理
Write-Host "AP-0820 QRスキャナ画像取得ツールを開始します。"
Write-Host "ネットワーク接続中...（HostIp=$HostIp Port=$Port）"
Try {
    $TcpClient.Connect($HostIp, $Port)  #TCPクライアント接続（IPアドレス, ポート番号）
} Catch {
    Write-Host "接続できませんでした。" -ForegroundColor yellow -NoNewline
    $null = Read-Host "Enterキーで終了します。"
    Exit    #スクリプト終了
}

Write-Host "接続できました。CTRL+C を入力すると終了します。"

################################################## 画像取得コマンド
$InputStr = Read-Host "画像サイズを選択してください。（0：1/1サイズ、1：1/4サイズ、2：1/16サイズ）"
If ($InputStr -eq "0") {
    $Script:CmdG = "G0`r"
} elseif ($InputStr -eq "1") {
    $Script:CmdG = "G1`r"
} elseif ($InputStr -eq "2") {
    $Script:CmdG = "G2`r"
}

Try {
    ################################################## メインループ処理
    While($true) {
        #------------ QR読み取り
        Write-Host "QRコードを読取してください。"
        SendFnc "F`r"
        $Len = RecvFnc  #ステータス受信
        If ($Len -eq 3 -and $RecvBuf[0] -eq 0x1b) {
            Write-Host "読み取りエラー"
        } Else {
            RecvBufEnc $Len  #読み取りデータ表示
        }

        #------------ 画像受信
        SendFnc $CmdG
        Write-Host "画像データ取得中..."
        $Len = RecvFnc

        $Script:ImgCnt++  #枚数カウント

        #------------ ファイル出力
        $FilePath = "$PSScriptRoot\img_$ImgCnt.bmp"
        $Bin = $RecvBuf[0..($Len-1)]
        Set-Content $FilePath -Value $Bin -Encoding Byte
        Write-Host "画像ファイルを出力しました。size= $Len byte"
        Write-Host $FilePath
        Start-Sleep -s 3
        . $FilePath  #画像表示
    }

################################################## 例外処理
} Catch {
    If ($PSItem.ToString() -ne "ScriptHalted") {  #Throwによる強制停止はエラー出力しない
        $Error[0] | Out-string | write-host -ForegroundColor red
    }

################################################## 終了処理
} Finally {
    Write-Host "処理終了"
}
Exit    #スクリプト終了
################################################## End Of File