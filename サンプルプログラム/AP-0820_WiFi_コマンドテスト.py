# AP-0820 WiFi コマンド動作テスト　2026/9/18
#
import socket
import sys

# 接続デバイス
DEVICE_NAME_IP = "AP-0820"  #接続デバイス名またはIPアドレスを指定
DEVICE_NAME_IP = "saitoh"  #接続デバイス名またはIPアドレスを指定
DEVICE_PORT = 9004  #接続ポートを指定

ENC_DEC = "utf-8"  #文字エンコード "utf-8"、"shift_jis"他
RECV_TIMEOUT = 5  #受信タイムアウト s タイムアウトなし:0


# 受信処理
def receive_data(sock):
    try:
        recvData = sock.recv(1024)
        if not recvData:
            print("❌機器が切断されました。")
            return False
        data = recvData.replace(b'\x1b', b'\x5e')  # ESCを'^'に変換
        data = data.rstrip(b'\x0d')  # 末尾のCRを削除
        data = data.replace(b'\x0d', b'\x0a')  # CRをLFに変換
        print(f"受信 < {data.decode(ENC_DEC, errors='ignore')}")

    except socket.timeout:
        print("❌機器からの応答がありません。")
        return False

    except Exception as e:
        print(f"受信エラー: {e}")
        return False

    return True


# メイン処理ループ
def main():
    global status, commands

    print(f"🔗 {DEVICE_NAME_IP}:{DEVICE_PORT} に接続中...")

    while True:
        sock = None
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(10)     # 接続タイムアウト 秒
            sock.connect((DEVICE_NAME_IP, DEVICE_PORT))  #接続
            print("✅ 接続しました。")
            if RECV_TIMEOUT == 0:
                sock.settimeout(None)  # タイムアウトなし
            else:
                sock.settimeout(RECV_TIMEOUT)  # 受信タイムアウト設定 秒 ※ネットワーク負荷が高い場合は長めに設定する

            print("📡 通信開始。'exit' と入力で終了します。")

            # 送受信ループ
            while True:
                # 送信コマンド入力
                sendCmd = input("送信 > ")
                if sendCmd.lower() in ("exit", "quit"):
                    break
                sendCmd += "\r"  # コマンド末尾CR追加

                # コマンド送信
                sock.sendall(sendCmd.encode(ENC_DEC))
                #print(f"送信コマンド={sendCmd}")

                # ステータス受信
                if not receive_data(sock):
                    #print("受信エラーが発生しました。")
                    break

        except KeyboardInterrupt:
            print("\n⚠️ Ctrl+C が押されたため中断します。")
            sys.exit(0)  #エラーログ表示を回避

        except Exception as e:
            print(f"通信エラー: {e}")

        finally:
            if sock:
                sock.close()  #切断
            break


if __name__ == "__main__":
    main()
    print("処理終了。")