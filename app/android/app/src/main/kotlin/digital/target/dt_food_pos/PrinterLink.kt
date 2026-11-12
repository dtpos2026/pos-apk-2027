package digital.target.dt_food_pos

import android.annotation.SuppressLint
import android.app.PendingIntent
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.BluetoothSocket
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.os.Build
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * Gets ESC/POS bytes to a receipt printer, the three ways cheap portable printers listen:
 * classic Bluetooth (SPP, three connection tricks), Bluetooth Low Energy (GATT write) and USB (OTG cable).
 * Every function blocks, so call them off the main thread. Failures throw Exception with a plain sentence that lists what was tried.
 */
@SuppressLint("MissingPermission")
class PrinterLink(private val ctx: Context) {
    /** How fast bytes are pushed: small printers with small buffers drop data when it comes too fast. */
    class Speed(val chunk: Int, val delayMs: Long)

    private fun speed(name: String) = when (name) {
        "fast" -> Speed(1024, 10)
        "safe" -> Speed(96, 50)
        else -> Speed(384, 22)
    }

    private val adapter get() = (ctx.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager).adapter

    private fun device(address: String): BluetoothDevice {
        val a = adapter ?: throw Exception("This phone has no Bluetooth.")
        if (!a.isEnabled) throw Exception("Bluetooth is off. Turn it on to print.")
        a.cancelDiscovery()
        return a.getRemoteDevice(address)
    }

    private fun typeName(d: BluetoothDevice) = when (d.type) {
        BluetoothDevice.DEVICE_TYPE_CLASSIC -> "classic"
        BluetoothDevice.DEVICE_TYPE_LE -> "le"
        BluetoothDevice.DEVICE_TYPE_DUAL -> "dual"
        else -> "unknown"
    }

    /** What Android knows about a paired printer: used by the printer test screen. */
    fun info(address: String): Map<String, Any> {
        val d = device(address)
        val uuids = d.uuids?.map { it.toString().lowercase() } ?: emptyList()
        return mapOf(
            "name" to (d.name ?: d.address),
            "address" to d.address,
            "type" to typeName(d),
            "bonded" to (d.bondState == BluetoothDevice.BOND_BONDED),
            "uuids" to uuids,
            "spp" to uuids.contains(SPP.toString()),
        )
    }

    // ---------- classic Bluetooth (SPP) ----------

    /** Returns the way that worked: "spp", "spp-insecure", "spp-port1", or "ble" when only Low Energy answered. */
    fun printBluetooth(address: String, bytes: ByteArray, speedName: String): String {
        val d = device(address)
        val failures = ArrayList<String>()
        val kind = d.type
        if (kind != BluetoothDevice.DEVICE_TYPE_LE) {
            val tries = listOf<Pair<String, () -> BluetoothSocket>>(
                "spp" to { d.createRfcommSocketToServiceRecord(SPP) },
                "spp-insecure" to { d.createInsecureRfcommSocketToServiceRecord(SPP) },
                // the trick many cheap printers need: connect straight to channel 1 without asking for the service
                "spp-port1" to { d.javaClass.getMethod("createRfcommSocket", Int::class.javaPrimitiveType).invoke(d, 1) as BluetoothSocket },
            )
            for ((route, make) in tries) {
                // only a failed CONNECT moves on to the next way; once connected, a failure is reported as it is,
                // so a half-sent slip is never sent a second time
                var socket: BluetoothSocket? = null
                try {
                    socket = make()
                    socket.connect()
                } catch (e: Exception) {
                    failures.add("$route: ${e.message}")
                    try { socket?.close() } catch (_: Exception) {}
                    Thread.sleep(300)
                    continue
                }
                val s = socket!!
                try {
                    sendStream(s.outputStream, bytes, speed(speedName))
                } catch (e: Exception) {
                    throw Exception("Printer ${d.name ?: address} connected ($route) but the data did not go through (${e.message}). Try the Safe speed in the printer test.")
                } finally {
                    try { s.close() } catch (_: Exception) {}
                }
                return route
            }
        }
        // a classic-only printer cannot answer over Low Energy: say what failed without a 12-second wait
        if (kind == BluetoothDevice.DEVICE_TYPE_CLASSIC) {
            throw Exception("Printer ${d.name ?: address} (classic Bluetooth) did not connect. Tried ${failures.joinToString("; ")}. Is it switched on, not connected to another phone, and close by?")
        }
        // a printer that only speaks Low Energy, or one whose classic link refused every try
        try {
            printBle(d, bytes, speedName)
            return "ble"
        } catch (e: Exception) {
            failures.add("ble: ${e.message}")
        }
        throw Exception("Printer ${d.name ?: address} (${typeName(d)}) did not take the data. Tried ${failures.joinToString("; ")}")
    }

    private fun sendStream(out: java.io.OutputStream, bytes: ByteArray, sp: Speed) {
        Thread.sleep(150) // let the printer finish waking up after the link opens
        out.write(byteArrayOf(0x1B, 0x40)) // ESC @: start from a clean state
        out.flush()
        Thread.sleep(60)
        var i = 0
        while (i < bytes.size) {
            val n = minOf(sp.chunk, bytes.size - i)
            out.write(bytes, i, n)
            out.flush()
            i += n
            Thread.sleep(sp.delayMs)
        }
        Thread.sleep(600 + (bytes.size / 200).toLong().coerceAtMost(3000)) // let the printer drain before the link closes
    }

    // ---------- Bluetooth Low Energy ----------

    @Suppress("DEPRECATION")
    private fun printBle(d: BluetoothDevice, bytes: ByteArray, speedName: String) {
        val sp = speed(speedName)
        val ready = CountDownLatch(1)
        val written = arrayOfNulls<CountDownLatch>(1)
        var problem: String? = null
        var mtu = 23
        val cb = object : BluetoothGattCallback() {
            override fun onConnectionStateChange(g: BluetoothGatt, status: Int, newState: Int) {
                if (newState == BluetoothProfile.STATE_CONNECTED) {
                    g.requestMtu(185)
                } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                    if (ready.count > 0) problem = "disconnected (status $status)"
                    ready.countDown()
                    written[0]?.countDown()
                }
            }

            override fun onMtuChanged(g: BluetoothGatt, m: Int, status: Int) {
                if (status == BluetoothGatt.GATT_SUCCESS) mtu = m
                g.discoverServices()
            }

            override fun onServicesDiscovered(g: BluetoothGatt, status: Int) {
                if (status != BluetoothGatt.GATT_SUCCESS) problem = "service discovery failed (status $status)"
                ready.countDown()
            }

            override fun onCharacteristicWrite(g: BluetoothGatt, c: BluetoothGattCharacteristic, status: Int) {
                if (status != BluetoothGatt.GATT_SUCCESS) problem = "write failed (status $status)"
                written[0]?.countDown()
            }
        }
        val gatt: BluetoothGatt = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) d.connectGatt(ctx, false, cb, BluetoothDevice.TRANSPORT_LE) else d.connectGatt(ctx, false, cb)
        try {
            if (!ready.await(12, TimeUnit.SECONDS)) throw Exception("no answer over Low Energy")
            problem?.let { throw Exception(it) }
            val target = pickWritable(gatt) ?: throw Exception("no writable service found")
            val noResponse = target.properties and BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE != 0
            val type = if (noResponse) BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE else BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
            val chunk = minOf(maxOf(mtu - 3, 20), sp.chunk)
            var i = 0
            while (i < bytes.size) {
                val part = bytes.copyOfRange(i, minOf(i + chunk, bytes.size))
                written[0] = CountDownLatch(1)
                val ok = if (Build.VERSION.SDK_INT >= 33) {
                    gatt.writeCharacteristic(target, part, type) == BluetoothGatt.GATT_SUCCESS
                } else {
                    target.writeType = type
                    target.value = part
                    gatt.writeCharacteristic(target)
                }
                if (!ok) throw Exception("the printer refused a write")
                // a write without response gets no callback on many phones: only the pacing delay applies
                if (!noResponse && !written[0]!!.await(4, TimeUnit.SECONDS)) throw Exception("write timed out")
                problem?.let { throw Exception(it) }
                i += part.size
                Thread.sleep(sp.delayMs)
            }
            Thread.sleep(600)
        } finally {
            try { gatt.disconnect() } catch (_: Exception) {}
            try { gatt.close() } catch (_: Exception) {}
        }
    }

    private fun pickWritable(g: BluetoothGatt): BluetoothGattCharacteristic? {
        val all = g.services.flatMap { it.characteristics }
        val writable = all.filter { it.properties and (BluetoothGattCharacteristic.PROPERTY_WRITE or BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE) != 0 }
        // the characteristics cheap thermal printers are known to use, then anything writable
        for (known in BLE_PRINTER_CHARACTERISTICS) writable.firstOrNull { it.uuid.toString().lowercase().startsWith(known) }?.let { return it }
        return writable.firstOrNull()
    }

    // ---------- USB (OTG cable) ----------

    fun usbDevices(): List<Map<String, Any>> {
        val m = ctx.getSystemService(Context.USB_SERVICE) as UsbManager
        return m.deviceList.values.map { d ->
            val label: String = d.productName ?: "USB device ${"%04x".format(d.vendorId)}:${"%04x".format(d.productId)}"
            mapOf(
                "name" to d.deviceName,
                "id" to usbId(d),
                "label" to label,
                "printer" to (0 until d.interfaceCount).any { d.getInterface(it).interfaceClass == UsbConstants.USB_CLASS_PRINTER },
            )
        }
    }

    private fun usbId(d: UsbDevice) = "%04x:%04x".format(d.vendorId, d.productId)

    /** Sends the bytes to a USB printer. Asks for Android's "allow this app to use the device" permission the first time. */
    fun printUsb(deviceName: String, bytes: ByteArray, speedName: String): String {
        val m = ctx.getSystemService(Context.USB_SERVICE) as UsbManager
        // the printer is saved as "vendor:product" because Android renumbers the device name each time the cable is plugged in
        val d: UsbDevice = m.deviceList.values.firstOrNull { usbId(it) == deviceName || it.deviceName == deviceName } ?: throw Exception("The USB printer is not connected. Plug the cable in (an OTG adapter is needed for most phones).")
        if (!m.hasPermission(d)) requestUsbPermission(m, d)
        val sp = speed(speedName)
        // the printer interface (class 7) first, then any interface that has a bulk OUT endpoint
        val candidates = (0 until d.interfaceCount).map { d.getInterface(it) }.sortedBy { if (it.interfaceClass == UsbConstants.USB_CLASS_PRINTER) 0 else 1 }
        for (itf in candidates) {
            val ep = (0 until itf.endpointCount).map { itf.getEndpoint(it) }.firstOrNull { it.type == UsbConstants.USB_ENDPOINT_XFER_BULK && it.direction == UsbConstants.USB_DIR_OUT } ?: continue
            val conn = m.openDevice(d) ?: throw Exception("Android would not open the USB printer.")
            try {
                if (!conn.claimInterface(itf, true)) continue
                val init = byteArrayOf(0x1B, 0x40)
                conn.bulkTransfer(ep, init, init.size, 3000)
                Thread.sleep(60)
                var i = 0
                while (i < bytes.size) {
                    val n = minOf(sp.chunk, bytes.size - i)
                    val sent = conn.bulkTransfer(ep, bytes, i, n, 5000)
                    if (sent <= 0) throw Exception("the USB printer stopped accepting data")
                    i += sent
                    Thread.sleep(sp.delayMs / 2)
                }
                Thread.sleep(500)
                conn.releaseInterface(itf)
                return "usb"
            } finally {
                conn.close()
            }
        }
        throw Exception("This USB device has no printer data endpoint.")
    }

    private fun requestUsbPermission(m: UsbManager, d: UsbDevice) {
        val action = "${ctx.packageName}.USB_PERMISSION"
        val latch = CountDownLatch(1)
        var granted = false
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(c: Context, i: Intent) {
                granted = i.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
                latch.countDown()
            }
        }
        if (Build.VERSION.SDK_INT >= 33) ctx.registerReceiver(receiver, IntentFilter(action), Context.RECEIVER_NOT_EXPORTED) else ctx.registerReceiver(receiver, IntentFilter(action))
        try {
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0)
            m.requestPermission(d, PendingIntent.getBroadcast(ctx, 0, Intent(action).setPackage(ctx.packageName), flags))
            if (!latch.await(40, TimeUnit.SECONDS) || !granted) throw Exception("USB permission was not given. Tap Allow when Android asks.")
        } finally {
            try { ctx.unregisterReceiver(receiver) } catch (_: Exception) {}
        }
    }

    companion object {
        val SPP: UUID = UUID.fromString("00001101-0000-1000-8000-00805f9b34fb")

        /** Writable characteristics (by UUID prefix) used by common Chinese portable printers. */
        val BLE_PRINTER_CHARACTERISTICS = listOf("0000ffe1", "0000ff02", "bef8d6c9", "49535343-8841", "00002af1", "0000fff2")
    }
}
