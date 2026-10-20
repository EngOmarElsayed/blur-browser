#!/usr/bin/env python3
"""Loopback relay for LAN model servers.

macOS Local Network privacy can refuse an app's direct connections to 192.168.x.x
(error -1009, "Local network prohibited"), even when the browser's WebKit process
can reach the same host. Loopback is never gated, so this forwards a local port to
the model server and the app talks to 127.0.0.1 instead.

Usage:
    python3 tools/relay.py --listen 127.0.0.1:18080 --target 192.168.1.150:8080
"""

import argparse
import asyncio


async def pipe(reader, writer):
    try:
        while True:
            data = await reader.read(65536)
            if not data:
                break
            writer.write(data)
            await writer.drain()
    except Exception:
        pass
    finally:
        try:
            writer.close()
        except Exception:
            pass


async def handle(client_reader, client_writer, host, port):
    try:
        remote_reader, remote_writer = await asyncio.open_connection(host, port)
    except Exception:
        client_writer.close()
        return
    await asyncio.gather(
        pipe(client_reader, remote_writer),
        pipe(remote_reader, client_writer),
    )


async def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--listen", default="127.0.0.1:18080")
    parser.add_argument("--target", default="192.168.1.150:8080")
    args = parser.parse_args()

    listen_host, listen_port = args.listen.rsplit(":", 1)
    target_host, target_port = args.target.rsplit(":", 1)

    server = await asyncio.start_server(
        lambda r, w: handle(r, w, target_host, int(target_port)),
        listen_host,
        int(listen_port),
    )
    print("relay %s -> %s" % (args.listen, args.target), flush=True)
    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    asyncio.run(main())
