package dev.organizacional.organizacional

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var share: ShareChannel? = null
    private var samsung: SamsungNotesChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        AppIconChannel.register(flutterEngine.dartExecutor.binaryMessenger, applicationContext)
        share = ShareChannel(this).also { it.attach(flutterEngine.dartExecutor.binaryMessenger) }
        samsung = SamsungNotesChannel(this).also { it.attach(flutterEngine.dartExecutor.binaryMessenger) }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Só no primeiro lançamento: ao recriar a activity (rotação) o mesmo intent não vale de novo.
        // Reaberto pelo histórico de recentes, o Android reentrega o intent antigo: não é novo compartilhamento.
        if (savedInstanceState == null && !ShareGuard.launchedFromHistory(intent.flags)) {
            share?.handleIntent(intent, true)
        }
    }

    @Deprecated("O seletor de pasta do Samsung Notes devolve o resultado por aqui.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (samsung?.onActivityResult(requestCode, resultCode, data) == true) return
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (!ShareGuard.launchedFromHistory(intent.flags)) share?.handleIntent(intent, false)
    }
}
