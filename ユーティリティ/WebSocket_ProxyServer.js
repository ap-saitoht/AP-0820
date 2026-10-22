// WebSocket中継プロキシサーバー
// ブラウザの標準機能だけではセキュリティ上TCPソケットを直接開いてデータのみを送受信することはできません。
// そのため、Node.jsにて中継サーバーを立ててデータを変換して送受信します。
// ※本スクリプトをGoogleドライブなどから起動はできません。ローカル環境で実行してください。
// 事前のインストール準備：npm install ws
// 
// WebSocket_config.json
// {
//   "websocketHost": "localhost",  -> ブラウザからの接続ホスト名またはIPアドレス
//   "websocketPort": 8080,         -> ブラウザとの接続ポート
//   "exitOnDisconnect": false      -> ブラウザまたはAP-0820が切断されたら中継サーバーも終了する場合はtrue
// }

// jsonから設定を読み込み
const CONFIG_FILENAME = 'WebSocket_config.json';
const fs = require('node:fs');
const path = require('node:path');
let config;
try {
    const configPath = path.join(__dirname, CONFIG_FILENAME);
    const configFile = fs.readFileSync(configPath, 'utf8');
    config = JSON.parse(configFile);
} catch (err) {
    console.error('設定ファイル (' + CONFIG_FILENAME + ') の読み込みに失敗しました:', err.message);
    process.exit(1);
}

console.log('WebSocket 中継プロキシサーバーを起動します。');
console.log(`ブラウザ[${config.websocketHost || '0.0.0.0'}:${config.websocketPort}] からの接続を待っています...`);
const WebSocket = require('ws');
const net = require('node:net');

const wss = new WebSocket.Server({ 
  host: config.websocketHost || '0.0.0.0', 
  port: config.websocketPort 
});

wss.on('error', (err) => {
    console.error('中継サーバーでエラーが発生しました:', err);
});

wss.on('connection', (ws, req) => {
    // ブラウザの接続URLからクエリパラメータ（?host=xxx&port=yyy）を解析
    const dummyBase = `http://${req.headers.host || 'localhost'}`;
    const myUrl = new URL(req.url, dummyBase);
    const tcpServerHost = myUrl.searchParams.get('host');
    const tcpServerPort = parseInt(myUrl.searchParams.get('port'), 10);
    if (!tcpServerHost || !tcpServerPort || isNaN(tcpServerPort)) {
        console.error('エラー: ブラウザからの接続URLに正しく host または port が指定されていません。');
        console.error(`接続拒否されたURL: ${req.url}`);
        ws.close(4000, 'Invalid query parameters. Required: ?host=XXX&port=YYY');
        return;
    }

    console.log(`ブラウザが接続されました。\nAP-0820[${tcpServerHost}:${tcpServerPort}] へ接続を開始します...`);

    // WebSocketエラーハンドリング
    ws.on('error', (err) => {
        console.error('WebSocket接続エラー:', err);
    });

    const tcpClient = new net.Socket();
    
    // TCP接続のエラーハンドリング（サーバーが起動していない場合）
    tcpClient.on('error', () => {
        console.error('AP-0820との接続エラー');
        ws.close();
    });

    tcpClient.connect(tcpServerPort, tcpServerHost, () => {
        console.log(`AP-0820と接続が成功しました。`);
    });

    // ブラウザからのデータをAP-0820へ送信
    ws.on('message', (message, isBinary) => {
        if (isBinary) {
            tcpClient.write(message, (err) => {
                if (err) {
                    console.error('AP-0820へのデータ送信に失敗しました:', err);
                } else {
                    console.log(`[ブラウザ -> AP-0820] ${message.byteLength} bytes 送信しました。`);
                }
            });
        }
    });

    // AP-0820からのデータをブラウザへ送信
    tcpClient.on('data', (data) => {
        ws.send(data, { binary: true }, (err) => {
            if (err) {
                console.error('ブラウザへのデータ送信失敗:', err);
            } else {
                console.log(`[AP-0820 -> ブラウザ] ${data.byteLength} bytes 送信しました。`);
            }
        });
    });

    // ブラウザの切断確認
    ws.on('close', () => {
        console.log('ブラウザが切断されました。');
        tcpClient.end();
        if (config.exitOnDisconnect) {
            console.log('処理を終了します。');
            process.exit(0);
        }
    });

    // AP-0820の切断確認
    tcpClient.on('close', () => {
        console.log('AP-0820が切断されました。');
        ws.close();
        if (config.exitOnDisconnect) {
            console.log('処理を終了します。');
            process.exit(0);
        }
    });
});
