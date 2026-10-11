package dev.organizacional.organizacional.widgets

import android.content.Context
import android.content.SharedPreferences
import android.view.View
import android.widget.RemoteViews
import dev.organizacional.organizacional.R
import java.time.ZoneId

class TarefasWidgetProvider : BaseOrgWidget() {
    override val layoutId = R.layout.widget_tarefas
    override val clickUri = "organizacional://tarefas"

    private val rows = intArrayOf(R.id.row1, R.id.row2, R.id.row3, R.id.row4, R.id.row5, R.id.row6)
    private val times = intArrayOf(R.id.row1_time, R.id.row2_time, R.id.row3_time, R.id.row4_time, R.id.row5_time, R.id.row6_time)
    private val titles = intArrayOf(R.id.row1_title, R.id.row2_title, R.id.row3_title, R.id.row4_title, R.id.row5_title, R.id.row6_title)

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
        val tasks = WidgetData.parseTasks(prefs)
        if (tasks.isEmpty()) {
            showEmpty(views, "Nenhuma tarefa")
            return
        }
        val cap = WidgetData.rowsFor(heightDp, rows.size)
        val shown = tasks.take(cap)
        shown.forEachIndexed { i, t ->
            val due = t.due
            views.setViewVisibility(rows[i], View.VISIBLE)
            views.setTextViewText(times[i], if (due == null) "" else WidgetData.dayLabel(due, nowMillis, zone))
            if (due != null) views.setTextColor(times[i], WidgetData.taskDueColor(due, nowMillis, zone, theme))
            views.setViewVisibility(times[i], if (due == null) View.GONE else View.VISIBLE)
            views.setTextViewText(titles[i], t.title)
            views.setTextColor(titles[i], WidgetData.taskTitleColor(t, theme))
        }
        val extra = tasks.size - shown.size
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
