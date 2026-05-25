from __future__ import annotations

import asyncio
from contextlib import suppress
from datetime import datetime
from uuid import UUID

from bluetooth_server.protocol import build_echo_response, decode_message


DEFAULT_BLE_NAME = "BluetoothTestBridge"
BLE_SERVICE_UUID = "12345678-1234-5678-1234-56789abcdef0"
BLE_CHARACTERISTIC_UUID = "12345678-1234-5678-1234-56789abcdef1"
DEFAULT_BLE_VALUE = b"Ready\n"


async def start_ble_server(ble_name: str = DEFAULT_BLE_NAME) -> None:
    try:
        from winrt.windows.devices.bluetooth import BluetoothError  # noqa: PLC0415
        from winrt.windows.devices.bluetooth.genericattributeprofile import (  # noqa: PLC0415
            GattCharacteristicProperties,
            GattLocalCharacteristicParameters,
            GattProtectionLevel,
            GattServiceProvider,
            GattServiceProviderAdvertisementStatus,
            GattServiceProviderAdvertisingParameters,
            GattWriteOption,
        )
        from winrt.windows.storage.streams import (  # noqa: PLC0415
            DataReader,
            DataWriter,
        )
    except ImportError as exc:
        raise RuntimeError(
            "Windows WinRT Bluetooth packages are not installed. Run `uv sync` on Windows.",
        ) from exc

    def make_buffer(value: bytes | bytearray):
        writer = DataWriter()
        writer.write_bytes(bytes(value))
        return writer.detach_buffer()

    state = _BleState(make_buffer)

    service_result = await GattServiceProvider.create_async(UUID(BLE_SERVICE_UUID))
    if service_result.error != BluetoothError.SUCCESS:
        raise RuntimeError(f"failed to create BLE GATT service: {service_result.error}")
    service_provider = service_result.service_provider
    if service_provider is None or service_provider.service is None:
        raise RuntimeError("failed to create BLE GATT service provider")

    char_parameters = GattLocalCharacteristicParameters()
    char_parameters.characteristic_properties = (
        GattCharacteristicProperties.READ
        | GattCharacteristicProperties.WRITE
        | GattCharacteristicProperties.NOTIFY
    )
    char_parameters.read_protection_level = GattProtectionLevel.PLAIN
    char_parameters.write_protection_level = GattProtectionLevel.PLAIN
    char_parameters.static_value = make_buffer(DEFAULT_BLE_VALUE)
    char_parameters.user_description = "Bluetooth test echo"

    char_result = await service_provider.service.create_characteristic_async(
        UUID(BLE_CHARACTERISTIC_UUID),
        char_parameters,
    )
    if char_result.error != BluetoothError.SUCCESS:
        raise RuntimeError(f"failed to create BLE GATT characteristic: {char_result.error}")
    characteristic = char_result.characteristic
    if characteristic is None:
        raise RuntimeError("failed to create BLE GATT characteristic")

    def read_characteristic(_sender, args) -> None:
        deferral = args.get_deferral()

        async def respond() -> None:
            try:
                request = await args.get_request_async()
                request.respond_with_value(make_buffer(state.value))
            finally:
                deferral.complete()

        asyncio.run_coroutine_threadsafe(respond(), state.loop)

    def write_characteristic(_sender, args) -> None:
        deferral = args.get_deferral()

        async def respond() -> None:
            try:
                request = await args.get_request_async()
                reader = DataReader.from_buffer(request.value)
                value = bytearray()
                for _ in range(reader.unconsumed_buffer_length):
                    value.append(reader.read_byte())
                state.receive(value, characteristic)
                if request.option == GattWriteOption.WRITE_WITH_RESPONSE:
                    request.respond()
            finally:
                deferral.complete()

        asyncio.run_coroutine_threadsafe(respond(), state.loop)

    characteristic.add_read_requested(read_characteristic)
    characteristic.add_write_requested(write_characteristic)

    adv_parameters = GattServiceProviderAdvertisingParameters()
    adv_parameters.is_discoverable = True
    adv_parameters.is_connectable = True

    service_provider.start_advertising_with_parameters(adv_parameters)

    print(f"BLE GATT server advertising as {ble_name}.")
    print(f"Service: {BLE_SERVICE_UUID}")
    print(f"Characteristic: {BLE_CHARACTERISTIC_UUID}")
    print("Press Ctrl+C to stop.")

    try:
        await _wait_for_advertising_start(
            service_provider,
            GattServiceProviderAdvertisementStatus,
        )
        await asyncio.Event().wait()
    finally:
        with suppress(Exception):
            service_provider.stop_advertising()
        print("BLE GATT server stopped.")


async def _wait_for_advertising_start(service_provider, status_type) -> None:
    for _ in range(50):
        if service_provider.advertisement_status in (
            status_type.STARTED,
            status_type.STARTED_WITHOUT_ALL_ADVERTISEMENT_DATA,
        ):
            return
        await asyncio.sleep(0.1)
    raise RuntimeError(
        f"BLE GATT advertising did not start: {service_provider.advertisement_status}",
    )


class _BleState:
    def __init__(self, make_buffer):
        self.loop = asyncio.get_running_loop()
        self.value = bytearray(DEFAULT_BLE_VALUE)
        self._make_buffer = make_buffer

    def receive(self, value: bytearray, characteristic) -> None:
        try:
            message = decode_message(bytes(value))
        except ValueError:
            return

        print(f"BLE received {datetime.now().isoformat(timespec='seconds')}: {message}")
        self.value = bytearray(build_echo_response(message))
        characteristic.static_value = self._make_buffer(self.value)
        characteristic.notify_value_async(self._make_buffer(self.value))
