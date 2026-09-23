##################################################
# AP-0820 QRスキャナ画像取得ツール 2026/5/22
################################################## 初期設定
$ErrorActionPreference = "SilentlyContinue"    #エラー発生時は無視

#シリアル通信パラメータ設定
$ComParam = @("COM", "115200", "None", "8", "One")  #COMポート設定 COM番号、ボーレート、パリティ（None, Odd, Even, Mark, Space)、データ長、ストップ

$RecvTimeout = 300  #受信タイムアウト(ms)
$BufSize = 1024 * 1024
[byte[]]$RecvBuf = new-object byte[] $BufSize  #受信データバッファ(バイト)

$CmdG = ""  #画像取得コマンド
$ImgCnt = 0  #画像枚数

################################################## 関数定義
#---+---+---+---+---+---+---+---+---+---+ 受信処理　戻り値：受信バイト数、未受信またはエラー時は 0
Function RecvByteFnc {
    While ($ComPortObj.BytesToRead -eq 0) { Start-Sleep -m 1 }  #受信待ち
    $Len = 0
    $Time = Get-Date
    While ($true) {
        $Size = $ComPortObj.BytesToRead
        If ($Size -gt 0) {
            If ($Len + $Size -le $BufSize) {
                $Len += $ComPortObj.Read($Script:RecvBuf, $Len, $Size)  #データバッファ, オフセット, 受信バイト数
            } Else {
                $Len += $ComPortObj.Read($Script:RecvBuf, $Len, $BufSize - $Len)  #データバッファ, オフセット, 受信バイト数
                Write-Host "バッファオーバーフローが発生しました。" -ForegroundColor Magenta
                Break
            }
            $Time = Get-Date
        }
        If (((Get-Date) - $Time).TotalMilliseconds -ge $RecvTimeout) { Break }  #受信タイムアウト確認
        Start-Sleep -m 1  #処理負荷低減用
    }
    Return $Len
}

#---+---+---+---+---+---+---+---+---+---+ 送信処理　文字列送信
Function SendStrFnc($SendStr) {
    $ComPortObj.Write($SendStr)    #送信
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
$ComAry = [System.IO.Ports.SerialPort]::GetPortNames()
If ($ComAry.Count -eq 0) {
    Write-Host "シリアルデバイスが見つかりません。" -ForegroundColor Red
    $null = Read-Host "USBケーブルの接続を確認してください。Enterキーで終了します。"
    Exit
}
Write-Host "シリアルCOM番号を入力してください。（$ComAry）"
Do {
    $ComNum = Read-Host "COM番号"
} While($ComNum -notmatch '^[1-9]+')  #1～の数字確認
$ComParam[0] += $ComNum

# シリアルCOMポート生成、パラメータ設定
$ComPortObj = New-Object System.IO.Ports.SerialPort $ComParam    #COM番号、ボーレート、データ長、パリティ、ストップ

try {
    $ComPortObj.Open()
} catch {
    Write-Host "COMポートのオープンが出来ません。" -ForegroundColor Red
    Exit    #スクリプト終了
}
Write-Host "COMポートオープン"

#---+---+---+---+---+---+---+---+---+---+ 送受信バッファクリア
Start-Sleep -m 1000    #機器からの不要データ受信待ちms
[void]$ComPortObj.DiscardInBuffer()   #受信バッファクリア
[void]$ComPortObj.DiscardOutBuffer()  #送信バッファクリア

################################################## 画像取得コマンド
$InputStr = Read-Host "画像サイズを選択してください。（0：1/1サイズ、1：1/4サイズ、2：1/16サイズ）"
If ($InputStr -eq "0") {
    $Script:CmdG = "G0`r"
} elseif ($InputStr -eq "1") {
    $Script:CmdG = "G1`r"
} elseif ($InputStr -eq "2") {
    $Script:CmdG = "G2`r"
}

################################################## メイン処理
Try {
    #AP-0820 設定情報取得
    SendStrFnc "conf`r"
    $Str = RecvBufEnc (RecvByteFnc)  #設定受信
    Foreach ($Line in $Str.Split("`n")) {  #LFで区切って表示
        if ($Line -match "log=") {
            If ($Line.Substring($Line.Length - 1, 1) -ne "0") {
               Write-Host "ログ出力モードを OFF にします。（log=0）"
                SendStrFnc "log=0`r"  #ログ出力停止
                $Len = RecvByteFnc  #ステータス受信
            }
        }
    }

    While($true) {
        #------------ QR読み取り
        Write-Host "QRコードを読取してください。"
        SendStrFnc "F`r"
        $Len = RecvByteFnc  #ステータス受信
        If ($Len -eq 3 -and $RecvBuf[0] -eq 0x1b) {
            Write-Host "読み取りエラー"
        } Else {
            RecvBufEnc $Len  #読み取りデータ表示
        }

        #------------ 画像受信
        SendStrFnc $CmdG
        Write-Host "画像データ取得中..."
        $Len = RecvByteFnc

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
    #---+---+---+---+---+---+---+---+---+---+ COMポートクローズ
    $ComPortObj.Close()
    Write-Host "COMポートクローズ"
    Write-Host "処理終了"
}
Exit    #スクリプト終了
################################################## End Of File