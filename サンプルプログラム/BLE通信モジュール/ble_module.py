# BLE通信モジュール　2026/10/26
#
# BLEデバイス接続：ble_interactive.py [デバイス名]
# デバイスからの受信については IDLE_TIMEOUT の時間内にデータが来なければ、そのデータを終端とみなして処理を行います。

import sys
import asyncio
from bleak import BleakScanner, BleakClient

UART_SERVICE_UUID = "6e400001-b5a3-f393-e0a9-e50e24dcca9e"
UART_RX_CHAR_UUID = "6e400002-b5a3-f393-e0a9-e50e24dcca9e"
UART_TX_CHAR_UUID = "6e400003-b5a3-f393-e0a9-e50e24dcca9e"

DEVICE_RESPONSE_TIMEOUT = 3.0  # デバイス応答のタイムアウト（秒）
IDLE_TIMEOUT = 0.1  # データ終端とみなすまでの無通信時間（秒）
recv_buffer = bytearray()
response_event = asyncio.Event()
idle_timer = None

# 標準入力から1行（改行まで）を非同期で読み込む
async def read_stdin_line():
    loop = asyncio.get_running_loop()
    def blocking_readline():
        return sys.stdin.buffer.readline()
    return await loop.run_in_executor(None, blocking_readline)

# BLEデバイスからの通知を受信するコールバック関数（無通信タイムアウト方式）
def notification_handler(sender, data: bytearray):
    global recv_buffer, idle_timer
    recv_buffer.extend(data)
    
    # 既存のタイマーがあればキャンセル
    if idle_timer is not None:
        idle_timer.cancel()
    
    # 一定時間新しいデータが来なければ response_event をセットするタスクをスケジュール
    loop = asyncio.get_running_loop()
    async def set_event_after_idle():
        try:
            await asyncio.sleep(IDLE_TIMEOUT)
            response_event.set()
        except asyncio.CancelledError:
            pass

    idle_timer = loop.create_task(set_event_after_idle())

async def print_output(text: str):
    sys.stdout.buffer.write(text.encode("utf-8") + b"\n")
    sys.stdout.buffer.flush()

async def main():
    if len(sys.argv) < 2:
        await print_output("ERROR: Device name argument is required.")
        sys.exit(1)

    deviceName = sys.argv[1]

    sys.stdout.buffer.write(b"Scanning...\n")
    sys.stdout.buffer.flush()
    devices = await BleakScanner.discover(timeout=DEVICE_RESPONSE_TIMEOUT)
    device = next((d for d in devices if deviceName in (d.name or "")), None)

    if not device:
        await print_output("ERROR: Device not found")
        sys.exit(1)

    await print_output(f"Connecting to {device.name}")
    try:
        async with BleakClient(device.address, timeout=DEVICE_RESPONSE_TIMEOUT) as client:
            await client.start_notify(UART_TX_CHAR_UUID, notification_handler)
            mtu_size = client.mtu_size - 3

            await print_output("READY") # 接続完了通知

            global recv_buffer
            while True:
                cmd_bytes = await read_stdin_line()
                if not cmd_bytes: 
                    break

                cmd_bytes = cmd_bytes.rstrip(b"\r\n")
                if not cmd_bytes:
                    continue

                response_event.clear()
                recv_buffer.clear()
                
                # BLE送信（MTUサイズに分割して送信）
                send_data = cmd_bytes + b"\r"
                for i in range(0, len(send_data), mtu_size):
                    chunk = send_data[i:i + mtu_size]
                    await client.write_gatt_char(UART_RX_CHAR_UUID, chunk, response=True)

                # デバイスからの応答待ち（全体タイムアウト ＋ 無通信判定）
                try:
                    await asyncio.wait_for(response_event.wait(), timeout=DEVICE_RESPONSE_TIMEOUT)
                    sys.stdout.buffer.write(b":" + bytes(recv_buffer) + b"\n")
                    sys.stdout.buffer.flush()
 
                except asyncio.TimeoutError:
                    await print_output("RESPONSE_ERROR: Timeout waiting for BLE device")

            await client.stop_notify(UART_TX_CHAR_UUID)

    except Exception as e:
        await print_output(f"ERROR: {e}")
    finally:
        await print_output("Disconnected")

if __name__ == "__main__":
    asyncio.run(main())
