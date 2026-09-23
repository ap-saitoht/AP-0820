# AP-0820 BLE ファイル取得　2026/6/8
#
# 使用時には下記コマンドにてライブラリをインストールしてください。
# pip install bleak
#
import asyncio
from bleak import BleakClient, BleakScanner
from datetime import datetime

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

                # 通知を取得
                await client.start_notify(UART_TX_CHAR_UUID, notification_handler)

                print("📡 通信開始。'exit' と入力で終了します。")

                # 送受信ループ
                while True:
                    # ファイル名入力
                    sendCmd = input("取得するファイル名を入力してください（f00～f99）: ")
                    if sendCmd.lower() in ("exit", "quit"):
                        loopFlag = False
                        break
                    if not sendCmd.startswith("f") or not sendCmd[1:].isdigit() or not (0 <= int(sendCmd[1:]) <= 99):
                        print("❌ 無効なファイル名です。f00～f99の形式で入力してください。")
                        continue
                    sendCmd += "\r"  # コマンド末尾CR追加

                    # コマンド送信
                    await client.write_gatt_char(UART_RX_CHAR_UUID, sendCmd.encode(ENC_DEC), response=True)  # コマンド送信（応答あり）
                    #await client.write_gatt_char(UART_RX_CHAR_UUID, sendCmd.encode(ENC_DEC), response=False)  # コマンド送信（応答なし）

                    # ステータス受信
                    global recvData
                    dataLen = 0
                    startTime = datetime.now()
                    timeoutFlag = True
                    while (datetime.now() - startTime).seconds < RECV_TIMEOUT:  # 受信タイムアウト s
                        if len(recvData) > dataLen:
                            dataLen = len(recvData)
                            if dataLen > 3:
                                if recvData[-3] == 0x1b and recvData[-2] == 0x65 and recvData[-1] == 0x0d:  # ESC e CR
                                    timeoutFlag = False
                                    break
                            startTime = datetime.now()
                        await asyncio.sleep(0.01)  # 受信待ち
                    if timeoutFlag:
                        print("❌ 受信タイムアウト")
                        if len(recvData) == 0:
                            continue

                    # 受信データ表示
                    #data = recvData.replace(b'\x1b', b'\x5e')  # ESCを'^'に変換
                    data = recvData.replace(b'\x0d', b'\x0a')  # CRをLFに変換
                    print(data.decode(ENC_DEC, errors='ignore'))  #受信データ表示

                    recvData = b''  #受信バッファクリア

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
