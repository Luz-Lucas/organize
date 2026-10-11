package dev.organizacional.organizacional.widgets

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import dev.organizacional.organizacional.MainActivity
import dev.organizacional.organizacional.R
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/** Base dos três widgets: desenha por id (com a altura de cada um) e trata clique/redimensionamento. */
abstract class BaseOrgWidget : HomeWidgetProvider() {
    protected abstract val layoutId: Int
    protected abstract val clickUri: String

    protected abstract fun render(
        context: Context,
        views: RemoteViews,
        prefs: SharedPreferences,
        theme: WidgetTheme,
        nowMillis: Long,
        heightDp: Int,
    )

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (id in appWidgetIds) draw(context, appWidgetManager, id, widgetData)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        val prefs = es.antonborri.home_widget.HomeWidgetPlugin.getData(context)
        draw(context, appWidgetManager, appWidgetId, prefs)
    }

    private fun draw(context: Context, mgr: AppWidgetManager, id: Int, prefs: SharedPreferences) {
        val views = RemoteViews(context.packageName, layoutId)
        val theme = WidgetData.parseTheme(prefs)
        val heightDp = mgr.getAppWidgetOptions(id).getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0)
        val now = System.currentTimeMillis()

        views.setInt(R.id.bg, "setColorFilter", theme.surface)
        views.setOnClickPendingIntent(
            R.id.root,
            HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse(clickUri)),
        )
        render(context, views, prefs, theme, now, heightDp)

        val state = WidgetData.state(prefs)
        val stale = state == WidgetData.STATE_ERROR &&
            WidgetData.isStale(WidgetData.generatedAt(prefs), now)
        views.setViewVisibility(R.id.stale, if (stale) View.VISIBLE else View.GONE)
        views.setTextColor(R.id.stale, theme.inkMuted)
        mgr.updateAppWidget(id, views)
    }
}
