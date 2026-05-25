from __future__ import annotations

import argparse
from collections.abc import Sequence

from bluetooth_server.rfcomm_server import (
    DEFAULT_CHANNEL,
    DEFAULT_HOST,
    normalize_channel,
    start_bluetooth_server,
)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Windows Bluetooth echo server")
    parser.add_argument("--mode", choices=("rfcomm",), default="rfcomm")
    parser.add_argument("--host", default=DEFAULT_HOST)
    parser.add_argument("--channel", default=str(DEFAULT_CHANNEL), type=normalize_channel)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        start_bluetooth_server(host=args.host, channel=args.channel)
    except KeyboardInterrupt:
        print("Interrupted.")
        return 130
    except Exception as exc:
        print(f"Error: {exc}")
        return 1
    return 0
