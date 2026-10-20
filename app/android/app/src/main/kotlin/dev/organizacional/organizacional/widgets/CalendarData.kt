package dev.organizacional.organizacional.widgets

import org.json.JSONObject
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.YearMonth
import java.time.ZoneId
import java.time.temporal.TemporalAdjusters

/**
 * Lógica pura do widget Calendário (sem Android, testável com JUnit): grade 6x7 do mês, eventos por
 * dia, cores dos pontos e o estado "mês exibido / dia escolhido" de cada widget.
 * Dados: `w_cal_events` (mesmo formato de `w_events`, sem `location`/`kind`) e `w_cal_range`.
 */
object CalendarData {
    const val KEY_EVENTS = "w_cal_events"
    const val KEY_RANGE = "w_cal_range"

    val WEEKDAY_INITIALS = listOf("S", "T", "Q", "Q", "S", "S", "D")
    private val MONTHS = listOf(
        "janeiro", "fevereiro", "março", "abril", "maio", "junho",
        "julho", "agosto", "setembro", "outubro", "novembro", "dezembro",
    )
    private val MONTHS_SHORT = listOf("jan", "fev", "mar", "abr", "mai", "jun", "jul", "ago", "set", "out", "nov", "dez")
    private val WEEKDAYS_SHORT = listOf("seg", "ter", "qua", "qui", "sex", "sáb", "dom")

    /** Janela de dados do widget (epoch millis; [to] exclusivo). As setas não passam dela. */
    data class Range(val from: Long, val to: Long)

    fun parseRange(json: String?): Range? = try {
        if (json.isNullOrBlank()) null else {
            val o = JSONObject(json)
            if (!o.has("from") || !o.has("to")) null else Range(o.getLong("from"), o.getLong("to"))
        }
    } catch (_: Exception) {
        null
    }

    // ---- Grade ---------------------------------------------------------

    /** 42 datas (6 semanas, segunda a domingo) que cobrem o [month]. */
    fun monthGrid(month: YearMonth): List<LocalDate> {
        val first = month.atDay(1).with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
        return List(42) { first.plusDays(it.toLong()) }
    }

    /** Eventos que tocam o [date] (calendário local); dia inteiro primeiro, depois por início. */
    fun eventsOnDate(events: List<WidgetEvent>, date: LocalDate, zone: ZoneId): List<WidgetEvent> {
        val s = date.atStartOfDay(zone).toInstant().toEpochMilli()
        val e = date.plusDays(1).atStartOfDay(zone).toInstant().toEpochMilli()
        return events
            .filter { it.start < e && (it.end > s || (it.end <= it.start && it.start >= s)) }
            .sortedWith(compareBy<WidgetEvent>({ !it.allDay }, { it.start }))
    }

    data class Cell(
        val date: LocalDate,
        val inMonth: Boolean,
        val isToday: Boolean,
        val isSelected: Boolean,
        /** Cor do pontinho (etiqueta do primeiro evento etiquetado, senão destaque); null = dia sem eventos. */
        val dotColor: Int?,
    )

    fun cells(
        month: YearMonth,
        selected: LocalDate,
        today: LocalDate,
        events: List<WidgetEvent>,
        accent: Int,
        zone: ZoneId,
    ): List<Cell> = monthGrid(month).map { d ->
        val evs = eventsOnDate(events, d, zone)
        Cell(
            date = d,
            inMonth = YearMonth.from(d) == month,
            isToday = d == today,
            isSelected = d == selected,
            dotColor = if (evs.isEmpty()) null else (evs.firstNotNullOfOrNull { it.tagColor } ?: accent),
        )
    }

    // ---- Estado por widget ---------------------------------------------

    /**
     * Mês exibido, dia escolhido e o dia de hoje em que a escolha foi feita ([on]). Quando o dia vira
     * ([on] != hoje) a escolha é descartada e volta para hoje.
     */
    data class State(val month: YearMonth, val selected: LocalDate, val on: LocalDate) {
        fun encode(): String = "$month|$selected|$on"

        companion object {
            fun decode(raw: String?): State? = try {
                val p = raw?.split("|")
                if (p == null || p.size != 3) null
                else State(YearMonth.parse(p[0]), LocalDate.parse(p[1]), LocalDate.parse(p[2]))
            } catch (_: Exception) {
                null
            }
        }
    }

    fun resolve(stored: State?, today: LocalDate): State =
        if (stored == null || stored.on != today) State(YearMonth.from(today), today, today) else stored

    fun pick(state: State, date: LocalDate): State = state.copy(selected = date)

    /** Meses permitidos [primeiro, último]; sem janela: o mês de hoje e os vizinhos. */
    private fun allowedMonths(range: Range?, today: LocalDate, zone: ZoneId): Pair<YearMonth, YearMonth> {
        if (range == null) return YearMonth.from(today).minusMonths(1) to YearMonth.from(today).plusMonths(1)
        val from = YearMonth.from(Instant.ofEpochMilli(range.from).atZone(zone))
        val last = YearMonth.from(Instant.ofEpochMilli(maxOf(range.from, range.to - 1)).atZone(zone))
        return from to last
    }

    /** Seta ‹ (-1) / › (+1). Fora da janela de dados nada muda. O mês de hoje seleciona hoje; os outros, o dia 1. */
    fun shift(state: State, delta: Int, range: Range?, today: LocalDate, zone: ZoneId): State {
        val target = state.month.plusMonths(delta.toLong())
        val (first, last) = allowedMonths(range, today, zone)
        if (target < first || target > last) return state
        val selected = if (target == YearMonth.from(today)) today else target.atDay(1)
        return state.copy(month = target, selected = selected)
    }

    // ---- Textos e medidas ----------------------------------------------

    fun monthTitle(month: YearMonth): String = "${MONTHS[month.monthValue - 1]} ${month.year}"

    fun dayTitle(date: LocalDate): String =
        "${WEEKDAYS_SHORT[date.dayOfWeek.value - 1]}, ${date.dayOfMonth} ${MONTHS_SHORT[date.monthValue - 1]}"

    /**
     * Linhas de eventos do dia que cabem abaixo da grade (1 a [cap]); a grade (cabeçalho, iniciais e
     * 6 semanas) e o cabeçalho da lista ocupam [fixedDp]. Altura desconhecida (<= 0) -> 3.
     */
    fun eventRows(heightDp: Int, cap: Int = 6, fixedDp: Int = 240, rowDp: Int = 20): Int {
        if (heightDp <= 0) return minOf(3, cap)
        return ((heightDp - fixedDp) / rowDp).coerceIn(1, cap)
    }
}
