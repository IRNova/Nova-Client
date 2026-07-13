package online.novaproxy.nova_client

import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.system.OsConstants
import io.nekohasekai.libbox.CommandServer
import io.nekohasekai.libbox.CommandServerHandler
import io.nekohasekai.libbox.ConnectionOwner
import io.nekohasekai.libbox.InterfaceUpdateListener
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.LocalDNSTransport
import io.nekohasekai.libbox.Notification
import io.nekohasekai.libbox.NetworkInterfaceIterator
import io.nekohasekai.libbox.OverrideOptions
import io.nekohasekai.libbox.PlatformInterface
import io.nekohasekai.libbox.SetupOptions
import io.nekohasekai.libbox.StringIterator
import io.nekohasekai.libbox.SystemProxyStatus
import io.nekohasekai.libbox.TunOptions
import io.nekohasekai.libbox.WIFIState
import java.io.File
import java.net.InetSocketAddress
import java.net.NetworkInterface as JavaNetworkInterface
import io.nekohasekai.libbox.NetworkInterface as LibboxNetworkInterface

/**
 * The sing-box tunnel host. Implements the libbox [PlatformInterface] (TUN
 * creation via Android's [VpnService.Builder], socket protection, interface
 * monitoring) and [CommandServerHandler] (lifecycle), and runs the core via the
 * v1.13.x [CommandServer] API.
 *
 * Built against sing-box v1.13.13's libbox. Adapted from the patterns in
 * SagerNet/sing-box-for-android (GPL-3.0).
 */
class NovaVpnService : VpnService(), PlatformInterface, CommandServerHandler {

    companion object {
        const val EXTRA_CONFIG = "config"
        const val ACTION_STOP = "online.novaproxy.nova_client.STOP"

        @Volatile
        private var libboxSetup = false
    }

    private val connectivity by lazy {
        getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    }

    private var commandServer: CommandServer? = null
    private var pfd: ParcelFileDescriptor? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null

    @Volatile
    private var running = false

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopBox(startId)
            return START_NOT_STICKY
        }
        val config = intent?.getStringExtra(EXTRA_CONFIG)
        if (config.isNullOrEmpty()) {
            stopSelf()
            return START_NOT_STICKY
        }
        if (running) return START_NOT_STICKY
        running = true
        NovaProxyBridge.emitState("connecting")
        Thread { startBox(config) }.start()
        return START_NOT_STICKY
    }

    private fun startBox(config: String) {
        try {
            if (!libboxSetup) {
                val working = File(filesDir, "working").apply { mkdirs() }
                Libbox.setup(
                    SetupOptions().apply {
                        setBasePath(filesDir.absolutePath)
                        setWorkingPath(working.absolutePath)
                        setTempPath(cacheDir.absolutePath)
                        setCommandServerListenPort(0)
                    },
                )
                libboxSetup = true
            }
            val server = CommandServer(this, this)
            server.start()
            commandServer = server
            server.startOrReloadService(config, OverrideOptions())
            NovaProxyBridge.emitState("connected")
        } catch (e: Exception) {
            running = false
            NovaProxyBridge.emitError(e.message)
            cleanup()
            stopSelf()
        }
    }

    private fun stopBox(stopStartId: Int = -1) {
        if (!running && commandServer == null) {
            stopSelfSafely(stopStartId)
            return
        }
        running = false
        NovaProxyBridge.emitState("disconnecting")
        Thread {
            cleanup()
            NovaProxyBridge.emitState("disconnected")
            stopSelfSafely(stopStartId)
        }.start()
    }

    /// Stop this service instance without killing a restart that raced in behind
    /// us. A "switch server" is stop-then-start; the stop runs cleanup on a
    /// background thread and, when it finished, an unconditional stopSelf() would
    /// tear down the *new* tunnel the restart had already established (onDestroy
    /// closes the fresh command server). stopSelf(startId) only stops if no newer
    /// start command has arrived, so the restart survives.
    private fun stopSelfSafely(stopStartId: Int) {
        if (stopStartId >= 0) stopSelf(stopStartId) else stopSelf()
    }

    private fun cleanup() {
        runCatching { commandServer?.closeService() }
        runCatching { commandServer?.close() }
        commandServer = null
        runCatching { pfd?.close() }
        pfd = null
    }

    override fun onDestroy() {
        cleanup()
        super.onDestroy()
    }

    override fun onRevoke() {
        stopBox()
        super.onRevoke()
    }

    // ---- CommandServerHandler ----

    override fun serviceStop() {
        stopBox()
    }

    override fun serviceReload() {
        // Single-profile client: nothing to reload.
    }

    override fun getSystemProxyStatus(): SystemProxyStatus =
        SystemProxyStatus().apply {
            setAvailable(false)
            setEnabled(false)
        }

    override fun setSystemProxyEnabled(isEnabled: Boolean) {
        // System HTTP proxy not exposed yet.
    }

    override fun writeDebugMessage(message: String?) {
        // No-op; box logs go to logcat via the core.
    }

    // ---- PlatformInterface ----

    override fun localDNSTransport(): LocalDNSTransport? = null

    override fun usePlatformAutoDetectInterfaceControl(): Boolean = true

    override fun autoDetectInterfaceControl(fd: Int) {
        protect(fd)
    }

    override fun openTun(options: TunOptions): Int {
        if (prepare(this) != null) error("android: missing vpn permission")

        val builder = Builder()
            .setSession("Nova Client")
            .setMtu(options.getMTU())

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            builder.setMetered(false)
        }

        val inet4 = options.getInet4Address()
        while (inet4.hasNext()) {
            val a = inet4.next()
            builder.addAddress(a.address(), a.prefix())
        }
        val inet6 = options.getInet6Address()
        var hasV6 = false
        while (inet6.hasNext()) {
            val a = inet6.next()
            builder.addAddress(a.address(), a.prefix())
            hasV6 = true
        }

        if (options.getAutoRoute()) {
            // Route everything into the TUN; sing-box hijacks DNS via sniff, so a
            // placeholder resolver address is sufficient here.
            builder.addDnsServer("1.1.1.1")
            builder.addRoute("0.0.0.0", 0)
            if (hasV6) builder.addRoute("::", 0)

            val include = options.getIncludePackage()
            while (include.hasNext()) {
                runCatching { builder.addAllowedApplication(include.next()) }
            }
            val exclude = options.getExcludePackage()
            while (exclude.hasNext()) {
                runCatching { builder.addDisallowedApplication(exclude.next()) }
            }
        }

        val descriptor = builder.establish() ?: error("android: VPN establish failed")
        pfd = descriptor
        return descriptor.fd
    }

    override fun useProcFS(): Boolean = Build.VERSION.SDK_INT < Build.VERSION_CODES.Q

    override fun findConnectionOwner(
        ipProtocol: Int,
        sourceAddress: String,
        sourcePort: Int,
        destinationAddress: String,
        destinationPort: Int,
    ): ConnectionOwner {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) error("unsupported")
        val uid = connectivity.getConnectionOwnerUid(
            ipProtocol,
            InetSocketAddress(sourceAddress, sourcePort),
            InetSocketAddress(destinationAddress, destinationPort),
        )
        return ConnectionOwner().apply { setUserId(uid) }
    }

    override fun startDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) = report(listener, network)
            override fun onCapabilitiesChanged(
                network: Network,
                caps: NetworkCapabilities,
            ) = report(listener, network)

            override fun onLost(network: Network) {
                runCatching { listener.updateDefaultInterface("", -1, false, false) }
            }
        }
        networkCallback = callback
        runCatching { connectivity.registerDefaultNetworkCallback(callback) }
    }

    private fun report(listener: InterfaceUpdateListener, network: Network) {
        runCatching {
            val name = connectivity.getLinkProperties(network)?.interfaceName ?: return
            val index = JavaNetworkInterface.getByName(name)?.index ?: -1
            listener.updateDefaultInterface(name, index, false, false)
        }
    }

    override fun closeDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        val callback = networkCallback ?: return
        runCatching { connectivity.unregisterNetworkCallback(callback) }
        networkCallback = null
    }

    override fun getInterfaces(): NetworkInterfaceIterator {
        val interfaces = mutableListOf<LibboxNetworkInterface>()
        runCatching {
            for (ni in JavaNetworkInterface.getNetworkInterfaces()) {
                val boxIf = LibboxNetworkInterface()
                boxIf.setName(ni.name)
                boxIf.setIndex(ni.index)
                runCatching { boxIf.setMTU(ni.mtu) }
                val addrs = mutableListOf<String>()
                for (ia in ni.interfaceAddresses) {
                    // Strip any IPv6 zone id ("fe80::1%wlan0"): sing-box 1.13 feeds
                    // these straight into netip.ParsePrefix, which rejects a zone
                    // in a prefix and PANICS (SIGABRT), crashing the whole app on
                    // connect. Every device has zoned link-local addresses, so
                    // dropping the "%zone" suffix here is required, not cosmetic.
                    val host = (ia.address.hostAddress ?: continue).substringBefore('%')
                    addrs.add("$host/${ia.networkPrefixLength}")
                }
                boxIf.setAddresses(StringArray(addrs.iterator()))
                var flags = 0
                if (ni.isUp) flags = flags or OsConstants.IFF_UP or OsConstants.IFF_RUNNING
                if (ni.isLoopback) flags = flags or OsConstants.IFF_LOOPBACK
                if (ni.isPointToPoint) flags = flags or OsConstants.IFF_POINTOPOINT
                if (ni.supportsMulticast()) flags = flags or OsConstants.IFF_MULTICAST
                boxIf.setFlags(flags)
                interfaces.add(boxIf)
            }
        }
        return InterfaceArray(interfaces.iterator())
    }

    override fun underNetworkExtension(): Boolean = false

    override fun includeAllNetworks(): Boolean = false

    override fun readWIFIState(): WIFIState? = null

    override fun systemCertificates(): StringIterator =
        StringArray(emptyList<String>().iterator())

    override fun clearDNSCache() {}

    override fun sendNotification(notification: Notification) {}

    private class StringArray(private val iterator: Iterator<String>) : StringIterator {
        override fun len(): Int = 0
        override fun hasNext(): Boolean = iterator.hasNext()
        override fun next(): String = iterator.next()
    }

    private class InterfaceArray(
        private val iterator: Iterator<LibboxNetworkInterface>,
    ) : NetworkInterfaceIterator {
        override fun hasNext(): Boolean = iterator.hasNext()
        override fun next(): LibboxNetworkInterface = iterator.next()
    }
}
