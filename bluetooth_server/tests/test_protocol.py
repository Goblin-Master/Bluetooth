import unittest
from unittest.mock import patch
from contextlib import redirect_stderr
import io

from bluetooth_server.ble_server import (
    BLE_CHARACTERISTIC_UUID,
    BLE_SERVICE_UUID,
    _BleState,
)
from bluetooth_server.cli import build_parser
from bluetooth_server.protocol import build_echo_response, decode_message, handle_payload
from bluetooth_server.rfcomm_server import DEFAULT_CHANNEL, normalize_channel


class ProtocolTest(unittest.TestCase):
    def test_decode_message_trims_utf8_text(self):
        self.assertEqual(decode_message("  hello Windows  \r\n".encode()), "hello Windows")

    def test_decode_message_rejects_empty_payload(self):
        with self.assertRaises(ValueError):
            decode_message(b" \n")

    def test_build_echo_response_uses_newline(self):
        self.assertEqual(build_echo_response("hello"), b"Echo: hello\n")

    def test_handle_payload_filters_empty_messages(self):
        self.assertIsNone(handle_payload(b" \r\n"))
        self.assertEqual(handle_payload(" ping ".encode()), b"Echo: ping\n")

    def test_normalize_channel_accepts_rfcomm_range(self):
        self.assertEqual(normalize_channel("1"), 1)
        self.assertEqual(normalize_channel("30"), 30)

    def test_normalize_channel_rejects_out_of_range_values(self):
        with self.assertRaises(ValueError):
            normalize_channel("0")
        with self.assertRaises(ValueError):
            normalize_channel("31")

    def test_cli_defaults_to_rfcomm_mode_and_default_channel(self):
        args = build_parser().parse_args([])

        self.assertEqual(args.mode, "rfcomm")
        self.assertEqual(args.channel, DEFAULT_CHANNEL)

    def test_cli_accepts_explicit_rfcomm_mode_and_channel(self):
        args = build_parser().parse_args(["--mode", "rfcomm", "--channel", "4"])

        self.assertEqual(args.mode, "rfcomm")
        self.assertEqual(args.channel, 4)

    def test_cli_accepts_ble_and_both_modes(self):
        ble_args = build_parser().parse_args(["--mode", "ble"])
        both_args = build_parser().parse_args(
            ["--mode", "both", "--channel", "5"],
        )

        self.assertEqual(ble_args.mode, "ble")
        self.assertEqual(both_args.mode, "both")
        self.assertEqual(both_args.channel, 5)

    def test_cli_rejects_ble_name_option(self):
        stderr = io.StringIO()
        with self.assertRaises(SystemExit):
            with redirect_stderr(stderr):
                build_parser().parse_args(["--mode", "ble", "--ble-name", "Bridge"])

    def test_ble_gatt_uses_fixed_bridge_uuids(self):
        self.assertEqual(BLE_SERVICE_UUID, "12345678-1234-5678-1234-56789abcdef0")
        self.assertEqual(
            BLE_CHARACTERISTIC_UUID,
            "12345678-1234-5678-1234-56789abcdef1",
        )

    def test_ble_state_notifies_echo_without_mutating_static_value(self):
        class Characteristic:
            def __init__(self):
                self.notified = None

            def notify_value_async(self, value):
                self.notified = value

        async def scenario():
            state = _BleState(bytes)
            characteristic = Characteristic()

            state.receive(bytearray(b"hello"), characteristic)

            self.assertEqual(state.value, bytearray(b"Echo: hello\n"))
            self.assertEqual(characteristic.notified, b"Echo: hello\n")
            self.assertFalse(hasattr(characteristic, "static_value"))

        import asyncio

        asyncio.run(scenario())

    def test_main_dispatches_rfcomm_mode(self):
        from bluetooth_server.cli import main

        with patch("bluetooth_server.cli.start_bluetooth_server") as start_server:
            result = main(["--mode", "rfcomm", "--channel", "4"])

        self.assertEqual(result, 0)
        start_server.assert_called_once_with(host="00:00:00:00:00:00", channel=4)

    def test_main_dispatches_ble_mode(self):
        from bluetooth_server.cli import main

        with patch("bluetooth_server.cli.asyncio.run") as run:
            result = main(["--mode", "ble"])

        self.assertEqual(result, 0)
        coroutine = run.call_args.args[0]
        coroutine.close()

    def test_main_dispatches_both_mode(self):
        from bluetooth_server.cli import main

        with patch("bluetooth_server.cli.asyncio.run") as run:
            result = main(["--mode", "both", "--channel", "4"])

        self.assertEqual(result, 0)
        coroutine = run.call_args.args[0]
        coroutine.close()


if __name__ == "__main__":
    unittest.main()
