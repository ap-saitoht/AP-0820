<#################################################
 AP-0820 BLEファイル連携ツール実行サンプルプログラム PowerShell 2026/5/30

 ・スクリプトを編集・デバッグするには、ポリシーの設定をする必要があります。
 　管理者権限でPowerShellを起動し、下記コマンドレットを実行してください。
 　　Set-ExecutionPolicy RemoteSigned

・バッチまたは、ショートカットでの起動方法
  powershell.exe -WindowStyle Hidden -ExecutionPolicy RemoteSigned -command ".\サンプルスクリプト.ps1"

●使い方
・ファイル連携ツールと同じフォルダにこのスクリプトファイルを置いてください。
・ファイル連携ツールの設定ファイルを使用環境にあわせて編集してください。
・本プログロムの設定について
    ファイルパス設定では、ツールや連携ファイル、読取データの出力ファイルを設定します。（基本的に変更は不要です）
    コマンド設定では、機器の初期化、読取コマンド、OK時コマンド、RFID書込、NG時コマンドを設定します。
    読取データ処理設定では、処理終了データ、重複読取チェック、マスターチェック、読取データ編集（切り取り）機能を使用する際に設定します。
・読取したデータはテキストファイルに追記されます。
・例外処理は行っていませんので、不具合が発生した場合には強制終了する場合があります。

●動作
・本プログラムを起動するとファイル連携ツールを起動し、機器との通信が開始されます。
・機器からのステータスおよび読取データを受信する場合は、command.txt が存在せず、status.txt が見つかったら読み込みをします。
・status.txt には、機器が接続された直後は ESC P CR が書き込まれています。その他ステータスについては機器の取説を参照してください。
・機器へコマンドを送信する場合は、command.txt を作成しコマンドを書き込みした後 status.txt を削除します。
・機器との通信エラーを取得する場合は、error.txt を読み込みしてください。エラーが発生都度ファイルに追記されていきます。
・error.txt はツール起動時に削除されますが、プログラムから削除する場合には command.txt が存在しないことを確認してから削除してください。
#>
################################################## 初期設定
$FileChkWait = 10  #ファイル確認待ち間隔(ms)
$Encode = "Default"  #エンコード 例）"UTF8"、"Default":シフトJIS

#ファイルパス設定
$ToolPath = ".\AP-0820_FileLinkage.exe"  #ファイル連携ツール
#$ToolPath = ".\AP-0820_FileLinkage.py"  #ファイル連携ツール（Pythonの実行環境がインストールされている場合はスクリプトを起動できます）
$ActFilePath = ".\active.txt"  #ツール実行中ファイル ※このファイルを削除するとツールと本スクリプトが終了します。
$CmdFilePath = ".\command.txt"  #コマンドファイル
$StatFilePath = ".\status.txt"  #ステータスファイル
$ErrFilePath = ".\error.txt"  #エラーファイル
$OutputFilePath = ".\ReadData.txt"  #読取データ出力ファイル

Set-Location -Path $PSScriptRoot  #カレントをスクリプトのフォルダに移動

#コマンド設定（未設定時は処理しない）
$CmdAry_Init = @("I", "Q0")  #初期設定コマンド
$Cmd_Read = "A"  #読取コマンド
$CmdAry_Ok = @("LA04", "B1", "M1")  #読取OK時コマンド
$Cmd_RfidWrite = ""  #読取データをRFIDに書込する場合に開始ブロックを指定 例）"W00"
$CmdAry_Err = @("LA02", "B30200")  #エラー時コマンド

#読取データ処理設定
$ExitData = "99999999"  #処理終了データ
$Duplicate_Flag = $false  #重複読取チェックする場合は$true、しない場合は$false
$MasterFilePath = ""  #マスターチェック用ファイル。未指定""の場合はチェックしない。例）.\Master.txt
$MasterChk_Pos = 1    #マスターチェック時の読取データ桁位置
$EditData_Flag = $false #読取データ編集（切り取り）する場合は$true、しない場合は$false
$Cut_Pos = 1    #読取データ編集時の開始位置
$Cut_Len = 5    #読取データ編集時の文字数
$EditFilePath = ""  #読取データ編集結果の出力ファイル。未指定""の場合は出力しない。例）.\ResultData.txt

$MasterChk_Pos = $MasterChk_Pos - 1    #処理上-1しておく
$Cut_Pos = $Cut_Pos - 1    #処理上-1しておく
$ReadData = ""  #読取データ

################################################## 関数定義
#---+---+---+---+---+---+---+---+---+---+ ステータス処理
#戻り値：ステータス文字、読取データ時は"data"
Function StatFnc($Stat) {
    If ($Stat.Length -eq 2) {
        If ($Stat[0] -eq [char]0x1b) {    #先頭 ESC 確認
            Switch ($Stat[1]) {
                "0" {    #正常応答
                    #Write-Host "正常応答：$($Stat[1])"
                }
                "?" {    #読取エラー
                    Write-Host "読取エラー：$($Stat[1])"
                }
                "P" {    #ツール起動
                    Write-Host "ツールが起動または、装置が接続されました。：$($Stat[1])"
                    If ($CmdAry_Init.Count -gt 0) {
                        Write-Host "初期設定：$CmdAry_Init"
                        CmdArySendFnc $CmdAry_Init    #初期設定
                    }
                }
                "C" {    #コマンドエラー
                    Write-Host "コマンドエラー：$($Stat[1])" -ForegroundColor Magenta
                }
                "T" {    #トリガボタン
                    Write-Host "トリガボタンが押されました。：$($Stat[1])"
                }
                "W" {    #書き込みエラー
                    Write-Host "書き込みエラー：$($Stat[1])" -ForegroundColor Magenta
                }
                "E" {    #処理終了 ※装置からのステータスではなく本プログラム内で使用
                    Write-Host "ツールが終了されました。：$($Stat[1])" -ForegroundColor Magenta
                }
                Default {    #未対応ステータス
                    Write-Host "未対応ステータス：$($Stat[1])" -ForegroundColor Magenta
                }
            }
            Return $Stat[1]
        }
    }
    $script:ReadData = $Stat
    Write-Host "読取データ：$ReadData"
    Return "data"
}

#---+---+---+---+---+---+---+---+---+---+ 読取データ処理
#戻り値：OK時は$true
Function ReadDataFnc {
    #処理終了データ確認
    If ($ReadData -eq $ExitData) {
        Write-Host "処理終了データを読み取りました。"
        Remove-Item -Path $ActFilePath  #処理終了
        Return $false
    }

    #重複読取チェック
    If ($Duplicate_Flag) {
        If (!(DuplicateChk $ReadData)) {
            Write-Host "重複チェックエラー" -ForegroundColor Magenta
            Write-Host "エラー時コマンド送信：$CmdAry_Err"
            CmdArySendFnc $CmdAry_Err
            Return $false
        }
    }

    #マスタチェック
    If ($MasterFilePath -ne "") {
        If (!(MasterChk $ReadData)) {
            Write-Host "マスタチェックエラー" -ForegroundColor Magenta
            Write-Host "エラー時コマンド送信：$CmdAry_Err"
            CmdArySendFnc $CmdAry_Err
            Return $false
        }
    }

    #読取データをファイル出力（追記）
    Write-Host "読取データ出力"
    Add-Content -Path $OutputFilePath  -Value $ReadData -Encoding $Encode
    
    #読取データ編集
    If ($EditData_Flag) {
        $Script:ReadData = EditDataFnc $ReadData
        Write-Host "データ編集：$ReadData"
        If ($EditFilePath -ne "") {
            Write-Host "編集結果出力：$ReadData"
            Add-Content -Path $EditFilePath  -Value $ReadData -Encoding $Encode
        }
    }

    #読取データOK時コマンド
    Write-Host "OK時コマンド送信：$CmdAry_Ok"
    CmdArySendFnc $CmdAry_Ok
    Return $true
}

#---+---+---+---+---+---+---+---+---+---+ 重複読取チェック処理
#戻り値：重複なし時はtrue、重複あり時はfalse
Function DuplicateChk($DataStr) {
    foreach ($Str in Get-Content -Path $OutputFilePath) {    #読取データファイル読み込み
        If ($Str -ceq $DataStr) {
            Return $false
        }
    }
    Return $true
}

#---+---+---+---+---+---+---+---+---+---+ マスタチェック処理
#戻り値：OK時はtrue、NG時はfalse
Function MasterChk([string]$DataStr) {
    foreach ($MasterStr in Get-Content -Path $MasterFilePath) {    #マスタファイル読み込み
        $Str = CutOutFnc $DataStr $MasterChk_Pos $MasterStr.Length    #読取データをマスタデータにあわせ切り出し
        If ($Str -ceq $MasterStr) {
            Return $true
        }
    }
    Return $false
}

#---+---+---+---+---+---+---+---+---+---+ 読取データ編集処理
#戻り値：データ編集結果
Function EditDataFnc([string]$DataStr) {
    Return CutOutFnc $DataStr $Cut_Pos $Cut_Len
}

#---+---+---+---+---+---+---+---+---+---+ データ切り出し
#戻り値：データ切り出し結果
Function CutOutFnc([String]$DataStr, [Int]$Pos, [Int]$Len) {
    $DataLen = $DataStr.Length
    If ($DataLen -lt $Pos) {
        $DataStr = ""
    } Else {
        $OverLen = $Pos + $Len - $DataLen
        If ($OverLen -lt 0) { $OverLen = 0 }
        $DataStr = $DataStr.Substring($Pos, $Len - $OverLen)
    }
    Return $DataStr
}

#---+---+---+---+---+---+---+---+---+---+ エラーファイル受信
Function ErrRecvFnc {
    Write-Host "ツールでエラーが発生しました。：$(Get-Content -Path $ErrFilePath -Encoding $Encode)" -ForegroundColor Magenta
    Remove-Item -Path $ErrFilePath  #エラーファイル削除
}

#---+---+---+---+---+---+---+---+---+---+ コマンド送信
Function CmdSendFnc($Cmd) {
    #コマンドファイル確認
    While (Test-Path $CmdFilePath -ErrorAction SilentlyContinue) {  #ファイルアクセス拒否を回避のため-ErrorAction追加
        If (!(Test-Path $ActFilePath)) { Throw "ツールが終了されました。" }  #ツール実行中ファイル確認
        Start-Sleep -m $FileChkWait
    }

    #エラーファイル確認
    If (Test-Path $ErrFilePath) { ErrRecvFnc }

    #ステータスファイルが無ければ作成
    If (!(Test-Path $StatFilePath)) { $null = New-Item -Path $StatFilePath }

    #コマンドのエンコード
    $Cmd += "`r"  #末尾CR追加
    If ($Encode -eq "Default") {
        $Bin = [System.Text.Encoding]::Default.GetBytes($Cmd)  #シフトJIS
    } Else {
        $Bin = [System.Text.Encoding]::UTF8.GetBytes($Cmd)  #UTF8
    }

    #コマンドファイル書き込み
    Set-Content -Path $CmdFilePath -Value $Bin -Encoding Byte  #バイナリファイル作成
    Remove-Item -Path $StatFilePath  #ステータスファイル削除
}

Function CmdArySendFnc($CmdAry) {
    Foreach ($Cmd in $CmdAry) {
        CmdSendFnc $Cmd
        $null = (StatFnc $(StatRecvFnc))
    }
}

#---+---+---+---+---+---+---+---+---+---+ ステータス受信
#戻り値：ステータスデータ
Function StatRecvFnc {
    #コマンドファイル確認
    While (Test-Path $CmdFilePath -ErrorAction SilentlyContinue) {  #ファイルアクセス拒否を回避のため-ErrorAction追加
        If (!(Test-Path $ActFilePath)) { Return "$([char]0x1b)E" }  #ツール実行中ファイル確認
        Start-Sleep -m $FileChkWait
    }

    #エラーファイル確認
    If (Test-Path $ErrFilePath) {
        ErrRecvFnc
        Return "$([char]0x1b)E"
    }

    #ステータスファイル読み込み
    While (!(Test-Path $StatFilePath)) {
        If (!(Test-Path $ActFilePath)) { Return "$([char]0x1b)E" }  #ツール実行中ファイル確認
        Start-Sleep -m $FileChkWait
    }
    $Stat = Get-Content -Path $StatFilePath -Encoding $Encode
    Return $Stat
}

#---+---+---+---+---+---+---+---+---+---+ RFID書込処理
#戻り値：ステータス文字
Function RfidWriteFnc($WriteData) {
    $Cmd = $Cmd_RfidWrite + $WriteData
    Write-Host "RFID書き込み：$Cmd"
    CmdSendFnc $Cmd
    $Stat = (StatFnc $(StatRecvFnc))
    If ($Stat -eq "0") {
        Write-Host "書き込みOK：$CmdAry_Ok"
        CmdArySendFnc $CmdAry_Ok
    } Else {
        Write-Host "書き込みエラー：$CmdAry_Err"
        CmdArySendFnc $CmdAry_Err
    }
    Return $Stat
}

################################################## メイン処理
try {
    #---+---+---+---+---+---+---+---+---+---+ イニシャル処理
    Write-Host "ツールを起動し処理を開始します。機器の電源を入れてください。"
    
    #ツール起動
    If (Test-Path $ActFilePath) {  #ツール実行中ファイルがあれば削除
        Write-Host "ツール実行中ファイルが見つかりました。ファイルを削除します。" -ForegroundColor Magenta
        Remove-Item -Path $ActFilePath
        Start-Sleep -s 3
    }
    If (Test-Path $ToolPath) {
        If([System.IO.Path]::GetExtension($ToolPath) -eq ".exe") {
            Start-Process -FilePath $ToolPath  #最小化で起動する場合は、-windowstyle Minimized を追加
        } else {
            Start-Process -FilePath python $ToolPath  #最小化で起動する場合は、-windowstyle Minimized を追加
        }
        While (!(Test-Path $ActFilePath)) {
            Start-Sleep -m $FileChkWait
        }
    } Else {    
        Write-Host "ツールが見つかりません。：$ToolPath" -ForegroundColor Magenta
    }
    
    $null = (StatFnc $(StatRecvFnc))    #ESC P CR 待ち

    #---+---+---+---+---+---+---+---+---+---+ メインループ
    While (Test-Path $ActFilePath) {
        #読取コマンド
        Write-Host "読取開始：$Cmd_Read"
        CmdSendFnc $Cmd_Read
        $Stat = (StatFnc $(StatRecvFnc))
        If ($Stat -eq "data") {
            $Stat = ReadDataFnc
        } else {
            $Stat = $false
        }
    
        If ($Stat -and $Cmd_RfidWrite -ne "") {
            #ランプ点滅
            CmdSendFnc "LA0C"
            $Stat = (StatFnc $(StatRecvFnc))

            #トリガボタン
            Write-Host "RFタグにデータを書き込みます。トリガボタンを押してください。"
            CmdSendFnc "T1"
            $Stat = (StatFnc $(StatRecvFnc))    #ESC T CR 待ち

            #RFID書込処理
            $WriteData = $ReadData
            Write-Host "RFIDタグ確認：FU"
            CmdSendFnc "FU"
            $Stat = (StatFnc $(StatRecvFnc))
            If ($Stat -eq "data") {
                $Stat = (RfidWriteFnc $WriteData)
                Start-Sleep -s 1
            } elseIf ($Stat -eq "?") {
                CmdArySendFnc $CmdAry_Err
            }
        }
    }

} Catch {
    #---+---+---+---+---+---+---+---+---+---+ エラー処理
    $Error[0] | Out-string | Write-Host -ForegroundColor red

} Finally {
    #---+---+---+---+---+---+---+---+---+---+ ツール終了、作業ファイル削除
    If (Test-Path $ActFilePath) {
        Write-Host "ツールを終了します。"
        Remove-Item -Path $ActFilePath
    }
    Write-Host "作業ファイルを削除します。"
    If (Test-Path $CmdFilePath) { Remove-Item -Path $CmdFilePath }
    If (Test-Path $StatFilePath) { Remove-Item -Path $StatFilePath }
    If (Test-Path $ErrFilePath) { Remove-Item -Path $ErrFilePath }
}

################################################## 終了処理
Write-Host "処理を終了します。"
#$null = Read-Host "[Enter]"
Exit    #スクリプト終了

################################################## End Of File