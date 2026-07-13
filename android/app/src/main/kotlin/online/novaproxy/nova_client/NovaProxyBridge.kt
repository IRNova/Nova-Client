package online.novaproxy.nova_client

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

/**
 * Bridges the native VpnService and the Flutter EventChannel.
 *
 * The service emits lifecycle/traffic events through here; [MainActivity]
 * registers the active [EventChannel.EventSink]. Events are always delivered on
 * the main thread, matching the contract documented in SingboxProxyController.
 */
object NovaProxyBridge {
    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var eventSink: EventChannel.EventSink? = null

    @Volatile
    var state: String = "disconnected"
        private set

    fun setSink(sink: EventChannel.EventSink?) {
        eventSink = sink
    }

    fun emitState(value: String) {
        state = value
        post(mapOf("type" to "state", "value" to value))
    }

    fun emitError(message: String?) {
        state = "error"
        post(mapOf("type" to "error", "message" to (message ?: "unknown error")))
    }

    fun emitTraffic(up: Long, down: Long, upTotal: Long, downTotal: Long) {
        post(
            mapOf(
                "type" to "traffic",
                "up" to up,
                "down" to down,
                "upTotal" to upTotal,
                "downTotal" to downTotal,
            ),
        )
    }

    private fun post(event: Map<String, Any?>) {
        val sink = eventSink ?: return
        mainHandler.post { runCatching { sink.success(event) } }
    }
}
