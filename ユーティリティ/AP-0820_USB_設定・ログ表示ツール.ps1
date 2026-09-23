##################################################
# AP-0820 設定・ログ表示ツール 2026/7/24
################################################## 初期設定
$ErrorActionPreference = "SilentlyContinue"    #エラー発生時は無視

# シリアル通信パラメータ設定
$ComParam = @("COM", "115200", "None", "8", "One")    #COMポート設定 COM番号、ボーレート、パリティ（None, Odd, Even, Mark, Space)、データ長、ストップ

$RecvTimeout = 100     #受信タイムアウト(ms)
$BufSize = 1024
$RecvBuf = new-object byte[] $BufSize  #受信データバッファ(バイト)
$SendBuf = new-object byte[] $BufSize  #データバッファ byte

################################################## 関数定義
#---+---+---+---+---+---+---+---+---+---+ 受信処理　戻り値：受信バイト数
Function RecvFnc {
    While ($ComPortObj.BytesToRead -eq 0) { Start-Sleep -m 1 }   #受信待ち
    $Len = 0
    While ($true) {
        Try {
            $Len += $ComPortObj.Read($RecvBuf, $Len, $BufSize - $Len)  #データバッファ, オフセット, 受信バイト数
        } Catch [TimeoutException] {
            break;
        } Catch {
            Throw
        }

        If($Len -ge $BufSize) {
            Start-Sleep -m 1000
            Write-Host "受信バッファオーバーしました。受信サイズ＝$($Len + $ComPortObj.BytesToRead) Byte" -ForegroundColor Red
            [void]$ComPortObj.DiscardInBuffer()  #受信バッファークリア
            break
        }
    }
    Return $Len
}

#---+---+---+---+---+---+---+---+---+---+ 受信データバッファ ⇒ バイナリ文字列　戻り値：受信バイト数
Function RecvBufByte($Len) {
    $BinStr = ""
    For ($i = 0; $i -lt $Len; $i++) {
        $BinStr += $RecvBuf[$i].ToString("X2") + " "  #16進数文字に変換
    }
    Return $BinStr
}

#---+---+---+---+---+---+---+---+---+---+ 受信データバッファ ⇒ エンコード　戻り値：エンコード文字列
Function RecvBufEnc($Len) {
    $SjisStr = [System.Text.Encoding]::Default.GetString($RecvBuf, 0, $Len)  #バイナリをシフトJISに変換
    $Str = $SjisStr.Replace([char]0x1b, "･")  #ESCを置き換え
    $Str = $Str.Replace("`r", " ")  #CRを置き換え
    Return $Str
}

#---+---+---+---+---+---+---+---+---+---+ キャラクタコード変換　戻り値：バイト数
Function ChrCodeConv($Str) {
    $i = 0
    #<NUL>～<SPC>,<DEL>変換
    Foreach ($c in @(`
            "<NUL>", "<SOH>" ,"<STX>" ,"<ETX>" ,"<EOT>" ,"<ENQ>" ,"<ACK>" ,"<BEL>" ,"<BS>" ,"<HT>" ,"<LF>",`
            "<VT>", "<FF>", "<CR>", "<SO>", "<SI>", "<DLE>", "<DC1>" ,"<DC2>", "<DC3>", "<DC4>", "<NAK>",`
            "<SYN>", "<ETB>", "<CAN>", "<EM>", "<SUB>", "<ESC>", "<FS>", "<GS>", "<RS>", "<US>", "<SPC>")) {
        $Str = $Str.Replace($c, $([char]$i))
        $i++
    }
    $Str = $Str.Replace("<DEL>", $([char]0x7f))
    
    #<01>～<FF>変換
    $Ary = [system.text.encoding]::Default.GetBytes("$Str")  #SJIS -> バイトコード
    #$Ary = [system.text.encoding]::UTF8.GetBytes("$Str")   #UTF8 -> バイトコード
    $i = 0
    $ByteStr = ""
    Foreach ($B in $Ary) {
        If ([char]$B -eq "<") {
            $ByteStr = "0x"
        } Else {
            If ($ByteStr -ne "") {
                If ([char]$B -match '[0-9]' -or [char]$B -match '[a-f]') {
                    If ($ByteStr.Length -lt 4) {
                        $ByteStr += [char]$B
                    } Else {
                        $ByteStr = ""
                    }
                } ElseIf ([char]$B -eq ">" -and $ByteStr.Length -eq 4) {
                    $i -= 3
                    $B = [byte]$ByteStr
                    $ByteStr = ""
                } Else {
                    $ByteStr = ""
                }
            }
        }
        $Script:SendBuf[$i] = $B
        $i++
    }
    Return $i
}

################################################## イニシャル処理
Write-Host "AP-0820 設定・ログ表示ツールを開始します。"
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
$ComPortObj.ReadTimeout = $RecvTimeout    #受信タイムアウト（ms）　デフォルトは-1で無効

try {
    $ComPortObj.Open()
} catch {
    Write-Host "COMポートのオープンが出来ません。" -ForegroundColor Red
    Exit    #スクリプト終了
}
Write-Host "COMポートオープン"

#---+---+---+---+---+---+---+---+---+---+ 送受信バッファクリア
Start-Sleep -m 1000    #機器からの不要データ受信待ちms
[void]$ComPortObj.DiscardInBuffer()  #受信バッファー
[void]$ComPortObj.DiscardOutBuffer()  #送信バッファー

Try {
    ################################################## 動作設定コマンド
    Write-Host "AP-0820 動作設定・ログ表示ツール" -ForegroundColor Green
    Write-Host "name=最大15byte、rfid=0-2、tone=0-5000、log=0-2、read=0-3、ssid=最大32byte、pass=最大16byte"
    Write-Host "ip=xxx.xxx.xxx.xxx、mask=xxx.xxx.xxx.xxx、gate=、dns=、、port=0-65535"
    Write-Host "bat=0-3300、host=U,B,W,H,S、rfbk=00-98、qr=xxxxxx、mtu=23-512、peri=最大12byte"
    Write-Host "conf、clear、info、reset、cmd=xxx･･･"
    Write-Host "ASCIIコードでの入力方法 制御コード<NUL>～<SPC>,<DEL>、16進コード<01>～<FF>"
    While($true) {
        Write-Host "コマンド入力（終了q）: " -ForegroundColor Green -NoNewline
        $Cmd = Read-Host
        If($Cmd.ToUpper() -eq "Q") { Break }  #設定終了
        $Cmd += "`r"  #CR追加
        $Len = ChrCodeConv $Cmd  #キャラクタコード変換
        $ComPortObj.Write($SendBuf, 0, $Len)  #送信
        #If($Cmd -like "cmd=*") { Break }  #コマンド入力時は終了
        $Len = RecvFnc  #受信
        Write-Host (RecvBufEnc($Len))  #受信データ 文字エンコードして表示
        #Write-host (RecvBufByte($Len))  #受信データ バイナリ表示
    }

    ################################################## ログ表示
    Write-Host "ログを表示します。表示されない場合は、log=1 または log=2 になっているか設定を確認してください。" -ForegroundColor Green
    While($true) {
        $Len = RecvFnc  #受信
        $Str = RecvBufEnc($Len)  #文字エンコード
        Write-Host ($Str.TrimEnd("`n"))  #受信データ 末尾LF削除して表示
        #Write-host (RecvBufByte($Len))  #受信データ バイナリ表示
    }

################################################## 例外処理
} Catch {
    If ($PSItem.ToString() -ne "ScriptHalted") {  #Throwによる強制停止はエラー出力しない
        $Error[0] | Out-string | write-host -ForegroundColor red
    }

################################################## 終了処理
} Finally {    #CTRL+C キー入力後の処理
    #---+---+---+---+---+---+---+---+---+---+ COMポートクローズ
    $ComPortObj.Close()
    Write-Host "COMポートクローズ"
    Write-Host "処理終了"
}
Exit    #スクリプト終了

################################################## End Of File