package dev.organizacional.organizacional

import com.google_mlkit_digital_ink_recognition.DigitalInkRecognizer
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Reconhecimento de escrita (ML Kit) no app de release.
 *
 * O registro automático do plugin engole exceções: se o ML Kit falha ao iniciar,
 * o canal fica sem tratador e o Dart só vê MissingPluginException. Aqui o tratador
 * do plugin é ligado de novo no canal dele. Se funcionar, conserta o registro; se
 * falhar, guarda o motivo, que o Dart lê em `dev.organizacional/ink`
 * (`registrationError`) para mostrar na tela.
 */
object InkChannel {
    private const val PLUGIN_CHANNEL = "google_mlkit_digital_ink_recognizer"
    private const val CHANNEL = "dev.organizacional/ink"

    @Volatile
    private var registrationError: String? = null

    fun attach(messenger: BinaryMessenger) {
        registrationError = try {
            MethodChannel(messenger, PLUGIN_CHANNEL).setMethodCallHandler(DigitalInkRecognizer())
            null
        } catch (t: Throwable) {
            describe(t)
        }
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "registrationError" -> result.success(registrationError)
                else -> result.notImplemented()
            }
        }
    }

    private fun describe(t: Throwable): String {
        val parts = mutableListOf<String>()
        var cur: Throwable? = t
        while (cur != null && parts.size < 3) {
            parts += "${cur.javaClass.simpleName}: ${cur.message ?: ""}".trim()
            cur = cur.cause
        }
        return parts.joinToString(" ← ")
    }
}
