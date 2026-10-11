package dev.organizacional.organizacional.widgets

import android.content.Context
import android.content.SharedPreferences
import android.view.View
import android.widget.RemoteViews
import dev.organizacional.organizacional.R
import java.time.ZoneId

class ProvaWidgetProvider : BaseOrgWidget() {
    override val layoutId = R.layout.widget_prova
    override val clickUri = "organizacional://agenda"

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
        for (id in intArrayOf(R.id.exam_title, R.id.exam_when, R.id.exam_place, R.id.empty)) {
            views.setViewVisibility(id, View.GONE)
        }

        if (WidgetData.state(prefs) == WidgetData.STATE_SIGNED_OUT) {
            showEmpty(views, "Abra o app e entre")
            return
        }
        val exam = WidgetData.nextExam(WidgetData.parseEvents(prefs), nowMillis)
        if (exam == null) {
            showEmpty(views, "Sem provas à vista")
            return
        }
        views.setViewVisibility(R.id.exam_title, View.VISIBLE)
        views.setTextViewText(R.id.exam_title, exam.title)
        views.setTextColor(R.id.exam_title, theme.ink)

        views.setViewVisibility(R.id.exam_when, View.VISIBLE)
        views.setTextViewText(R.id.exam_when, WidgetData.examWhen(exam, nowMillis, zone))
        views.setTextColor(R.id.exam_when, theme.accentText)

        val place = exam.location
        if (place != null) {
            views.setViewVisibility(R.id.exam_place, View.VISIBLE)
            views.setTextViewText(R.id.exam_place, place)
            views.setTextColor(R.id.exam_place, theme.inkMuted)
        }
    }

    private fun showEmpty(views: RemoteViews, text: String) {
        views.setViewVisibility(R.id.empty, View.VISIBLE)
        views.setTextViewText(R.id.empty, text)
    }
}
