package com.example.scan_erp

import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PersistableBundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity(), EventChannel.StreamHandler {
    private val clipboardChannel = "scan_erp/clipboard_stream"
    private val scannerChannel = "scan_erp/media_scanner" 

    private var clipboardManager: ClipboardManager? = null
    private var events: EventChannel.EventSink? = null

    private val clipboardListener = ClipboardManager.OnPrimaryClipChangedListener {
        val manager = clipboardManager ?: return@OnPrimaryClipChangedListener
        val item = manager.primaryClip?.getItemAt(0) ?: return@OnPrimaryClipChangedListener
        val text = item.coerceToText(this).toString().trim()

        if (text.isEmpty()) return@OnPrimaryClipChangedListener

        events?.success(text)
        clearClipboardSilently(manager)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, clipboardChannel)
            .setStreamHandler(this)

            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, scannerChannel).setMethodCallHandler { call, result ->
            if (call.method == "scanFile") {
                val path = call.argument<String>("path")
                if (path != null) {
                    scanFile(path)
                    result.success(null)
                } else {
                    result.error("INVALID_PATH", "Path is null", null)
                }
            } else {
                result.notImplemented()
            }
        }
    }
    private fun scanFile(path: String) {
        try {
            val file = File(path)
            val uri = Uri.fromFile(file)
            val intent = Intent(Intent.ACTION_MEDIA_SCANNER_SCAN_FILE, uri)
            sendBroadcast(intent)
        } catch (e: Exception) {
        }
    }

    override fun onListen(arguments: Any?, eventSink: EventChannel.EventSink?) {
        events = eventSink
        clipboardManager = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        clipboardManager?.addPrimaryClipChangedListener(clipboardListener)
    }

    override fun onCancel(arguments: Any?) {
        clipboardManager?.removePrimaryClipChangedListener(clipboardListener)
        clipboardManager = null
        events = null
    }

    private fun clearClipboardSilently(manager: ClipboardManager) {
        val clip = ClipData.newPlainText("", "")

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            clip.description.extras = PersistableBundle().apply {
                putBoolean(ClipDescription.EXTRA_IS_SENSITIVE, true)
            }
        }

        manager.setPrimaryClip(clip)
    }
}
