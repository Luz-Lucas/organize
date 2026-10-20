package dev.organizacional.organizacional.widgets

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import dev.organizacional.organizacional.MainActivity
import dev.organizacional.organizacional.R
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin

/**
 * 4x4: itens pendentes da primeira lista de compras, agrupados por seção, até [WidgetViewIds.shRow] linhas
 * conforme a altura. Tocar num item o remove do `w_shop` local na hora (redesenha) e manda a gravação
 * (`checked = true`) para o segundo plano do home_widget; se falhar, a próxima sincronização o traz de volta.
 * Tocar no título (ou nas margens) abre Compras.
 */
class MercadoWidgetProvider : BaseOrgWidget() {
    override val layoutId = R.layout.widget_mercado
    override val clickUri = URI_COMPRAS

    override fun render(
        context: Context,
        views: RemoteViews,
        prefs: SharedPreferences,
        theme: WidgetTheme,
        nowMillis: Long,
        heightDp: Int,
    ) {
        val ids = WidgetViewIds
        val compras = HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse(URI_COMPRAS))
        views.setOnClickPendingIntent(R.id.sh_header, compras)
        views.setTextColor(R.id.sh_title, theme.accentText)
        for (r in ids.shRow) views.setViewVisibility(r, View.GONE)
        views.setViewVisibility(R.id.sh_empty, View.GONE)
        views.setViewVisibility(R.id.sh_more, View.GONE)

        if (WidgetData.state(prefs) == WidgetData.STATE_SIGNED_OUT) {
            views.setTextViewText(R.id.sh_title, "Mercado")
            showText(views, R.id.sh_empty, theme, "Abra o app e entre")
            return
        }

        val shop = ShopData.parse(prefs.getString(ShopData.KEY_SHOP, null))
        views.setTextViewText(R.id.sh_title, ShopData.title(shop))
        if (ShopData.count(shop) == 0) {
            // Inclui quem nunca abriu Compras (sem lista): vazio, sem erro.
            showText(views, R.id.sh_empty, theme, "Lista vazia")
            return
        }

        val layout = ShopData.lines(shop, minOf(ShopData.maxLines(heightDp), ids.shRow.size))
        layout.lines.forEachIndexed { i, line ->
            views.setViewVisibility(ids.shRow[i], View.VISIBLE)
            when (line) {
                is ShopLine.Header -> {
                    views.setTextViewText(ids.shName[i], line.label.uppercase())
                    views.setTextViewTextSize(ids.shName[i], android.util.TypedValue.COMPLEX_UNIT_SP, 10f)
                    views.setTextColor(ids.shName[i], theme.accentText)
                    views.setViewVisibility(ids.shQty[i], View.GONE)
                    // Sem toque próprio: cai no clique da raiz (abre Compras).
                    views.setOnClickPendingIntent(ids.shRow[i], compras)
                }
                is ShopLine.Item -> {
                    views.setTextViewText(ids.shName[i], "○  ${line.name}")
                    views.setTextViewTextSize(ids.shName[i], android.util.TypedValue.COMPLEX_UNIT_SP, 13f)
                    views.setTextColor(ids.shName[i], theme.ink)
                    if (line.quantity.isBlank()) {
                        views.setViewVisibility(ids.shQty[i], View.GONE)
                    } else {
                        views.setViewVisibility(ids.shQty[i], View.VISIBLE)
                        views.setTextViewText(ids.shQty[i], line.quantity)
                        views.setTextColor(ids.shQty[i], theme.inkMuted)
                    }
                    views.setOnClickPendingIntent(ids.shRow[i], checkIntent(context, line.id))
                }
            }
        }
        if (layout.hidden > 0) {
            showText(views, R.id.sh_more, theme, WidgetData.moreLabel(layout.hidden))
            views.setOnClickPendingIntent(R.id.sh_more, compras)
        }
    }

    // ---- Toque num item ------------------------------------------------------

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_CHECK) {
            super.onReceive(context, intent)
            return
        }
        val itemId = ShopData.itemIdFromUri(intent.dataString) ?: return
        val prefs = HomeWidgetPlugin.getData(context)
        // 1) Some na hora: tira o item do w_shop local e redesenha.
        val updated = ShopData.removeItem(prefs.getString(ShopData.KEY_SHOP, null), itemId)
        if (updated != null) {
            prefs.edit().putString(ShopData.KEY_SHOP, updated).apply()
            val mgr = AppWidgetManager.getInstance(context)
            for (id in mgr.getAppWidgetIds(ComponentName(context, MercadoWidgetProvider::class.java))) {
                draw(context, mgr, id, prefs)
            }
        }
        // 2) Grava no Supabase em segundo plano (callback Dart widgetInteractivityCallback). Sem sessão ou
        //    sem rede o item volta na próxima sincronização; nada trava.
        try {
            HomeWidgetBackgroundIntent.getBroadcast(context, Uri.parse(ShopData.checkUri(itemId))).send()
        } catch (_: PendingIntent.CanceledException) {
        }
    }

    /** Um PendingIntent por item: a URI (com o id) os distingue. */
    private fun checkIntent(context: Context, itemId: String): PendingIntent {
        val intent = Intent(context, MercadoWidgetProvider::class.java)
            .setAction(ACTION_CHECK)
            .setData(Uri.parse(ShopData.checkUri(itemId)))
        return PendingIntent.getBroadcast(
            context, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun showText(views: RemoteViews, id: Int, theme: WidgetTheme, text: String) {
        views.setViewVisibility(id, View.VISIBLE)
        views.setTextViewText(id, text)
        views.setTextColor(id, theme.inkMuted)
    }

    companion object {
        const val URI_COMPRAS = "organizacional://compras"
        const val ACTION_CHECK = "dev.organizacional.organizacional.widgets.MERCADO_CHECK"
    }
}
