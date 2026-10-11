package dev.organizacional.organizacional.widgets

import android.content.Context
import android.content.SharedPreferences
import android.view.View
import android.widget.RemoteViews
import dev.organizacional.organizacional.R
import java.time.ZoneId

class HojeWidgetProvider : BaseOrgWidget() {
    override val layoutId = R.layout.widget_hoje
    override val clickUri = "organizacional://agenda"

    private val rows = intArrayOf(R.id.row1, R.id.row2, R.id.row3, R.id.row4, R.id.row5)
    private val times = intArrayOf(R.id.row1_time, R.id.row2_time, R.id.row3_time, R.id.row4_time, R.id.row5_time)
    private val titles = intArrayOf(R.id.row1_title, R.id.row2_title, R.id.row3_title, R.id.row4_title, R.id.row5_title)

    override fun render(
        context: Context,
        views: RemoteViews,
        prefs: SharedPreferences,
        theme: WidgetTheme,
        nowMillis: Long,
        heightDp: Int,
    ) {
        val zone = ZoneId.systemDefault()
        views.setTextColor(R.id.header, theme.accentText)
        views.setTextColor(R.id.empty, theme.inkMuted)
        for (r in rows) views.setViewVisibility(r, View.GONE)
        views.setViewVisibility(R.id.more, View.GONE)
        views.setViewVisibility(R.id.empty, View.GONE)

        if (WidgetData.state(prefs) == WidgetData.STATE_SIGNED_OUT) {
            showEmpty(views, "Abra o app e entre")
            return
        }
        val today = WidgetData.eventsToday(WidgetData.parseEvents(prefs), nowMillis, zone)
        if (today.isEmpty()) {
            showEmpty(views, "Nada na agenda hoje")
            return
        }
        val cap = WidgetData.rowsFor(heightDp, rows.size)
        val shown = today.take(cap)
        shown.forEachIndexed { i, e ->
            val ongoing = !e.allDay && e.start <= nowMillis && nowMillis < e.end
            val finished = !e.allDay && e.end <= nowMillis
            val color = when {
                ongoing -> theme.accentText
                finished -> theme.inkMuted
                else -> theme.ink
            }
            views.setViewVisibility(rows[i], View.VISIBLE)
            views.setTextViewText(times[i], WidgetData.eventTimeLabel(e, nowMillis, zone))
            views.setTextColor(times[i], if (ongoing) theme.accentText else theme.inkMuted)
            views.setTextViewText(titles[i], e.title)
            views.setTextColor(titles[i], color)
        }
        val extra = today.size - shown.size
        if (extra > 0) {
            views.setViewVisibility(R.id.more, View.VISIBLE)
            views.setTextViewText(R.id.more, "+$extra")
            views.setTextColor(R.id.more, theme.inkMuted)
        }
    }

    private fun showEmpty(views: RemoteViews, text: String) {
        views.setViewVisibility(R.id.empty, View.VISIBLE)
        views.setTextViewText(R.id.empty, text)
    }
}
