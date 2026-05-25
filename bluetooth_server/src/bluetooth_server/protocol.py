from __future__ import annotations


def decode_message(data: bytes) -> str:
    message = data.decode("utf-8", errors="replace").strip()
    if not message:
        raise ValueError("empty message")
    return message


def build_echo_response(message: str) -> bytes:
    return f"Echo: {message}\n".encode("utf-8")


def handle_payload(data: bytes) -> bytes | None:
    try:
        message = decode_message(data)
    except ValueError:
        return None
    return build_echo_response(message)
