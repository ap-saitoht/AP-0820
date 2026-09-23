# AP-0820　ファイル連携ツール　2026/6/6
#
# 使用時には下記コマンドにてライブラリをインストールしてください。
# pip install bleak
#
# ●使用方法
# １．設定ファイル setting.ini を使用環境にあわせて編集する。
# ２．ツールが起動すると機器との接続を行いファイル連携を開始します。
#
# ●動作
# １．本ツールを起動すると active.txt と command.txt を作成後、error.txt があれば削除します。
# ２．ツールにて機器との接続が完了すると status.txt（ESC P CR）を作成後、command.txt を削除します。
# ３．アプリからステータスを読み込む際は、command.txt が存在せず、status.txt が見つかったら読み込みをします。
# ４．アプリからコマンドを書き込む際は、command.txt を作成後に status.txt を削除します。
# ５．ツールにて status.txt が削除されたのを確認して、command.txt を読み込みコマンドを機器へ送信し command.txt を削除します。
# ６．ツールが機器からのステータスを受信すると command.txt を作成後、 status.txt に書き出し、command.txt を削除します。
# ７．3.から処理を繰り返します。
# 
# ●機器との通信にてエラーが発生した場合
# 通信が切断した場合などでもツールは停止せず、再接続を行い動作を継続します。
# エラーが発生した都度 error.txt にエラー内容を追記した後、command.txt を削除します。
# アプリでエラーを取得したい場合には error.txt を読み込みして削除してください。
# 
# ●終了方法
# アプリから active.txt を削除します。
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

recvData = b''   #受信データバッファ

# 設定ファイルの読み込み
os.chdir(os.path.dirname(__file__)) # カレントディレクトリをスクリプトと同じに場所に変更 ※exeにする場合はコメントアウト
try:
    setup = ET.parse("setting.xml").getroot()
    deviceName = setup.findtext("devicename") 
    folderPath = setup.findtext("folderpath")
    delay = int(setup.findtext("delay")) / 1000
    retry = int(setup.findtext("retry"))
    dataEncDec = setup.findtext("dataencdec")
except Exception as e:
    print(f"setting.xmlファイル error: {e}")
    exit()

# 起動時ファイル処理
os.chdir(folderPath) # カレントディレクトリを変更
try:
    # 実行中ファイル作成
    f = open('active.txt', 'w', encoding=dataEncDec)  #上書き
    f.close()

    # エラーファイル削除
    if os.path.isfile('error.txt'):
        os.remove('error.txt')

except Exception as e:
    print(f"起動時ファイル error: {e}")
    exit()


# 受信時に呼ばれるコールバック関数
def notification_handler(sender, data: bytearray):
    try:
        global recvData
        recvData += data
    except Exception as e:
        print(f"受信処理エラー: {e}")


# エラー発生時ファイル出力
def outputErrFile(errMsg):
    if not os.path.isfile('command.txt'):  #コマンドファイル確認
        f = open('command.txt', 'w')  # 空コマンドファイル作成
        f.close()
    f = open('error.txt', 'a', encoding=dataEncDec)  # エラーファイル作成 追記
    f.write(errMsg + "\r")  # 書き込み
    f.close()
    os.remove('command.txt')  # コマンドファイル削除


# メイン処理ループ
async def main():
    while os.path.isfile('active.txt'):  # 実行中ファイル確認
        print(f"🔍 BLEデバイス{deviceName} をスキャン中...")
        try:
            devices = await BleakScanner.discover(timeout=3.0)
        except Exception as e:
            print(f"BLEスキャン error: {e}")
            outputErrFile("BLEスキャン error")

        # 指定のデバイス名でフィルタして接続
        device = next((d for d in devices if deviceName in (d.name or "")), None)
        if not device:
            print("❌ デバイスが見つかりません。")
            outputErrFile("BLEデバイスが見つかりません。")
        else:
            break
        
    while os.path.isfile('active.txt'):  # 実行中ファイル確認
        print(f"🔗 {device.name} に接続中...")
        try:
            async with BleakClient(device.address, timeout=5.0) as client:
            #async with BleakClient(device.address, loop=loop) as client:  # タイムアウトなし
                print("✅ 接続しました。")
                print(f"ネゴシエートMTUサイズ: {client.mtu_size}")
                mtuSize = client.mtu_size - 3  # MTUサイズからATTヘッダ分を引く

                # 通知の開始
                await client.start_notify(UART_TX_CHAR_UUID, notification_handler)

                print("📡 通信開始。CTRL+C で終了。")

                # 接続後の連携ファイル処理
                if not os.path.isfile('command.txt'):  # コマンドファイルが無ければ空ファイル作成
                    f = open('command.txt', 'w')
                    f.close()
                f = open('status.txt', 'w', encoding=dataEncDec)  # ステータスファイル作成
                f.write(chr(0x1b) + "P\r")  # ESC P CR書き込み
                f.close()
                os.remove('command.txt')  # コマンドファイル削除
                retryCnt = retry
                startTime = datetime.now()

                # 送受信ループ
                while os.path.isfile('active.txt'):  # 実行中ファイル確認
                    #コマンド送信
                    if os.path.isfile('command.txt') and not os.path.isfile('status.txt'):  # コマンド、ステータスファイル確認
                        f = open('command.txt', 'r', encoding=dataEncDec)
                        cmd = f.readline()
                        f.close()
                        if cmd[-1] == chr(0x0a):  # コマンド末尾LF
                            cmd = cmd[:-1] + "\r" #LF削除してCR追加

                        print(f"送信コマンド：{cmd}")  # デバッグ表示用

                        # MTUサイズに分割して送信
                        cmdBytes = cmd.encode(dataEncDec)
                        for i in range(0, len(cmdBytes), mtuSize):
                            chunk = cmdBytes[i:i + mtuSize]
                            await client.write_gatt_char(UART_RX_CHAR_UUID, chunk, response=True)  # コマンド送信（応答あり）
                            #await client.write_gatt_char(UART_RX_CHAR_UUID, chunk, response=False)  # コマンド送信（応答なし）
                        os.remove('command.txt')  # コマンドファイル削除
                        retryCmd = cmd  # 再送信コマンド
                        retryCnt = 0
                        startTime = datetime.now()

                    # ステータス受信
                    global recvData
                    if len(recvData) > 0:
                        if recvData[-1] == 0x0d:
                            # デバッグ表示用
                            stat = recvData.decode(dataEncDec, errors='ignore')
                            print(f"受信ステータス：{ stat if stat[0] != chr(0x1b) else stat[1:]}")

                            if not os.path.isfile('command.txt'):  #コマンドファイル確認
                                f = open('command.txt', 'w')  # 空コマンドファイル作成
                                f.close()
                                f = open('status.txt', 'wb')  # ステータスファイル作成（バイナリ）
                                f.write(recvData)  # 書き込み
                                f.close()
                                os.remove('command.txt')  # コマンドファイル削除
                            recvData = b''  #受信バッファクリア
                            retryCnt = retry
                    else:
                        # ステータス タイムアウト（5秒間応答がない場合コマンド再送信）
                        if retryCnt < retry:
                            if (datetime.now() - startTime).seconds > 5:
                                retryCnt += 1
                                print(f"ステータス受信タイムアウト。コマンドを再送信します。retry={retryCnt}")

                                # MTUサイズに分割して再送信
                                retryCmdBytes = retryCmd.encode(dataEncDec)
                                for i in range(0, len(retryCmdBytes), client.mtu_size):
                                    chunk = retryCmdBytes[i:i + client.mtu_size]
                                    await client.write_gatt_char(UART_RX_CHAR_UUID, chunk, response=True)  # コマンド送信（応答あり）
                                    #await client.write_gatt_char(UART_RX_CHAR_UUID, chunk, response=False)  # コマンド送信（応答なし）
                                startTime = datetime.now()
                    
                    #ループディレイ
                    await asyncio.sleep(delay)

                    if not client.is_connected: #接続確認
                        break

                # 切断
                print("🔌 切断しました。")
                await client.stop_notify(UART_TX_CHAR_UUID)

            #await client.disconnect()

        except asyncio.TimeoutError:
            print("BLE接続・通信タイムアウト")
            outputErrFile("BLE通信 タイムアウト")
        except BleakError as e:
            print(f"BLE接続・通信エラー: {e}")
            outputErrFile("BLE通信 error")
        except Exception as e:
            print(f"BLE接続・通信にて予期せぬエラー: {e}")
            outputErrFile("BLE通信 予期せぬエラー")


if __name__ == "__main__":
    try:
        asyncio.run(main())
    finally:
        os.remove('active.txt')  # 実行中ファイル削除

    print("処理終了。")
    #text = input("[Enter]")
