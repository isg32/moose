package com.isg32.moose

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.isg32.moose.youtube.YouTubeChannel

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        // First, so a crash on the Android side is written down and shown
        // on the next launch.
        CrashFiles.installCrashHandler(this)
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        CrashFiles.register(this, flutterEngine.dartExecutor.binaryMessenger)
        // Song clips (C27, C28): NewPipe finds the stream (see youtube.dart).
        YouTubeChannel.register(flutterEngine.dartExecutor.binaryMessenger)
        // Over-the-air updates from GitHub Releases (lib/net/updater.dart).
        Updater.register(this, flutterEngine.dartExecutor.binaryMessenger)
        // "Hide in recent apps" (C36): FLAG_SECURE blanks Moose in the
        // app switcher and blocks screenshots of it.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "moose/window")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "secure" -> {
                        val on = call.arguments as? Boolean ?: true
                        runOnUiThread {
                            if (on) {
                                window.addFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE)
                            } else {
                                window.clearFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE)
                            }
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
