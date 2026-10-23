package digital.target.dt_food_pos

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothManager
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import android.os.Build
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.Executors

/**
 * The few Android features DT Food POS needs, without third-party plugins:
 * a stable phone id, classic-Bluetooth (SPP) ESC/POS printing, runtime permissions and one location fix.
 * Channel: "digital.target/device". Every call answers on the main thread; slow work runs on [io].
 */
class MainActivity : FlutterActivity() {
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var pendingPermission: MethodChannel.Result? = null
    private val permissionRequestCode = 4711

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "digital.target/device").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "phoneId" -> result.success(phoneId())
                    "hasPermissions" -> result.success(hasAll(perms(call)))
                    "requestPermissions" -> requestPermissions(perms(call), result)
                    "bluetoothPaired" -> bluetoothPaired(result)
                    "bluetoothPrint" -> bluetoothPrint(call, result)
                    "location" -> location(result)
                    "openWhatsApp" -> result.success(openWhatsApp(call.argument<String>("phone") ?: "", call.argument<String>("text") ?: ""))
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("device", e.message ?: e.toString(), null)
            }
        }
    }

    /** SHA-256 of ANDROID_ID + package: the same after reinstalling (same signing key), different per app, not the IMEI. */
    @SuppressLint("HardwareIds")
    private fun phoneId(): String? {
        val raw = Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID) ?: return null
        val digest = MessageDigest.getInstance("SHA-256").digest("$raw:$packageName".toByteArray())
        return digest.joinToString("") { "%02x".format(it) }.substring(0, 20)
    }

    private fun perms(call: MethodCall): List<String> = (call.argument<List<String>>("permissions") ?: emptyList()).filter { applies(it) }

    /** Bluetooth runtime permissions exist from Android 12; older versions grant Bluetooth at install time. */
    private fun applies(p: String): Boolean =
        when (p) {
            "android.permission.BLUETOOTH_CONNECT", "android.permission.BLUETOOTH_SCAN" -> Build.VERSION.SDK_INT >= Build.VERSION_CODES.S
            else -> true
        }

    private fun hasAll(list: List<String>) = list.all { checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }

    private fun requestPermissions(list: List<String>, result: MethodChannel.Result) {
        if (hasAll(list)) return result.success(true)
        if (pendingPermission != null) return result.error("busy", "A permission request is already open", null)
        pendingPermission = result
        requestPermissions(list.toTypedArray(), permissionRequestCode)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != permissionRequestCode) return
        val r = pendingPermission ?: return
        pendingPermission = null
        r.success(grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED })
    }

    @SuppressLint("MissingPermission")
    private fun bluetoothPaired(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !hasAll(listOf(Manifest.permission.BLUETOOTH_CONNECT))) {
            return result.error("permission", "Bluetooth permission is not given. Allow \"Nearby devices\" for DT Food POS.", null)
        }
        val adapter = (getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager).adapter
            ?: return result.error("unsupported", "This phone has no Bluetooth.", null)
        if (!adapter.isEnabled) return result.error("off", "Bluetooth is off. Turn it on and try again.", null)
        result.success(adapter.bondedDevices.map { mapOf("name" to (it.name ?: it.address), "address" to it.address) })
    }

    @SuppressLint("MissingPermission")
    private fun bluetoothPrint(call: MethodCall, result: MethodChannel.Result) {
        val address = call.argument<String>("address") ?: return result.error("args", "No printer address", null)
        val bytes = call.argument<ByteArray>("bytes") ?: return result.error("args", "Nothing to print", null)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !hasAll(listOf(Manifest.permission.BLUETOOTH_CONNECT))) {
            return result.error("permission", "Bluetooth permission is not given. Allow \"Nearby devices\" for DT Food POS.", null)
        }
        val adapter = (getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager).adapter
            ?: return result.error("unsupported", "This phone has no Bluetooth.", null)
        if (!adapter.isEnabled) return result.error("off", "Bluetooth is off. Turn it on to print.", null)
        io.execute {
            try {
                val device = adapter.getRemoteDevice(address)
                adapter.cancelDiscovery()
                device.createRfcommSocketToServiceRecord(SPP).use { socket ->
                    socket.connect()
                    val out = socket.outputStream
                    var i = 0
                    while (i < bytes.size) {
                        val n = minOf(1024, bytes.size - i)
                        out.write(bytes, i, n)
                        out.flush()
                        i += n
                        Thread.sleep(15) // small printers have small buffers
                    }
                    Thread.sleep(400) // let the printer drain before the link closes
                }
                main.post { result.success(true) }
            } catch (e: Exception) {
                main.post { result.error("print", "Bluetooth printer $address did not print (${e.message}). Is it on, paired and in range?", null) }
            }
        }
    }

    /** One location fix: the freshest last-known position, or a new one (Android 11+), within 15 seconds. */
    @SuppressLint("MissingPermission")
    private fun location(result: MethodChannel.Result) {
        val fine = hasAll(listOf(Manifest.permission.ACCESS_FINE_LOCATION))
        val coarse = hasAll(listOf(Manifest.permission.ACCESS_COARSE_LOCATION))
        if (!fine && !coarse) return result.success(null)
        val lm = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        val providers = lm.getProviders(true)
        val last = providers.mapNotNull { runCatching { lm.getLastKnownLocation(it) }.getOrNull() }.maxByOrNull { it.time }
        if (last != null && System.currentTimeMillis() - last.time < 10 * 60 * 1000) return result.success(toMap(last))
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R || providers.isEmpty()) return result.success(last?.let { toMap(it) })
        val provider = if (LocationManager.GPS_PROVIDER in providers && fine) LocationManager.GPS_PROVIDER else providers.first()
        val signal = CancellationSignal()
        var answered = false
        val done = { l: Location? ->
            if (!answered) {
                answered = true
                result.success((l ?: last)?.let { toMap(it) })
            }
        }
        main.postDelayed({ signal.cancel(); done(null) }, 15000)
        lm.getCurrentLocation(provider, signal, mainExecutor) { done(it) }
    }

    /** Opens a WhatsApp chat with the message typed in; the user presses Send. WhatsApp, then WhatsApp Business, then the browser. */
    private fun openWhatsApp(phone: String, text: String): Boolean {
        val uri = Uri.parse("https://wa.me/$phone?text=" + Uri.encode(text))
        for (pkg in listOf("com.whatsapp", "com.whatsapp.w4b", null)) {
            try {
                val intent = Intent(Intent.ACTION_VIEW, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                if (pkg != null) intent.setPackage(pkg)
                startActivity(intent)
                return true
            } catch (_: ActivityNotFoundException) {
                // try the next app
            }
        }
        return false
    }

    private fun toMap(l: Location) = mapOf("lat" to l.latitude, "lng" to l.longitude, "accuracy" to l.accuracy.toDouble(), "time" to l.time)

    override fun onDestroy() {
        io.shutdown()
        super.onDestroy()
    }

    companion object {
        private val SPP: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
    }
}
