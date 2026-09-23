<################################################# CSVファイル表示 2026/3/28
指定したCSVファイルをタイマーでリアルタイムに読み込み表示するツールです。
１．ファイルを指定し読み込みをします。ファイル選択ボタンでダイアログが開きます。
２．ファイルが更新されるたびにデータグリッドビューを再表示します。
３．データグリッドビューにて編集をしてから別ファイルへの出力ができます。
xmlファイルにて起動時の設定ができます。

バッチまたは、ショートカットでの起動方法
  powershell.exe -WindowStyle Hidden -ExecutionPolicy RemoteSigned -command ".\スクリプト名.ps1"

#>
################################################## 動作設定
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$XmlFilePath = "CsvViewerConf.xml"

################################################## フォーム
#メインフォーム
$Form = New-Object System.Windows.Forms.Form
#$Form.Size = "550, 400"
$Form.StartPosition = 'CenterScreen'  #WindowsDefaultLocation  WindowsDefaultBounds  CenterParent

# データグリッドビュー
$Grid = New-Object System.Windows.Forms.DataGridView
$Grid.Dock = "Fill"
$Grid.AutoSizeColumnsMode = "Fill"  #表示領域の幅いっぱいに表示。"AllCells"ですべてのセルの内容に合わせ調整
$Grid.ColumnCount = 1   #列数を指定
$Grid.Columns.Clear()
$Form.Controls.Add($Grid)
# カーソル選択時のイベント
$Grid.add_CurrentCellChanged({
    $PanelStatus1.Text = "$($Grid.Rows.Count - 1) ($($Grid.CurrentCell.ColumnIndex + 1), $($Grid.CurrentCell.RowIndex + 1))" #ステータスバー1
})
# 行番号を描画するイベントハンドラを追加
$Grid.add_RowPostPaint({
    param($sender_, $e)
    $rowIdx = ($e.RowIndex + 1).ToString()  #行番号のテキスト（行のインデックス + 1）
    # 描画範囲の計算
    $headerBounds = New-Object System.Drawing.Rectangle($e.RowBounds.Left, $e.RowBounds.Top, $sender_.RowHeadersWidth, $e.RowBounds.Height)
    # 右寄せ
    $centerFormat = New-Object System.Drawing.StringFormat
    $centerFormat.Alignment = [System.Drawing.StringAlignment]::Far
    $centerFormat.LineAlignment = [System.Drawing.StringAlignment]::Center
    # ブラシとフォントを指定して描画
    $brush = New-Object System.Drawing.SolidBrush($sender_.RowHeadersDefaultCellStyle.ForeColor)
    $e.Graphics.DrawString($rowIdx, $sender_.Font, $brush, [System.Drawing.RectangleF]$headerBounds, $centerFormat)
})

# 操作パネル
$PanelOperation = New-Object System.Windows.Forms.Panel
$PanelOperation.Dock = "Bottom"  #フォーム内の表示位置 Top、Bottom
$PanelOperation.Height = "30"
$PanelOperation.Padding = New-Object System.Windows.Forms.Padding(5, 5, 5, 5) #パネル内余白
$Form.Controls.Add($PanelOperation)

# ヘッダ有チェックボックス
$ChkBoxHead = New-Object System.Windows.Forms.CheckBox
$ChkBoxHead.size = "65, 30"
$ChkBoxHead.Text = "ヘッダ有"
$ChkBoxHead.Dock = "Left"
$PanelOperation.Controls.Add($ChkBoxHead)
# 変更時のイベント
$ChkBoxHead.Add_CheckedChanged({
    if ($ChkBoxHead.Checked) {
        $Script:HeaderFlag = $true
    } else {
        $Script:HeaderFlag = $false
        $Grid.Columns.Clear()
    }
    $PanelStatus2.Text = "" #ステータスバー2 クリア
    $Script:WriteTime = ""  #データ再表示
})

# 文字エンコード
$ComboEnc = New-Object System.Windows.Forms.Combobox
$ComboEnc.size = "70, 30"
$ComboEnc.Dock = "Left"
$ComboEnc.DropDownStyle = "DropDown"    #DropDown、DropDownList、Simleから選択し変更可能
$ComboEnc.FlatStyle = "standard"
[void] $ComboEnc.Items.Add("UTF8")
[void] $ComboEnc.Items.Add("Default")
[void] $ComboEnc.Items.Add("ASCII")
[void] $ComboEnc.Items.Add("Unicode")
#$ComboEnc.SelectedIndex = 0
$PanelOperation.Controls.Add($ComboEnc)
# 変更時時のイベント
$ComboEnc.Add_SelectedIndexChanged({
    $Script:Encoding = $ComboEnc.Text
    $PanelStatus2.Text = "" #ステータスバー2 クリア
    $Script:WriteTime = ""  #データ再表示
})

# 区切り文字
$ComboSeparat = New-Object System.Windows.Forms.Combobox
$ComboSeparat.size = "50, 30"
$ComboSeparat.Dock = "Left"
$ComboSeparat.DropDownStyle = "DropDown"    #DropDown、DropDownList、Simleから選択し変更可能
$ComboSeparat.FlatStyle = "standard"
$ComboSeparat.Font = New-Object System.Drawing.Font("ＭＳ ゴシック", 10)
[void] $ComboSeparat.Items.Add(",")
[void] $ComboSeparat.Items.Add("TAB")
[void] $ComboSeparat.Items.Add("SP")
[void] $ComboSeparat.Items.Add(":")
[void] $ComboSeparat.Items.Add(";")
[void] $ComboSeparat.Items.Add("|")
#$ComboSeparat.SelectedIndex = 0
$PanelOperation.Controls.Add($ComboSeparat)
# 変更時のイベント
$ComboSeparat.Add_SelectedIndexChanged({
    Switch ($ComboSeparat.Text) {
        "TAB" {
            $Script:Separation = "`t"
            Break
        }
        "SP" {
            $Script:Separation = " "
            Break
        }
        Default {
            $Script:Separation = $ComboSeparat.Text
        }
    }
    $PanelStatus2.Text = "" #ステータスバー2 クリア
    $Script:WriteTime = ""  #データ再表示
})

# ファイル選択ボタン
$BtnFileSelect = New-Object Windows.Forms.Button
$BtnFileSelect.Text = "ファイル選択"
$BtnFileSelect.Dock = "Left"
$PanelOperation.Controls.Add($BtnFileSelect)
# クリック時のイベント
$BtnFileSelect.Add_Click({
    $openFile = New-Object Windows.Forms.OpenFileDialog
    $openFile.InitialDirectory = $PSScriptRoot
    $openFile.Filter = "CSVファイル|*.csv;*.tsv;*.txt|すべてのファイル|*.*"
    if ($openFile.ShowDialog() -eq [Windows.Forms.DialogResult]::OK) {
        $ComboFilePath.Text = $openFile.FileName
        [void] $ComboFilePath.Items.Add($openFile.FileName)
        $BtnFileChk.Text = "監視停止"
        $PanelStatus2.Text = "" #ステータスバー2 クリア
    }
})

# 監視ボタン
$BtnFileChk = New-Object System.Windows.Forms.Button
$BtnFileChk.Text = "監視停止"
$BtnFileChk.Dock = "Right"
$PanelOperation.Controls.Add($BtnFileChk)
# クリック時のイベント
$BtnFileChk.Add_Click({
    If($BtnFileChk.Text -eq "監視停止") {
        #監視停止
        $BtnFileChk.Text = "監視開始"
        $PanelStatus2.Text = "File monitoring stopped." #ステータスバー2
    } Else {
        #監視開始
        $BtnFileChk.Text = "監視停止"
        $PanelStatus2.Text = "File monitoring started." #ステータスバー2
    }
})

# ファイル出力ボタン
$BtnOutput = New-Object System.Windows.Forms.Button
$BtnOutput.Text = 'ファイル出力'
$BtnOutput.Dock = "Right"
$PanelOperation.Controls.Add($BtnOutput)
# クリック時のイベント
$BtnOutput.Add_Click({
    FileOutput
})

# 終了ボタン
$BtnCancel = New-Object System.Windows.Forms.Button
$BtnCancel.Text = '終了'
$BtnCancel.Dock = "Right"
$BtnCancel.DialogResult = [System.Windows.Forms.DialogResult]::OK
$Form.CancelButton = $BtnCancel
$PanelOperation.Controls.Add($BtnCancel)

# CSVファイルパス
$ComboFilePath = New-Object System.Windows.Forms.Combobox
$ComboFilePath.Dock = "Top"
$ComboFilePath.DropDownStyle = "DropDown"    #DropDown、DropDownList、Simleから選択し変更可能
$ComboFilePath.FlatStyle = "standard"
$form.Controls.Add($ComboFilePath) 
# 変更時のイベント
$ComboFilePath.Add_SelectedIndexChanged({
    $BtnFileChk.Text = "監視停止"
    $PanelStatus2.Text = "" #ステータスバー2 クリア
})

# ステータスバー
$StatusBar = New-Object System.Windows.Forms.StatusBar
$PanelStatus1 = New-Object System.Windows.Forms.StatusBarPanel
$PanelStatus1.AutoSize = 3     #幅 1.None:サイズ変更しない 2.Spring:ほかのパネルと共有 3.Contents:幅は内容によって決定
$PanelStatus1.ToolTipText = "行数 (カーソルX, Y)"    #ツールチップ
$PanelStatus2 = New-Object System.Windows.Forms.StatusBarPanel
$PanelStatus2.AutoSize = 2
$StatusBar.ShowPanels = $True
$null = $StatusBar.Panels.Add($PanelStatus1)    #戻り値が返ってくるため$nullに代入
$null = $StatusBar.Panels.Add($PanelStatus2)    #戻り値が返ってくるため$nullに代入
$Form.Controls.Add($StatusBar)

################################################## タイマ処理
$Timer = New-Object System.Windows.Forms.Timer
#$Timer.Interval = 500    #フォーム表示内容の更新間隔(ms)
#---+---+---+---+---+---+---+---+---+---+ 初期値
$WriteTime = ""
$Time = {
    #---+---+---+---+---+---+---+---+---+---+ 処理
    If ($ComboFilePath.Text -ne "" -and $BtnFileChk.Text -eq "監視停止") {
        If (Test-Path $ComboFilePath.Text) {    #読取データファイル存在確認
            #ファイルの更新日時を確認
            If($WriteTime -ne $(Get-ItemProperty $ComboFilePath.Text).LastWriteTime) {   #読取データファイルが更新された場合
                $script:WriteTime = $(Get-ItemProperty $ComboFilePath.Text).LastWriteTime
        
                # データクリッドビュー　項目追加
                If ($HeaderFlag) {
                    $Grid.Columns.Clear()   #ヘッダ含めすべて削除
                } Else {
                    $Grid.Rows.Clear()    #データ削除
                }
                Foreach ($Str in Get-Content $ComboFilePath.Text -Encoding $Encoding) {
                    $Ary = $Str.Split($Separation)
                    $Grid.ColumnCount = $Ary.Count    # 列数を指定
                    If ($HeaderFlag) {
                        #1行目ヘッダ項目追加 列タイトル
                        $i = 0
                        Foreach ($Item in $Ary) {
                            $Grid.Columns[$i++].Name = $Item
                        }
                        $HeaderFlag = $False
                    } Else {
                        #2行目以降レコード追加
                        [void]$Grid.Rows.Add($Ary)
                    }
                }
    
                $Grid.FirstDisplayedScrollingRowIndex = $Grid.Rows.Count - 1    #最下行を表示
            }
            $PanelStatus1.Text = "$($Grid.Rows.Count - 1) ($($Grid.CurrentCell.ColumnIndex + 1), $($Grid.CurrentCell.RowIndex + 1))" #ステータスバー1
            #$PanelStatus2.Text = "" #ステータスバー2
        } Else {
            $PanelStatus1.Text = ""
            $PanelStatus2.Text = "File not found." #ステータスバー2
            $Grid.Columns.Clear()   #データ削除
            $Script:WriteTime = ""  #データ再表示
        }
    }
}
$Timer.Add_Tick($Time)

################################################## ファイル処理
#---+---+---+---+---+---+---+---+---+---+ ファイル出力
Function FileOutput() {
    $OutFilePath = [System.IO.Path]::GetDirectoryName($ComboFilePath.Text) + "\"`
                    + [System.IO.Path]::GetFileNameWithoutExtension($ComboFilePath.Text)`
                    + "_out"`
                    + [System.IO.Path]::GetExtension($ComboFilePath.Text)
    
    $csvLines = New-Object System.Collections.Generic.List[string]
    #ヘッダ部
    If ($HeaderFlag) {
        $header = foreach ($col in $Grid.Columns) {
            $col.HeaderText # 列の表示名を取得
        }
        $csvLines.Add(($header -join $Separation))
    }
    #データ部
    foreach ($row in $Grid.Rows) {
        if ($row.IsNewRow) { continue }
        $values = foreach ($col in $Grid.Columns) {
            $row.Cells[$col.Index].Value
        }
        $csvLines.Add(($values -join $Separation))
    }
            
    # ファイルへ書き出し
    If ($csvLines) {
        Try {
            $csvLines | Out-File -FilePath $OutFilePath -Encoding $Encoding
            $PanelStatus2.Text = "$OutFilePath writing complete." #ステータスバー2
        } Catch {
            $PanelStatus2.Text = "$OutFilePath write error." #ステータスバー2
        }
    }
}

################################################## イニシャル処理
Set-Location -Path $PSScriptRoot  #カレントをスクリプトのフォルダに移動

#xmlファイル読み込み
$HeaderFlag = $false    #CSVヘッダ有無フラグ
$Status2 = ""
If (Test-Path $XmlFilePath) {
    Try {
        $xmlDoc = New-Object System.Xml.XmlDocument
        [xml]$xmlDoc = Get-Content -Path $XmlFilePath
        $FormTitle = $xmlDoc.config.formtitle
        $FormSize = $xmlDoc.config.formsize
        $Separation = $xmlDoc.config.separation
        $Timer.Interval = [int]$xmlDoc.config.interval
        $Grid.Font = New-Object System.Drawing.Font($xmlDoc.config.datafont, [int]$xmlDoc.config.fontsize) 
        $Encoding = $xmlDoc.config.encoding
        If ($xmlDoc.config.header -eq "true") {
            $HeaderFlag = $true
            $ChkBoxHead.Checked = $true
        }
        #ファイルリスト追加
        foreach ($node in $xmlDoc.config.filepath) {
            [void] $ComboFilePath.Items.Add($node)
        }
        If ($ComboFilePath.Rows -lt 0) { $ComboFilePath.SelectedIndex = 0 }
    } Catch {
        $Status2 = "$XmlFilePath file error."
    }
} Else {
    $Status2 = "$XmlFilePath not found."
}

If ($Status2 -ne "") {
    $FormTitle = "CsvViewer"
    $FormSize = "550, 400"
    $Separation = ","    #CSV区切り文字
    $Timer.Interval = 500
    $Grid.Font = New-Object System.Drawing.Font("ＭＳ ゴシック", 10)
    $Encoding = "UTF8"
}

# フォームの初期値表示
$Form.Text = $FormTitle
$Form.Size = $FormSize
$ComboSeparat.SelectedItem = $Separation
$ComboEnc.SelectedItem = $Encoding
$PanelStatus2.Text = $Status2

################################################## メイン処理
#---+---+---+---+---+---+---+---+---+---+ フォームを表示直後の処理
$Form.Add_Shown({
    $ComboFilePath.Select()    #フォーカスを設定
})

$Timer.Start()    #タイマー起動

#---+---+---+---+---+---+---+---+---+---+ フォーム表示
#$Form.Topmost = $true    #フォームを常に手前に表示
$Form.TopLevel = $true    #起動時は最前面に表示する(他のアプリケーションに隠れる)
$Result = $Form.ShowDialog()    #フォームを表示

################################################## 終了処理
$Timer.Stop()    #タイマー終了
Exit $Result
