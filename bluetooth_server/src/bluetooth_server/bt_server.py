from bluetooth_server.cli import build_parser, main
from bluetooth_server.protocol import build_echo_response, decode_message, handle_payload
from bluetooth_server.rfcomm_server import (
    BUFFER_SIZE,
    DEFAULT_CHANNEL,
    DEFAULT_HOST,
    ensure_windows_bluetooth_socket,
    normalize_channel,
    start_bluetooth_server,
)


if __name__ == "__main__":
    raise SystemExit(main())
