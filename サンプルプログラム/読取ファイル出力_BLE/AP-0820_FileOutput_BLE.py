# AP-0820　読み取りデータファイル出力　2026/6/8
#
# 使用時には下記コマンドにてライブラリをインストールしてください。
# pip install bleak
#
# ●使用方法
# １．設定ファイル setting.xml を使用環境にあわせて編集する。
# ２．本ツールを起動するとリーダと接続し、読み取り状態になります。
# ３．AP-0820で読み取りしたデータをファイルに出力します。
# 
# 処理中にAP-0820との接続エラーが発生した場合、自動的に再接続を行います。
# 

import asyncio
from bleak import BleakClient, BleakScanner, BleakError
import os
import xml.etree.ElementTree as ET
from datetime import datetime

# Nordic UART Service UUIDs
UART_SERVICE_UUID = "6e400001-b5a3-f393-e0a9-e50e24dcca9e"
UART_RX_CHAR_UUID = "6e400002-b5a3-f393-e0a9-e50e24dcca9e"
UART_TX_CHAR_UUID = "6e400003-b5a3-f393-e0a9-e50e24dcca9e"

loopFlag = True     # 処理繰り返しフラグ
status: str         # ステータス
commands = []       # コマンド
recvData = bytearray() # 受信データ

# 設定ファイルの読み込み
os.chdir(os.path.dirname(__file__)) # カレントディレクトリをスクリプトと同じに場所に変更 ※exeにする場合はコメントアウト
try:
    setup = ET.parse("setting.xml").getroot()
    deviceName = setup.findtext("devicename") 
    outFilepath = setup.findtext("filepath")
    readCmd = (setup.findtext("readcmd") + "\r").encode('utf-8')   # コマンド末尾CR追加しエンコード
    interval = int(setup.findtext("interval"))
    retry = int(setup.findtext("retry"))
    dataDec = setup.findtext("datadec")
    endData = (setup.findtext("enddata") + "\r").encode('utf-8')
except Exception as e:
    print(f"setting.xmlファイル error: {e}")
    exit()


# 受信時に呼ばれるコールバック関数
def notification_handler(sender, data: bytearray):
    try:
        global recvData
        recvData += data
        if data[-1] == 0x0d:  # 末尾CR
            global status
            if len(recvData) == 3 and recvData[0] == 0x1b:  # ESC x CR
                status = chr(data[1])
                recvData.clear()
            else:
                status = "data"
    except Exception as e:
        print(f"受信処理エラー: {e}")


# 正常読み取り時処理
def read_ok():
    print(f"受信データ：{recvData.decode(dataDec, errors='ignore')}")

    # 処理終了データの確認
    if recvData == endData:
        print("処理終了データを読み取りました。")
        global loopFlag
        loopFlag = False
    else:
        # ファイル出力
        try:
            f = open(outFilepath, 'ab')  # オープン（バイナリ追記モード）
            f.write(recvData)
            f.close()  #クローズ
        except Exception as e:
            print(f"出力ファイル error: {e}")

        global commands
        recvData.clear()
        commands = [b"B1\r", b"M1\r", b"LA04\r"]    # 送信コマンドリスト


# メイン処理ループ
async def main():
    print(f"🔍 BLEデバイス{deviceName} をスキャン中...")
    try:
        devices = await BleakScanner.discover(timeout=5.0)
    except Exception as e:
        print(f"BLEスキャン error: {e}")
        return

    # 指定のデバイス名でフィルタして取得
    device = next((d for d in devices if deviceName in (d.name or "")), None)
    if not device:
        print("❌ デバイスが見つかりません。")
        return
        
    global commands
    commands = [b"I\r"]  # 装置リセットコマンド

    while loopFlag:
        print(f"🔗 {device.name} に接続中...")
        try:
            async with BleakClient(device.address, timeout=5.0) as client:
            #async with BleakClient(device.address, loop=loop) as client:  # タイムアウトなし
                print("✅ 接続しました。")
                #print(f"ネゴシエートMTUサイズ: {client.mtu_size}")

                # 通知の開始
                await client.start_notify(UART_TX_CHAR_UUID, notification_handler)

                print("📡 通信開始。読み取りを行います。CTRL+C で終了。")
                global status
                status = ""
                readWait = 0  # 次の読み取りコマンドを送信するまでの待ち時間 s
                startTime = datetime.now()

                # 送受信ループ
                while loopFlag:
                    # コマンド送信処理
                    if status == "":
                        if len(commands) > 0:
                            status = "wait"
                            await client.write_gatt_char(UART_RX_CHAR_UUID, commands[0], response=True)  # コマンド送信（応答あり）
                            #await client.write_gatt_char(UART_RX_CHAR_UUID, commands[0], response=False)  # コマンド送信（応答なし）
                            retryCmd = commands[0]  # 再送信コマンド
                            retryCnt = 0
                            commands.pop(0)                            
                            startTime = datetime.now()
                        elif (datetime.now() - startTime).seconds > readWait:
                            commands = [b"LA00\r"]
                            commands.append(readCmd)  # 読み取りコマンド
                            readWait = interval

                    await asyncio.sleep(0.01)  # 受信待機

                    # ステータス処理
                    if status == "data":  # 読み取りデータ
                        read_ok()
                        status = ""
                        startTime = datetime.now()
                    elif status == "0":
                        #print("正常応答")
                        status = ""
                    elif status == "?":
                        #print("読み取りエラー")
                        status = ""
                    elif status == "C":
                        print("コマンドエラー")
                        commands = [b"B20200\r", b"LA02\r"]
                        status = ""
                    elif status == "W":
                        print("書き込みエラー")
                        commands = [b"B20200\r", b"LA02\r"]
                        status = ""
                    else:
                        # ステータス タイムアウト（5秒間応答がない場合コマンド再送信）
                        if retryCnt < retry:
                            if (datetime.now() - startTime).seconds > 5:
                                retryCnt += 1
                                print(f"ステータス受信タイムアウト。コマンドを再送信します。retry={retryCnt}")
                                await client.write_gatt_char(UART_RX_CHAR_UUID, retryCmd, response=True)  # コマンド送信（応答あり）
                                #await client.write_gatt_char(UART_RX_CHAR_UUID, retryCmd, response=False)  # コマンド送信（応答なし）
                                startTime = datetime.now()

                    if not client.is_connected: #接続確認
                        break

                # 切断
                print("🔌 切断しました。")
                await client.stop_notify(UART_TX_CHAR_UUID)

            #await client.disconnect()

        except asyncio.TimeoutError:
            print("BLE接続・通信タイムアウト")
        except BleakError as e:
            print(f"BLE接続・通信エラー: {e}")
        except Exception as e:
            print(f"BLE接続・通信にて予期せぬエラー: {e}")
        

if __name__ == "__main__":
    asyncio.run(main())
    print("処理終了。")
    text = input("[Enter]")
