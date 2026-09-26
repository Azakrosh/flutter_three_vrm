package dev.flutter_three_vrm

import android.annotation.SuppressLint
import android.annotation.TargetApi
import android.content.Context
import android.os.Build
import android.os.PowerManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel

/** Provides Android thermal status to the package's Dart diagnostics layer. */
class FlutterThreeVrmPlugin : FlutterPlugin, EventChannel.StreamHandler {
    private lateinit var channel: EventChannel
    private lateinit var applicationContext: Context
    private var eventSink: EventChannel.EventSink? = null
    private var thermalMonitor: Api29ThermalMonitor? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
        channel = EventChannel(binding.binaryMessenger, THERMAL_CHANNEL)
        channel.setStreamHandler(this)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        stopMonitoring()
        eventSink = events
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            events.success(null)
            return
        }
        startMonitoring(events)
    }

    override fun onCancel(arguments: Any?) {
        stopMonitoring()
    }

    @SuppressLint("NewApi")
    private fun startMonitoring(events: EventChannel.EventSink) {
        val monitor = Api29ThermalMonitor(applicationContext) { status ->
            eventSink?.success(status)
        }
        thermalMonitor = monitor
        monitor.start(events)
    }

    private fun stopMonitoring() {
        thermalMonitor?.stop()
        thermalMonitor = null
        eventSink = null
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        stopMonitoring()
        channel.setStreamHandler(null)
    }

    private companion object {
        const val THERMAL_CHANNEL = "dev.flutter_three_vrm/thermal_status"
    }

    @TargetApi(Build.VERSION_CODES.Q)
    private class Api29ThermalMonitor(
        context: Context,
        onStatus: (Int) -> Unit,
    ) {
        private val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        private val listener = PowerManager.OnThermalStatusChangedListener(onStatus)

        fun start(events: EventChannel.EventSink) {
            powerManager.addThermalStatusListener(listener)
            events.success(powerManager.currentThermalStatus)
        }

        fun stop() {
            powerManager.removeThermalStatusListener(listener)
        }
    }
}
