import unittest

from bluetooth_server.bt_server import build_echo_response, decode_message, normalize_channel


class ProtocolTest(unittest.TestCase):
    def test_decode_message_trims_utf8_text(self):
        self.assertEqual(decode_message("  hello Windows  \r\n".encode()), "hello Windows")

    def test_decode_message_rejects_empty_payload(self):
        with self.assertRaises(ValueError):
            decode_message(b" \n")

    def test_build_echo_response_uses_newline(self):
        self.assertEqual(build_echo_response("hello"), b"Echo: hello\n")

    def test_normalize_channel_accepts_rfcomm_range(self):
        self.assertEqual(normalize_channel("1"), 1)
        self.assertEqual(normalize_channel("30"), 30)

    def test_normalize_channel_rejects_out_of_range_values(self):
        with self.assertRaises(ValueError):
            normalize_channel("0")
        with self.assertRaises(ValueError):
            normalize_channel("31")


if __name__ == "__main__":
    unittest.main()
