#!/usr/bin/env node
/**
 * A slow phone connection for the Android emulator, which ignores its own
 * network-speed setting: a CONNECT proxy whose tunnels all share one link of
 * a fixed speed.
 *
 *   node slow-proxy.mjs <port> <kbit/s down> <kbit/s up>
 *   adb shell settings put global http_proxy 10.0.2.2:<port>   # slow
 *   adb shell settings put global http_proxy :0                # back to normal
 *
 * Android's HTTP stacks (HttpURLConnection, OkHttp: ExoPlayer, React Native's
 * fetch, Firebase) honour the system proxy, so the app's data and its media
 * both go through it. Check the speed before trusting it: time a download
 * from the host (`curl -x http://127.0.0.1:<port> -o /dev/null <url>`).
 * Only CONNECT is served: everything the app reaches is HTTPS.
 */
import net from 'node:net';

const [port, down, up] = process.argv.slice(2).map(Number);
if (![port, down, up].every((n) => Number.isFinite(n) && n > 0)) {
  console.error('usage: node slow-proxy.mjs <port> <kbit/s down> <kbit/s up>');
  process.exit(2);
}

/** One direction of the link: how long a chunk waits so bytes leave no faster than `kbps`. */
function link(kbps) {
  const bytesPerMs = (kbps * 1000) / 8 / 1000;
  let freeAt = Date.now();
  return (chunk) => {
    const start = Math.max(Date.now(), freeAt);
    freeAt = start + chunk.length / bytesPerMs;
    return Math.max(0, freeAt - Date.now());
  };
}
const downLink = link(down);
const upLink = link(up);

/** Forward `from` to `to`, each chunk when the link has room for it. */
function pace(from, to, wait) {
  from.on('data', (chunk) => {
    from.pause();
    setTimeout(() => {
      to.write(chunk);
      from.resume();
    }, wait(chunk));
  });
  from.on('end', () => to.end());
  from.on('error', () => to.destroy());
}

net
  .createServer((client) => {
    client.once('data', (head) => {
      const m = /^CONNECT ([^:\s]+):(\d+) HTTP/.exec(head.toString());
      if (!m) {
        client.end('HTTP/1.1 405 Only CONNECT\r\n\r\n');
        return;
      }
      const remote = net.connect(Number(m[2]), m[1], () => {
        client.write('HTTP/1.1 200 Connection Established\r\n\r\n');
        pace(remote, client, downLink);
        pace(client, remote, upLink);
      });
      remote.on('error', () => client.destroy());
      client.on('error', () => remote.destroy());
    });
  })
  .listen(port, '127.0.0.1', () => console.log(`slow proxy on 127.0.0.1:${port}: ${down} kbit/s down, ${up} up`));
