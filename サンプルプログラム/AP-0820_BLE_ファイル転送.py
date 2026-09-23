# AP-0820 BLE ファイル転送　2026/6/8
#
# 使用時には下記コマンドにてライブラリをインストールしてください。
# pip install bleak
#
import asyncio
from bleak import BleakClient, BleakScanner
from datetime import datetime
from tkinter import filedialog

# BLE Device Name
#DEVICE_NAME = "AP-0820"  #接続デバイス名
DEVICE_NAME = ""  #未指定時はスキャンして一覧から選択

# Nordic UART Service UUIDs
UART_SERVICE_UUID = "6e400001-b5a3-f393-e0a9-e50e24dcca9e"
UART_RX_CHAR_UUID = "6e400002-b5a3-f393-e0a9-e50e24dcca9e"
UART_TX_CHAR_UUID = "6e400003-b5a3-f393-e0a9-e50e24dcca9e"

ENC_DEC = "utf-8"  #文字エンコード "utf-8"、"shift_jis"他
RECV_TIMEOUT = 10  #受信タイムアウト s
recvData = b''   #受信データバッファ

# 受信時に呼ばれるコールバック関数
def notification_handler(sender, data: bytearray):
    try:
        global recvData
        recvData += data  #受信バッファへコピー
    except Exception as e:
        print(f"受信処理エラー: {e}")

# メイン処理ループ
async def main():
    print(f"🔍 BLEデバイス{DEVICE_NAME} をスキャン中...")
    try:
        devices = await BleakScanner.discover(timeout=3.0)
    except Exception as e:
        print(f"BLE error: {e}")
        return

    if DEVICE_NAME == "":
        # スキャンしてユーザーが一覧から選択する場合
        for i, d in enumerate(devices):
            print(f"{i}: {d.name} [{d.address}]")
        if not devices:
            print("❌ デバイスが見つかりませんでした。")
            return
        index = int(input("\n接続したいデバイス番号を選んでください: "))
        if len(devices) <= index:
            return
        device = devices[index]
    else:
        # 指定のデバイス名でフィルタして接続したい場合
        device = next((d for d in devices if DEVICE_NAME in (d.name or "")), None)
        if not device:
            print("❌ デバイスが見つかりませんでした。")
            return
        
    print(f"🔗 {device.name} に接続中...")
    loopFlag = True # 繰り返しフラグ

    while loopFlag:
        try:
            async with BleakClient(device.address, timeout=5.0) as client:
            #async with BleakClient(device.address, loop=loop) as client:  # タイムアウトなし
                print("✅ 接続成功！")
                print(f"ネゴシエートMTUサイズ: {client.mtu_size}")
                mtuSize = client.mtu_size - 3  # MTUサイズからATTヘッダ分を引く

                # 通知を取得
                await client.start_notify(UART_TX_CHAR_UUID, notification_handler)

                print("📡 通信開始。'exit' と入力で終了します。")

                # 送受信ループ
                while True:
                    # 送信コマンド入力
                    fCmd = input("転送先のファイル名を入力してください（f00～f99）: ")
                    if fCmd.lower() in ("exit", "quit"):
                        loopFlag = False
                        break
                    if not fCmd.startswith("f") or not fCmd[1:].isdigit() or not (0 <= int(fCmd[1:]) <= 99):
                        print("❌ 無効なファイル名です。f00～f99の形式で入力してください。")
                        continue

                    # ファイル選択ダイアログ表示
                    filename = filedialog.askopenfilename ( initialdir = "./", initialfile = "*.csv", title = "転送するファイルを選択してください", filetypes = (("CSV files","*.csv"),("All files","*.*")) )
                    if not filename:
                        print("❌ ファイルが選択されませんでした。")
                        continue

                    # ファイル内容を１レコードずつ読み込んで送信
                    count = 0
                    with open(filename, "r", encoding=ENC_DEC) as f:
                        for line in f:
                            sendCmd = fCmd + ("+" if count > 0 else "=") + line.rstrip("\r\n") + "\r"
                            count += 1
                            print(f"{count}: {line.strip()}")  #送信コマンド表示
                            cmdBytes = sendCmd.encode(ENC_DEC)

                            # MTUサイズに分割して送信
                            for i in range(0, len(cmdBytes), mtuSize):
                                chunk = cmdBytes[i:i + mtuSize]
                                #await client.write_gatt_char(UART_RX_CHAR_UUID, chunk, response=True)  # コマンド送信（応答あり）
                                await client.write_gatt_char(UART_RX_CHAR_UUID, chunk, response=False)  # コマンド送信（応答なし）

                            # ステータス受信
                            global recvData
                            recvData = b''  #受信バッファクリア
                            startTime = datetime.now()
                            timeoutFlag = True
                            while (datetime.now() - startTime).seconds < RECV_TIMEOUT:  # 受信タイムアウト s
                                if len(recvData) > 0:
                                    if recvData[-1] == 0x0d:  # CR
                                        timeoutFlag = False
                                        break
                                await asyncio.sleep(0.01)  # 受信待ち
                            if timeoutFlag:
                                print("❌ 受信タイムアウト")
                                break

                            if len(recvData) != 3 or recvData[0] != 0x1b or recvData[1] != 0x30:  # ESC 0 CR 以外
                                data = [0xa5 if x == 0x1b else x for x in recvData]  # ESCを'･'に変換
                                print(f"❌ ステータスエラー: {data.decode(ENC_DEC, errors='ignore')}")
                                break

                    if not client.is_connected: #接続確認
                        break

                # 切断
                print("🔌 切断しました。")
                await client.stop_notify(UART_TX_CHAR_UUID)

        except Exception as e:
            print(f"BLE error: {e}")
            errFlag = True
            text = input("再接続しますか？[Y/N]")
            if not (text  in ("Y", "y")):
                loopFlag = False

if __name__ == "__main__":
    asyncio.run(main())
    print("処理終了。")
