from __future__ import annotations

import argparse
import asyncio
from collections.abc import Sequence
import threading

from bluetooth_server.ble_server import DEFAULT_BLE_NAME, start_ble_server
from bluetooth_server.rfcomm_server import (
    DEFAULT_CHANNEL,
    DEFAULT_HOST,
    normalize_channel,
    start_bluetooth_server,
)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Windows Bluetooth echo server")
    parser.add_argument("--mode", choices=("rfcomm", "ble", "both"), default="rfcomm")
    parser.add_argument("--host", default=DEFAULT_HOST)
    parser.add_argument("--channel", default=str(DEFAULT_CHANNEL), type=normalize_channel)
    parser.add_argument("--ble-name", default=DEFAULT_BLE_NAME)
    return parser


async def start_both_servers(host: str, channel: int, ble_name: str) -> None:
    rfcomm_thread = threading.Thread(
        target=start_bluetooth_server,
        kwargs={"host": host, "channel": channel},
        daemon=True,
    )
    rfcomm_thread.start()
    await start_ble_server(ble_name=ble_name)


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        if args.mode == "rfcomm":
            start_bluetooth_server(host=args.host, channel=args.channel)
        elif args.mode == "ble":
            asyncio.run(start_ble_server(ble_name=args.ble_name))
        elif args.mode == "both":
            asyncio.run(
                start_both_servers(
                    host=args.host,
                    channel=args.channel,
                    ble_name=args.ble_name,
                ),
            )
    except KeyboardInterrupt:
        print("Interrupted.")
        return 130
    except Exception as exc:
        print(f"Error: {exc}")
        return 1
    return 0
