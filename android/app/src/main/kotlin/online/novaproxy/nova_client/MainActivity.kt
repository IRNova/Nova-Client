package online.novaproxy.nova_client

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts the Flutter UI and the proxy control/event channels.
 *
 * `nova.proxy/control` (MethodChannel): start / stop / status.
 * `nova.proxy/events`  (EventChannel):  state + traffic stream.
 *
 * Starting the tunnel first requests the system VPN consent dialog
 * ([VpnService.prepare]); on grant it launches [NovaVpnService].
 */
class MainActivity : FlutterActivity() {
    private val controlChannel = "nova.proxy/control"
    private val eventChannel = "nova.proxy/events"
    private val vpnRequestCode = 0x4E56 // "NV"

    private var pendingResult: MethodChannel.Result? = null
    private var pendingConfig: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, controlChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val config = call.argument<String>("configJson")
                    if (config.isNullOrEmpty()) {
                        result.error("no_config", "configJson missing", null)
                        return@setMethodCallHandler
                    }
                    val consent = VpnService.prepare(this)
                    if (consent != null) {
                        pendingResult = result
                        pendingConfig = config
                        startActivityForResult(consent, vpnRequestCode)
                    } else {
                        startVpn(config)
                        result.success(null)
                    }
                }

                "stop" -> {
                    stopVpn()
                    result.success(null)
                }

                "status" -> result.success(NovaProxyBridge.state)

                else -> result.notImplemented()
            }
        }

        EventChannel(messenger, eventChannel).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    NovaProxyBridge.setSink(events)
                }

                override fun onCancel(arguments: Any?) {
                    NovaProxyBridge.setSink(null)
                }
            },
        )
    }

    private fun startVpn(config: String) {
        val intent = Intent(this, NovaVpnService::class.java)
            .putExtra(NovaVpnService.EXTRA_CONFIG, config)
        startService(intent)
    }

    private fun stopVpn() {
        val intent = Intent(this, NovaVpnService::class.java)
            .setAction(NovaVpnService.ACTION_STOP)
        startService(intent)
    }

    @Deprecated("Using onActivityResult for the VpnService consent dialog")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != vpnRequestCode) return
        val result = pendingResult
        val config = pendingConfig
        pendingResult = null
        pendingConfig = null
        if (resultCode == Activity.RESULT_OK && config != null) {
            startVpn(config)
            result?.success(null)
        } else {
            NovaProxyBridge.emitError("VPN permission denied")
            result?.error("vpn_denied", "VPN permission denied", null)
        }
    }
}
