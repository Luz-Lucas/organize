package dev.organizacional.organizacional.widgets

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import dev.organizacional.organizacional.MainActivity
import dev.organizacional.organizacional.R
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

/**
 * 4x4: grade do mês em cima (hoje destacado, dia escolhido marcado, pontinho nos dias com eventos) e os
 * eventos do dia escolhido embaixo. Tocar num dia ou nas setas muda o estado e redesenha **sem abrir o
 * app** (broadcast para este mesmo receiver); tocar num evento ou no cabeçalho da lista abre a Agenda.
 * O mês exibido e o dia escolhido ficam por `appWidgetId` e voltam para hoje quando o dia vira.
 */
class CalendarioWidgetProvider : BaseOrgWidget() {
    override val layoutId = R.layout.widget_calendario
    override val clickUri = URI_AGENDA

    override fun render(
        context: Context,
        views: RemoteViews,
        prefs: SharedPreferences,
        theme: WidgetTheme,
        nowMillis: Long,
        heightDp: Int,
    ) {
        val zone = ZoneId.systemDefault()
        val id = drawingId
        val agenda = HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse(URI_AGENDA))
        val ids = WidgetViewIds

        for (r in ids.calEvRow) views.setViewVisibility(r, View.GONE)
        views.setViewVisibility(R.id.cal_more, View.GONE)
        views.setViewVisibility(R.id.cal_empty, View.GONE)
        views.setTextColor(R.id.cal_day_title, theme.accentText)

        if (WidgetData.state(prefs) == WidgetData.STATE_SIGNED_OUT) {
            views.setViewVisibility(R.id.cal_grid, View.GONE)
            views.setTextViewText(R.id.cal_day_title, "")
            showText(views, R.id.cal_empty, theme, "Abra o app e entre")
            return
        }
        views.setViewVisibility(R.id.cal_grid, View.VISIBLE)

        val today = Instant.ofEpochMilli(nowMillis).atZone(zone).toLocalDate()
        val range = CalendarData.parseRange(prefs.getString(CalendarData.KEY_RANGE, null))
        val events = WidgetData.parseEventsJson(prefs.getString(CalendarData.KEY_EVENTS, null))
        val state = loadState(context, id, today)

        // Cabeçalho do mês e setas (esmaecidas no limite da janela de dados).
        views.setTextViewText(R.id.cal_month, CalendarData.monthTitle(state.month))
        views.setTextColor(R.id.cal_month, theme.ink)
        val canPrev = CalendarData.shift(state, -1, range, today, zone) != state
        val canNext = CalendarData.shift(state, +1, range, today, zone) != state
        views.setTextColor(R.id.cal_prev, if (canPrev) theme.accentText else dim(theme.inkMuted))
        views.setTextColor(R.id.cal_next, if (canNext) theme.accentText else dim(theme.inkMuted))
        views.setOnClickPendingIntent(R.id.cal_prev, action(context, id, ACTION_PREV, null))
        views.setOnClickPendingIntent(R.id.cal_next, action(context, id, ACTION_NEXT, null))
        for (w in ids.calWeekday) views.setTextColor(w, theme.inkMuted)

        // Grade 6x7.
        val cells = CalendarData.cells(state.month, state.selected, today, events, theme.accentText, zone)
        cells.forEachIndexed { i, c ->
            views.setTextViewText(ids.calNum[i], c.date.dayOfMonth.toString())
            val numColor = when {
                c.isSelected -> theme.onAccent
                c.isToday -> theme.accentText
                c.inMonth -> theme.ink
                else -> dim(theme.inkMuted)
            }
            views.setTextColor(ids.calNum[i], numColor)
            val circle = when {
                c.isSelected -> theme.accentDeep
                c.isToday -> theme.accentSoft
                else -> null
            }
            views.setViewVisibility(ids.calBg[i], if (circle == null) View.INVISIBLE else View.VISIBLE)
            if (circle != null) views.setInt(ids.calBg[i], "setColorFilter", circle)
            val dot = c.dotColor
            views.setViewVisibility(ids.calDot[i], if (dot == null) View.INVISIBLE else View.VISIBLE)
            if (dot != null) views.setTextColor(ids.calDot[i], if (c.inMonth) dot else dim(dot))
            views.setOnClickPendingIntent(ids.calCell[i], action(context, id, ACTION_PICK, c.date))
        }

        // Lista do dia escolhido.
        val selected = state.selected
        val isToday = selected == today
        views.setTextViewText(
            R.id.cal_day_title,
            if (isToday) "${CalendarData.dayTitle(selected)} · hoje" else CalendarData.dayTitle(selected),
        )
        views.setOnClickPendingIntent(R.id.cal_list_header, agenda)
        val dayEvents = CalendarData.eventsOnDate(events, selected, zone)
        if (dayEvents.isEmpty()) {
            showText(views, R.id.cal_empty, theme, "Dia livre")
            return
        }
        // Referência dentro do dia escolhido para os rótulos de horário ("→ 02:00", "22:00 →").
        val ref = selected.atTime(12, 0).atZone(zone).toInstant().toEpochMilli()
        val cap = CalendarData.eventRows(heightDp)
        val shown = dayEvents.take(cap)
        shown.forEachIndexed { i, e ->
            views.setViewVisibility(ids.calEvRow[i], View.VISIBLE)
            views.setTextViewText(ids.calEvTime[i], WidgetData.eventTimeCompact(e, ref, zone))
            views.setTextViewText(ids.calEvTitle[i], taggedTitle(e))
            // Em andamento / já terminado só faz sentido no dia de hoje.
            views.setTextColor(
                ids.calEvTime[i],
                if (isToday) WidgetData.eventTimeColor(e, nowMillis, theme) else theme.inkMuted,
            )
            views.setTextColor(
                ids.calEvTitle[i],
                if (isToday) WidgetData.eventTitleColor(e, nowMillis, theme) else theme.ink,
            )
            views.setOnClickPendingIntent(ids.calEvRow[i], agenda)
        }
        val extra = dayEvents.size - shown.size
        if (extra > 0) {
            showText(views, R.id.cal_more, theme, WidgetData.moreLabel(extra))
            views.setOnClickPendingIntent(R.id.cal_more, agenda)
        }
    }

    // ---- Toques na grade (sem abrir o app) -----------------------------------

    override fun onReceive(context: Context, intent: Intent) {
        val act = intent.action
        if (act != ACTION_PREV && act != ACTION_NEXT && act != ACTION_PICK) {
            super.onReceive(context, intent)
            return
        }
        val id = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
        if (id == AppWidgetManager.INVALID_APPWIDGET_ID) return
        val zone = ZoneId.systemDefault()
        val today = LocalDate.now(zone)
        val prefs = HomeWidgetPlugin.getData(context)
        val range = CalendarData.parseRange(prefs.getString(CalendarData.KEY_RANGE, null))
        // Se o dia virou desde o último desenho, resolve() já volta para hoje antes de aplicar o toque.
        val state = loadState(context, id, today)
        val next = when (act) {
            ACTION_PREV -> CalendarData.shift(state, -1, range, today, zone)
            ACTION_NEXT -> CalendarData.shift(state, +1, range, today, zone)
            else -> {
                val date = try {
                    LocalDate.parse(intent.getStringExtra(EXTRA_DATE))
                } catch (_: Exception) {
                    return
                }
                CalendarData.pick(state, date)
            }
        }
        saveState(context, id, next)
        draw(context, AppWidgetManager.getInstance(context), id, prefs)
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        super.onDeleted(context, appWidgetIds)
        val e = statePrefs(context).edit()
        for (id in appWidgetIds) e.remove(stateKey(id))
        e.apply()
    }

    // ---- Estado por widget ---------------------------------------------------

    private fun statePrefs(context: Context) = context.getSharedPreferences(STATE_PREFS, Context.MODE_PRIVATE)
    private fun stateKey(id: Int) = "state_$id"

    private fun loadState(context: Context, id: Int, today: LocalDate): CalendarData.State {
        val stored = CalendarData.State.decode(statePrefs(context).getString(stateKey(id), null))
        val resolved = CalendarData.resolve(stored, today)
        if (resolved != stored) saveState(context, id, resolved)
        return resolved
    }

    private fun saveState(context: Context, id: Int, state: CalendarData.State) {
        statePrefs(context).edit().putString(stateKey(id), state.encode()).apply()
    }

    // ---- Auxiliares ----------------------------------------------------------

    /** Cada célula/seta tem a sua URI (e o id do widget nela) para os PendingIntents não se sobrescreverem. */
    private fun action(context: Context, id: Int, action: String, date: LocalDate?): PendingIntent {
        val intent = Intent(context, CalendarioWidgetProvider::class.java)
            .setAction(action)
            .setData(Uri.parse("organizacional://calendario/$id/${action.substringAfterLast('.')}/${date ?: ""}"))
            .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
        if (date != null) intent.putExtra(EXTRA_DATE, date.toString())
        return PendingIntent.getBroadcast(
            context, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun dim(color: Int): Int = (color and 0x00FFFFFF) or 0x80000000.toInt()

    private fun showText(views: RemoteViews, id: Int, theme: WidgetTheme, text: String) {
        views.setViewVisibility(id, View.VISIBLE)
        views.setTextViewText(id, text)
        views.setTextColor(id, theme.inkMuted)
    }

    companion object {
        const val URI_AGENDA = "organizacional://agenda"
        const val ACTION_PREV = "dev.organizacional.organizacional.widgets.CAL_PREV"
        const val ACTION_NEXT = "dev.organizacional.organizacional.widgets.CAL_NEXT"
        const val ACTION_PICK = "dev.organizacional.organizacional.widgets.CAL_PICK"
        const val EXTRA_DATE = "date"
        private const val STATE_PREFS = "org_calendar_widget"
    }
}
