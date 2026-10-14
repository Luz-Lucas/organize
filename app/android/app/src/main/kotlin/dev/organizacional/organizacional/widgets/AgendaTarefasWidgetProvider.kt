package dev.organizacional.organizacional.widgets

import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import dev.organizacional.organizacional.MainActivity
import dev.organizacional.organizacional.R
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import java.time.ZoneId

/**
 * 4x4 dividido ao meio (peso 1/1): "Eventos de hoje" em cima e "Tarefas" embaixo, cada metade
 * com até [MAX_ROWS] linhas conforme a altura do widget. Mesmos dados e regras de Hoje/Tarefas;
 * cada seção abre a sua tela (o clique da raiz, vindo de [BaseOrgWidget], cobre apenas as
 * margens e abre a agenda).
 */
class AgendaTarefasWidgetProvider : BaseOrgWidget() {
    override val layoutId = R.layout.widget_agenda_tarefas
    override val clickUri = URI_AGENDA

    private val evRows = intArrayOf(
        R.id.ev_row1, R.id.ev_row2, R.id.ev_row3, R.id.ev_row4, R.id.ev_row5, R.id.ev_row6,
    )
    private val evTimes = intArrayOf(
        R.id.ev_row1_time, R.id.ev_row2_time, R.id.ev_row3_time,
        R.id.ev_row4_time, R.id.ev_row5_time, R.id.ev_row6_time,
    )
    private val evTitles = intArrayOf(
        R.id.ev_row1_title, R.id.ev_row2_title, R.id.ev_row3_title,
        R.id.ev_row4_title, R.id.ev_row5_title, R.id.ev_row6_title,
    )
    private val tkRows = intArrayOf(
        R.id.tk_row1, R.id.tk_row2, R.id.tk_row3, R.id.tk_row4, R.id.tk_row5, R.id.tk_row6,
    )
    private val tkTimes = intArrayOf(
        R.id.tk_row1_time, R.id.tk_row2_time, R.id.tk_row3_time,
        R.id.tk_row4_time, R.id.tk_row5_time, R.id.tk_row6_time,
    )
    private val tkTitles = intArrayOf(
        R.id.tk_row1_title, R.id.tk_row2_title, R.id.tk_row3_title,
        R.id.tk_row4_title, R.id.tk_row5_title, R.id.tk_row6_title,
    )

    override fun render(
        context: Context,
        views: RemoteViews,
        prefs: SharedPreferences,
        theme: WidgetTheme,
        nowMillis: Long,
        heightDp: Int,
    ) {
        val zone = ZoneId.systemDefault()

        // Duas áreas clicáveis, distinguidas pela URI de cada PendingIntent.
        views.setOnClickPendingIntent(R.id.section_events, launch(context, URI_AGENDA))
        views.setOnClickPendingIntent(R.id.section_tasks, launch(context, URI_TAREFAS))

        // Título de cada seção: ícone pequeno + texto na cor de destaque do tema.
        views.setTextColor(R.id.ev_title, theme.accentText)
        views.setTextColor(R.id.tk_title, theme.accentText)
        views.setInt(R.id.ev_icon, "setColorFilter", theme.accentText)
        views.setInt(R.id.tk_icon, "setColorFilter", theme.accentText)
        views.setInt(R.id.divider, "setBackgroundColor", theme.line)
        for (r in evRows + tkRows) views.setViewVisibility(r, View.GONE)
        for (id in intArrayOf(R.id.ev_more, R.id.ev_empty, R.id.tk_more, R.id.tk_empty)) {
            views.setViewVisibility(id, View.GONE)
        }

        if (WidgetData.state(prefs) == WidgetData.STATE_SIGNED_OUT) {
            setTasksSectionVisible(views, false)
            showEmpty(views, R.id.ev_empty, theme, "Abra o app e entre")
            return
        }
        setTasksSectionVisible(views, true)

        val events = WidgetData.eventsToday(WidgetData.parseEvents(prefs), nowMillis, zone)
        val tasks = WidgetData.parseTasks(prefs)
        // As duas metades têm a mesma altura, então a mesma quantidade de linhas.
        val cap = WidgetData.sectionRows(heightDp, MAX_ROWS)

        // Eventos de hoje
        if (events.isEmpty()) {
            showEmpty(views, R.id.ev_empty, theme, "Nada na agenda hoje")
        } else {
            val shown = events.take(cap)
            shown.forEachIndexed { i, e ->
                views.setViewVisibility(evRows[i], View.VISIBLE)
                views.setTextViewText(evTimes[i], WidgetData.eventTimeCompact(e, nowMillis, zone))
                views.setTextColor(evTimes[i], WidgetData.eventTimeColor(e, nowMillis, theme))
                views.setTextViewText(evTitles[i], taggedTitle(e))
                views.setTextColor(evTitles[i], WidgetData.eventTitleColor(e, nowMillis, theme))
            }
            showMore(views, R.id.ev_more, theme, events.size - shown.size)
        }

        // Tarefas
        if (tasks.isEmpty()) {
            showEmpty(views, R.id.tk_empty, theme, "Nenhuma tarefa")
        } else {
            val shown = tasks.take(cap)
            shown.forEachIndexed { i, t ->
                val due = t.due
                views.setViewVisibility(tkRows[i], View.VISIBLE)
                // Sem prazo: "—" mantém a coluna e os títulos continuam alinhados.
                views.setTextViewText(tkTimes[i], if (due == null) "—" else WidgetData.dayLabel(due, nowMillis, zone))
                views.setTextColor(
                    tkTimes[i],
                    if (due == null) theme.inkMuted else WidgetData.taskDueColor(due, nowMillis, zone, theme),
                )
                views.setTextViewText(tkTitles[i], t.title)
                views.setTextColor(tkTitles[i], WidgetData.taskTitleColor(t, theme))
            }
            showMore(views, R.id.tk_more, theme, tasks.size - shown.size)
        }
    }

    private fun launch(context: Context, uri: String) =
        HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse(uri))

    private fun setTasksSectionVisible(views: RemoteViews, visible: Boolean) {
        val v = if (visible) View.VISIBLE else View.GONE
        views.setViewVisibility(R.id.divider, v)
        views.setViewVisibility(R.id.section_tasks, v)
    }

    private fun showEmpty(views: RemoteViews, id: Int, theme: WidgetTheme, text: String) {
        views.setViewVisibility(id, View.VISIBLE)
        views.setTextViewText(id, text)
        views.setTextColor(id, theme.inkMuted)
    }

    private fun showMore(views: RemoteViews, id: Int, theme: WidgetTheme, extra: Int) {
        if (extra <= 0) return
        views.setViewVisibility(id, View.VISIBLE)
        views.setTextViewText(id, WidgetData.moreLabel(extra))
        views.setTextColor(id, theme.inkMuted)
    }

    private companion object {
        const val URI_AGENDA = "organizacional://agenda"
        const val URI_TAREFAS = "organizacional://tarefas"
        const val MAX_ROWS = 6
    }
}
