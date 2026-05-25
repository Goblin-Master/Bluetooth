from __future__ import annotations

import socket
import sys

from bluetooth_server.protocol import decode_message, build_echo_response


DEFAULT_HOST = "00:00:00:00:00:00"
DEFAULT_CHANNEL = 4
BUFFER_SIZE = 1024


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
