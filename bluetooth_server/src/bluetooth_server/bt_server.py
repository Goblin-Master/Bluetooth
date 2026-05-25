from __future__ import annotations

import argparse
import socket
import sys
from collections.abc import Sequence


DEFAULT_HOST = "00:00:00:00:00:00"
DEFAULT_CHANNEL = 1
BUFFER_SIZE = 1024


def decode_message(data: bytes) -> str:
    message = data.decode("utf-8", errors="replace").strip()
    if not message:
        raise ValueError("empty message")
    return message


def build_echo_response(message: str) -> bytes:
    return f"Echo: {message}\n".encode("utf-8")


def normalize_channel(value: str | int) -> int:
    try:
        channel = int(value)
    except (TypeError, ValueError) as exc:
        raise ValueError("channel must be an integer") from exc
    if channel < 1 or channel > 30:
        raise ValueError("channel must be between 1 and 30")
    return channel


def start_bluetooth_server(host: str = DEFAULT_HOST, channel: int = DEFAULT_CHANNEL) -> None:
    ensure_windows_bluetooth_socket()
    server_sock = socket.socket(
        socket.AF_BLUETOOTH,
        socket.SOCK_STREAM,
        socket.BTPROTO_RFCOMM,
    )
    client_sock: socket.socket | None = None

    try:
        server_sock.bind((host, channel))
        server_sock.listen(1)
        print(f"Server listening on RFCOMM channel {channel}.")
        print("Pair the phone with Windows first, then connect from Flutter.")

        client_sock, client_info = server_sock.accept()
        print(f"Accepted connection from {client_info[0]} on channel {client_info[1]}.")

        while True:
            data = client_sock.recv(BUFFER_SIZE)
            if not data:
                print("Client disconnected.")
                break

            try:
                message = decode_message(data)
            except ValueError:
                continue

            print(f"Received: {message}")
            client_sock.sendall(build_echo_response(message))
    finally:
        if client_sock is not None:
            client_sock.close()
        server_sock.close()
        print("Server stopped.")


def ensure_windows_bluetooth_socket() -> None:
    missing = [
        name
        for name in ("AF_BLUETOOTH", "BTPROTO_RFCOMM")
        if not hasattr(socket, name)
    ]
    if missing:
        names = ", ".join(missing)
        raise RuntimeError(
            f"Python socket is missing {names}. Run this server on Windows Python 3.9+.",
        )
    if sys.platform != "win32":
        raise RuntimeError("Run this RFCOMM server on Windows, not WSL.")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Windows RFCOMM echo server")
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
        print(f"Error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
