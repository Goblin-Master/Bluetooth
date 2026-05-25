import unittest

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


if __name__ == "__main__":
    unittest.main()
