package dev.organizacional.organizacional

import android.content.Intent
import android.os.Bundle
import android.view.MotionEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var share: ShareChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        AppIconChannel.register(flutterEngine.dartExecutor.binaryMessenger, applicationContext)
        share = ShareChannel(this).also { it.attach(flutterEngine.dartExecutor.binaryMessenger) }
        FilesChannel(this).attach(flutterEngine.dartExecutor.binaryMessenger)
        UpdateChannel(this).attach(flutterEngine.dartExecutor.binaryMessenger)
        InkChannel.attach(flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Só no primeiro lançamento: ao recriar a activity (rotação) o mesmo intent não vale de novo.
        // Reaberto pelo histórico de recentes, o Android reentrega o intent antigo: não é novo compartilhamento.
        if (savedInstanceState == null && !ShareGuard.launchedFromHistory(intent.flags)) {
            share?.handleIntent(intent, true)
        }
    }

    // Caneta (ou ponta-borracha): entrega cada amostra do input na hora, sem agrupar por vsync.
    override fun dispatchTouchEvent(ev: MotionEvent): Boolean {
        if (StylusInput.shouldRequestUnbuffered(ev.actionMasked, ev.getToolType(0))) {
            window.decorView.requestUnbufferedDispatch(ev)
        }
        return super.dispatchTouchEvent(ev)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (!ShareGuard.launchedFromHistory(intent.flags)) share?.handleIntent(intent, false)
    }
}
