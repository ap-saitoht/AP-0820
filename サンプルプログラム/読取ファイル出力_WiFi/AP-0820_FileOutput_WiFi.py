# AP-0820　読み取りデータファイル出力　Wi-Fi 2026/6/11
#
# ●使用方法
# １．設定ファイル setting.xml を使用環境にあわせて編集する。
# ２．本ツールを起動するとリーダと接続し、読み取り状態になります。
# ３．AP-0820で読み取りしたデータをファイルに出力します。
# 
# 処理中にAP-0820との接続エラーが発生した場合、自動的に再接続を行います。

import socket
import os
import xml.etree.ElementTree as ET
from datetime import datetime
import time

loopFlag = True
status = ""
commands = []
readData = b""

# 設定ファイル読み込み
os.chdir(os.path.dirname(__file__)) # カレントディレクトリをスクリプトと同じに場所に変更 ※exeにする場合はコメントアウト
try:
    setup = ET.parse("setting.xml").getroot()
    ip = setup.findtext("ip")
    port = int(setup.findtext("port"))
    outFilepath = setup.findtext("filepath")
    readCmd = (setup.findtext("readcmd") + "\r").encode('utf-8')
    interval = float(setup.findtext("interval"))
    connectChk = float(setup.findtext("connectChk"))
    dataDec = setup.findtext("datadec")
    endData = (setup.findtext("enddata") + "\r").encode('utf-8')
except Exception as e:
    print(f"setting.xml error: {e}")
    exit()


# 受信処理
def receive_data(sock):
    global status, readData
    connectChk = False  #接続確認フラグ
    while True:
        try:
            data = sock.recv(1024)
            if not data:
                print("❌機器が切断されました。")
                return False

            if data[0] == 0x1b and len(data) == 3:
                status = chr(data[1])
                #print(f"受信ステータス：{status}")
            else:
                print(f"受信データ：{data.decode(dataDec, errors='ignore')}")
                status = "data"
                readData = data

        except socket.timeout:  # 無限待ち防止のためタイムアウト設定
            #接続状態の確認
            if connectChk:
                print("❌機器からの応答がありません。")
                return False
            sock.sendall(b"\x05\r") # ENQ
            connectChk = True
            continue

        except Exception as e:
            print(f"受信エラー: {e}")
            return False

        return True


# 正常読み取り時処理
def read_ok():
    global loopFlag, commands

    if readData == endData:
        print("処理終了データを読み取りました。")
        loopFlag = False
    else:
        try:
            with open(outFilepath, 'ab') as f:
                f.write(readData)
        except Exception as e:
            print(f"ファイル出力エラー: {e}")

        commands = [b"B1\r", b"M1\r", b"LA04\r", "interval", b"LA00\r", readCmd]


def main():
    global status, commands

    print(f"🔗 {ip}:{port} に接続中...")

    while loopFlag:
        sock = None
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(10)     # 接続タイムアウト 秒
            sock.connect((ip, port))
            print("✅ 接続しました。")
            if connectChk == 0:
                sock.settimeout(None)  # タイムアウトなし
            else:
                sock.settimeout(connectChk)  # 受信タイムアウト設定 秒 ※ネットワーク負荷が高い場合は長めに設定する

            commands = [b"I\r", readCmd]
            status = ""

            while loopFlag:
                # コマンド送信
                if len(commands) > 0:
                    if status == "":
                        if commands[0] == "interval":
                            time.sleep(interval)  # 読み取り間隔待機
                            commands.pop(0)
                            continue
                        status = "wait"
                        sock.sendall(commands[0])
                        #print(f"送信コマンド={commands[0]}")
                        commands.pop(0)

                # 受信処理
                if not receive_data(sock):
                    print("❌通信が切断されました。")
                    break

                # ステータス処理
                if status == "data":
                    read_ok()
                    status = ""

                elif status == "0":
                    status = ""

                elif status == "?":
                    commands = [b"LA02\r", "interval", readCmd]
                    status = ""

                elif status == "C":
                    print("コマンドエラー")
                    commands = [b"B20200\r", b"LA0A\r", "interval", readCmd]
                    status = ""

                elif status == "W":
                    print("書き込みエラー")
                    commands = [b"B20200\r", b"LA0A\r", "interval", readCmd]
                    status = ""

                elif status == chr(0x06):   # ACK
                    pass

        except Exception as e:
            print(f"通信エラー: {e}")

        finally:
            print("再接続します...")
            if sock:
                sock.close()
            
        time.sleep(3)  # 接続待ち s

if __name__ == "__main__":
    main()
    print("処理終了")
    input("[Enter]")