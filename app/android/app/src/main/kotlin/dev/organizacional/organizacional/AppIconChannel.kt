package dev.organizacional.organizacional

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Canal `dev.organizacional/app_icon`: um `activity-alias` por tema, só um habilitado.
 * `current` devolve o tema do alias habilitado; `set(theme)` habilita o alvo primeiro
 * e depois desabilita os demais (nunca fica sem nenhum ícone de lançamento).
 */
class AppIconChannel(private val context: Context) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "dev.organizacional/app_icon"
        val THEME_IDS = listOf(
            "violeta", "safira", "musgo", "lunar", "indigo",
            "grafite", "coral", "cobalto", "cacto", "bronze",
        )

        fun aliasName(themeId: String): String =
            "dev.organizacional.organizacional.Icon" + themeId.replaceFirstChar { it.uppercaseChar() }

        fun register(messenger: BinaryMessenger, context: Context) {
            MethodChannel(messenger, CHANNEL).setMethodCallHandler(AppIconChannel(context))
        }
    }

    private val pm: PackageManager get() = context.packageManager

    private fun component(themeId: String) = ComponentName(context.packageName, aliasName(themeId))

    // Considera o estado efetivo: DEFAULT vale o `android:enabled` do manifesto (só violeta).
    private fun isEnabled(themeId: String): Boolean =
        when (pm.getComponentEnabledSetting(component(themeId))) {
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED -> true
            PackageManager.COMPONENT_ENABLED_STATE_DEFAULT -> themeId == "violeta"
            else -> false
        }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "current" -> result.success(THEME_IDS.firstOrNull { isEnabled(it) })
            "set" -> {
                val theme = call.argument<String>("theme")
                if (theme == null || theme !in THEME_IDS) {
                    result.error("invalid_theme", "Tema inválido: $theme", null)
                    return
                }
                try {
                    pm.setComponentEnabledSetting(
                        component(theme),
                        PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                        PackageManager.DONT_KILL_APP,
                    )
                    for (other in THEME_IDS) {
                        if (other == theme) continue
                        pm.setComponentEnabledSetting(
                            component(other),
                            PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                            PackageManager.DONT_KILL_APP,
                        )
                    }
                    result.success(null)
                } catch (e: Exception) {
                    result.error("set_failed", e.message, null)
                }
            }
            else -> result.notImplemented()
        }
    }
}
