package com.isg32.moose

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

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
    }
}
