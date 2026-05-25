from __future__ import annotations

import asyncio
from contextlib import suppress
from datetime import datetime

from bluetooth_server.protocol import build_echo_response, decode_message


DEFAULT_BLE_NAME = "BluetoothTestBridge"
BLE_SERVICE_UUID = "12345678-1234-5678-1234-56789abcdef0"
BLE_CHARACTERISTIC_UUID = "12345678-1234-5678-1234-56789abcdef1"
DEFAULT_BLE_VALUE = b"Ready\n"


async def start_ble_server(ble_name: str = DEFAULT_BLE_NAME) -> None:
    try:
        from bless import (  # noqa: PLC0415
            BlessServer,
            GATTAttributePermissions,
            GATTCharacteristicProperties,
        )
    except ImportError as exc:
        raise RuntimeError(
            "bless is not installed correctly. Run `uv sync` on Windows.",
        ) from exc

    server = BlessServer(name=ble_name)
    state = _BleState(server)

    server.read_request_func = state.read_request
    server.write_request_func = state.write_request

    await server.add_new_service(BLE_SERVICE_UUID)
    await server.add_new_characteristic(
        BLE_SERVICE_UUID,
        BLE_CHARACTERISTIC_UUID,
        (
            GATTCharacteristicProperties.read
            | GATTCharacteristicProperties.write
            | GATTCharacteristicProperties.notify
        ),
        bytearray(DEFAULT_BLE_VALUE),
        GATTAttributePermissions.readable | GATTAttributePermissions.writeable,
    )

    await server.start()
    print(f"BLE GATT server advertising as {ble_name}.")
    print(f"Service: {BLE_SERVICE_UUID}")
    print(f"Characteristic: {BLE_CHARACTERISTIC_UUID}")
    print("Press Ctrl+C to stop.")

    try:
        await asyncio.Event().wait()
    finally:
        with suppress(Exception):
            await server.stop()
        print("BLE GATT server stopped.")


class _BleState:
    def __init__(self, server):
        self._server = server
        self._value = bytearray(DEFAULT_BLE_VALUE)

    def read_request(self, characteristic) -> bytearray:
        return bytearray(characteristic.value or self._value)

    def write_request(self, characteristic, value: bytearray) -> None:
        try:
            message = decode_message(bytes(value))
        except ValueError:
            return

        print(f"BLE received {datetime.now().isoformat(timespec='seconds')}: {message}")
        self._value = bytearray(build_echo_response(message))
        characteristic.value = self._value
        self._server.update_value(BLE_SERVICE_UUID, BLE_CHARACTERISTIC_UUID)
