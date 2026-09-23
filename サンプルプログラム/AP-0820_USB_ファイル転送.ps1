##################################################
# AP-0820 ファイルデータ転送 2026/6/5
################################################## 初期設定
$ErrorActionPreference = "SilentlyContinue"    #エラー発生時は無視

#シリアル通信パラメータ設定
$ComParam = @("COM", "115200", "None", "8", "One")  #COMポート設定 COM番号、ボーレート、パリティ（None, Odd, Even, Mark, Space)、データ長、ストップ

$RecvTimeout = 500  #受信タイムアウト(ms)
$BufSize = 1024
[byte[]]$RecvBuf = new-object byte[] $BufSize  #受信データバッファ(バイト)

Add-Type -AssemblyName System.Windows.Forms    #アセンブリのロード

################################################## 関数定義
#---+---+---+---+---+---+---+---+---+---+ 受信処理　戻り値：受信バイト数、未受信またはエラー時は 0
Function RecvByteFnc {
    #While ($ComPortObj.BytesToRead -eq 0) { Start-Sleep -m 1 }  #受信待ち
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
        If ($RecvBuf[$Len - 1] -ge 0x0d) { Break }  #末尾CR確認
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
    $Str = [System.Text.Encoding]::UTF8.GetString($RecvBuf, 0, $Len)  #バイナリをUTF-8に変換
    #$Str = [System.Text.Encoding]::Default.GetString($RecvBuf, 0, $Len)  #バイナリをシフトJISに変換
    Return $Str.Replace([char]0x1b, "･")  #ESCを置き換え
}

################################################## イニシャル処理
Write-Host "AP-0820 ファイル作成を開始します。"
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

################################################## メイン処理
Try {
    #AP-0820 設定情報取得
    SendStrFnc "conf`r"
    $Str = RecvBufEnc (RecvByteFnc)  #設定受信
    Foreach ($Line in $Str.Split("`n")) {  #LFで区切って表示
        if ($Line -match "name=") {
            Write-Host "デバイス名：$($Line.Remove(0, $Line.indexOf("name=") + 5))"  #デバイス名表示
        }
        if ($Line -match "log=") {
            If ($Line.Substring($Line.Length - 1, 1) -ne "0") {
               Write-Host "ログ出力モードを OFF にします。（log=0）" -ForegroundColor Yellow
                SendStrFnc "log=0`r"  #ログ出力停止
                $Len = RecvByteFnc  #ステータス受信
            }
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