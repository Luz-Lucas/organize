package dev.organizacional.organizacional.widgets

import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit

/** Contrato de dados (Dart grava -> Kotlin lê). Veja docs/superpowers/specs/2026-10-11-widgets-android-design.md. */

data class WidgetTheme(
    val surface: Int,
    val surfaceRaised: Int,
    val line: Int,
    val ink: Int,
    val inkMuted: Int,
    val accentDeep: Int,
    val onAccent: Int,
    val accentText: Int,
    val accentSoft: Int,
    val danger: Int,
)

data class WidgetEvent(
    val id: String,
    val title: String,
    val start: Long,
    val end: Long,
    val allDay: Boolean,
    val location: String?,
    val kind: String,
    /** Cor da etiqueta do evento (ARGB), ou null se não tiver etiqueta. */
    val tagColor: Int? = null,
)

data class WidgetTask(
    val id: String,
    val title: String,
    val status: String,
    val due: Long?,
)

object WidgetData {
    const val KEY_STATE = "w_state"
    const val KEY_GENERATED_AT = "w_generated_at"
    const val KEY_THEME = "w_theme"
    const val KEY_EVENTS = "w_events"
    const val KEY_TASKS = "w_tasks"
    /** Opacidade do fundo (0-255), preferência do aparelho gravada pelo app; ausente = opaco. */
    const val KEY_BG_ALPHA = "w_bg_alpha"

    const val STATE_OK = "ok"
    const val STATE_SIGNED_OUT = "signed_out"
    const val STATE_ERROR = "error"

    const val STALE_AFTER_MILLIS = 3L * 60 * 60 * 1000

    // Fallback: tema Violeta.
    val VIOLETA = WidgetTheme(
        surface = 0xFF160F1E.toInt(),
        surfaceRaised = 0xFF251E2D.toInt(),
        line = 0xFF413B49.toInt(),
        ink = 0xFFEFE9F7.toInt(),
        inkMuted = 0xFF9B8FAE.toInt(),
        accentDeep = 0xFF6633CC.toInt(),
        onAccent = 0xFFFFFFFF.toInt(),
        accentText = 0xFFC0A9FF.toInt(),
        accentSoft = 0xFF291B41.toInt(),
        danger = 0xFFF2726B.toInt(),
    )

    // ---- Parsing -------------------------------------------------------

    /** '#RRGGBB' (ou '#AARRGGBB') -> cor ARGB; qualquer outra coisa -> [fallback]. */
    fun parseColor(value: String?, fallback: Int): Int {
        if (value == null) return fallback
        val s = value.trim().removePrefix("#")
        if (!s.all { it.isDigit() || it.lowercaseChar() in 'a'..'f' }) return fallback
        return when (s.length) {
            6 -> (0xFF000000L or s.toLong(16)).toInt()
            8 -> s.toLong(16).toInt()
            else -> fallback
        }
    }

    /** '#RRGGBB' / '#AARRGGBB' válido -> cor; vazio, nulo ou inválido -> null (evento sem etiqueta). */
    fun parseOptionalColor(value: String?): Int? {
        if (value.isNullOrBlank()) return null
        val s = value.trim().removePrefix("#")
        if (s.length != 6 && s.length != 8) return null
        if (!s.all { it.isDigit() || it.lowercaseChar() in 'a'..'f' }) return null
        return parseColor(value, 0)
    }

    /** Marca que antecede o título de um evento com etiqueta (o ponto é pintado com a cor dela). */
    const val TAG_DOT = "●"

    /** Título com o ponto da etiqueta na frente; sem etiqueta, o título como está. */
    fun titleWithDot(e: WidgetEvent): String = if (e.tagColor == null) e.title else "$TAG_DOT ${e.title}"

    fun parseThemeJson(json: String?): WidgetTheme {
        val o = try {
            if (json.isNullOrBlank()) null else JSONObject(json)
        } catch (_: Exception) {
            null
        } ?: return VIOLETA
        fun c(key: String, fb: Int) = parseColor(o.optString(key, ""), fb)
        val v = VIOLETA
        return WidgetTheme(
            surface = c("surface", v.surface),
            surfaceRaised = c("surfaceRaised", v.surfaceRaised),
            line = c("line", v.line),
            ink = c("ink", v.ink),
            inkMuted = c("inkMuted", v.inkMuted),
            accentDeep = c("accentDeep", v.accentDeep),
            onAccent = c("onAccent", v.onAccent),
            accentText = c("accentText", v.accentText),
            accentSoft = c("accentSoft", v.accentSoft),
            danger = c("danger", v.danger),
        )
    }

    /** Opacidade do fundo: número 0-255 (limitado); ausente ou inválido -> 255 (opaco). */
    fun parseBgAlpha(value: String?): Int =
        value?.trim()?.toIntOrNull()?.coerceIn(0, 255) ?: 255

    fun parseEventsJson(json: String?): List<WidgetEvent> {
        val arr = try {
            if (json.isNullOrBlank()) null else JSONArray(json)
        } catch (_: Exception) {
            null
        } ?: return emptyList()
        val out = ArrayList<WidgetEvent>(arr.length())
        for (i in 0 until arr.length()) {
            val o = arr.optJSONObject(i) ?: continue
            if (!o.has("start") || o.isNull("start")) continue
            val start = o.optLong("start")
            val end = if (o.has("end") && !o.isNull("end")) o.optLong("end") else start
            out.add(
                WidgetEvent(
                    id = o.optString("id", ""),
                    title = o.optString("title", ""),
                    start = start,
                    end = end,
                    allDay = o.optBoolean("allDay", false),
                    location = if (o.isNull("location")) null
                    else o.optString("location", "").ifBlank { null },
                    kind = o.optString("kind", "outro"),
                    tagColor = parseOptionalColor(o.optString("tagColor", "")),
                ),
            )
        }
        return out.sortedBy { it.start }
    }

    fun parseTasksJson(json: String?): List<WidgetTask> {
        val arr = try {
            if (json.isNullOrBlank()) null else JSONArray(json)
        } catch (_: Exception) {
            null
        } ?: return emptyList()
        val out = ArrayList<WidgetTask>(arr.length())
        for (i in 0 until arr.length()) {
            val o = arr.optJSONObject(i) ?: continue
            out.add(
                WidgetTask(
                    id = o.optString("id", ""),
                    title = o.optString("title", ""),
                    status = o.optString("status", "todo"),
                    due = if (o.has("due") && !o.isNull("due")) o.optLong("due") else null,
                ),
            )
        }
        return out
    }

    fun parseTheme(p: SharedPreferences) = parseThemeJson(p.getString(KEY_THEME, null))
    fun parseEvents(p: SharedPreferences) = parseEventsJson(p.getString(KEY_EVENTS, null))
    fun parseTasks(p: SharedPreferences) = parseTasksJson(p.getString(KEY_TASKS, null))
    fun bgAlpha(p: SharedPreferences): Int = parseBgAlpha(p.getString(KEY_BG_ALPHA, null))
    fun state(p: SharedPreferences): String = p.getString(KEY_STATE, null) ?: STATE_OK
    fun generatedAt(p: SharedPreferences): Long? = p.getString(KEY_GENERATED_AT, null)?.toLongOrNull()

    // ---- Datas (calendário local do aparelho, java.time) ----------------

    private fun zdt(millis: Long, zone: ZoneId): ZonedDateTime =
        Instant.ofEpochMilli(millis).atZone(zone)

    fun startOfDay(nowMillis: Long, zone: ZoneId): Long =
        zdt(nowMillis, zone).toLocalDate().atStartOfDay(zone).toInstant().toEpochMilli()

    fun endOfDay(nowMillis: Long, zone: ZoneId): Long =
        zdt(nowMillis, zone).toLocalDate().plusDays(1).atStartOfDay(zone).toInstant().toEpochMilli()

    /** Eventos cujo intervalo toca o dia de hoje; dia inteiro primeiro, depois por início. */
    fun eventsToday(events: List<WidgetEvent>, nowMillis: Long, zone: ZoneId): List<WidgetEvent> {
        val s = startOfDay(nowMillis, zone)
        val e = endOfDay(nowMillis, zone)
        return events
            .filter { it.start < e && (it.end > s || (it.end <= it.start && it.start >= s)) }
            .sortedWith(compareBy<WidgetEvent>({ !it.allDay }, { it.start }))
    }

    /** Dias de calendário entre hoje e o dia de [startMillis] (negativo se já passou). */
    fun daysUntil(startMillis: Long, nowMillis: Long, zone: ZoneId): Int {
        val a = zdt(nowMillis, zone).toLocalDate()
        val b = zdt(startMillis, zone).toLocalDate()
        return ChronoUnit.DAYS.between(a, b).toInt()
    }

    /** "hoje" / "amanhã" / "dd/MM". */
    fun dayLabel(dueMillis: Long, nowMillis: Long, zone: ZoneId): String =
        when (daysUntil(dueMillis, nowMillis, zone)) {
            0 -> "hoje"
            1 -> "amanhã"
            else -> zdt(dueMillis, zone).format(DDMM)
        }

    fun isOverdue(dueMillis: Long, nowMillis: Long, zone: ZoneId): Boolean =
        dueMillis < startOfDay(nowMillis, zone)

    fun isStale(generatedAt: Long?, nowMillis: Long): Boolean =
        generatedAt == null || nowMillis - generatedAt > STALE_AFTER_MILLIS

    private val DDMM = DateTimeFormatter.ofPattern("dd/MM")
    private val HHMM = DateTimeFormatter.ofPattern("HH:mm")

    fun hhmm(millis: Long, zone: ZoneId): String = zdt(millis, zone).format(HHMM)

    /** Texto da coluna de horário do widget Hoje. */
    fun eventTimeLabel(e: WidgetEvent, nowMillis: Long, zone: ZoneId): String {
        if (e.allDay) return "Dia todo"
        val s = startOfDay(nowMillis, zone)
        val d = endOfDay(nowMillis, zone)
        val startsBefore = e.start < s
        val endsAfter = e.end > d
        return when {
            startsBefore && endsAfter -> "Dia todo"
            endsAfter -> "${hhmm(e.start, zone)} → amanhã"
            startsBefore -> "→ ${hhmm(e.end, zone)}"
            else -> hhmm(e.start, zone)
        }
    }

    /** Como [eventTimeLabel], porém curto o bastante para uma coluna de largura fixa. */
    fun eventTimeCompact(e: WidgetEvent, nowMillis: Long, zone: ZoneId): String {
        val label = eventTimeLabel(e, nowMillis, zone)
        return if (label.endsWith(" → amanhã")) "${hhmm(e.start, zone)} →" else label
    }

    /** "+N mais". */
    fun moreLabel(extra: Int): String = "+$extra mais"

    /** Primeira prova que ainda não terminou. */
    fun nextExam(events: List<WidgetEvent>, nowMillis: Long): WidgetEvent? =
        events.filter { it.kind == "prova" && maxOf(it.end, it.start) > nowMillis }
            .minByOrNull { it.start }

    /** "hoje às 14:00" / "amanhã às 14:00" / "em N dias" / "em andamento". */
    fun examWhen(e: WidgetEvent, nowMillis: Long, zone: ZoneId): String {
        val n = daysUntil(e.start, nowMillis, zone)
        val at = if (e.allDay) "" else " às ${hhmm(e.start, zone)}"
        return when {
            n < 0 -> "em andamento"
            n == 0 -> "hoje$at"
            n == 1 -> "amanhã$at"
            else -> "em $n dias"
        }
    }

    // ---- Cores das linhas (compartilhadas por Hoje, Tarefas e Agenda e Tarefas) ----

    private fun isOngoing(e: WidgetEvent, nowMillis: Long) =
        !e.allDay && e.start <= nowMillis && nowMillis < e.end

    /** Título do evento: em andamento = accentText; já terminado = inkMuted; senão ink. */
    fun eventTitleColor(e: WidgetEvent, nowMillis: Long, theme: WidgetTheme): Int = when {
        isOngoing(e, nowMillis) -> theme.accentText
        !e.allDay && e.end <= nowMillis -> theme.inkMuted
        else -> theme.ink
    }

    /** Horário do evento: em andamento = accentText; senão inkMuted. */
    fun eventTimeColor(e: WidgetEvent, nowMillis: Long, theme: WidgetTheme): Int =
        if (isOngoing(e, nowMillis)) theme.accentText else theme.inkMuted

    /** Título da tarefa: "doing" = accentText; senão ink. */
    fun taskTitleColor(t: WidgetTask, theme: WidgetTheme): Int =
        if (t.status == "doing") theme.accentText else theme.ink

    /** Prazo da tarefa: atrasada = danger; senão inkMuted. */
    fun taskDueColor(due: Long, nowMillis: Long, zone: ZoneId, theme: WidgetTheme): Int =
        if (isOverdue(due, nowMillis, zone)) theme.danger else theme.inkMuted

    /**
     * Linhas por seção do widget "Agenda e Tarefas" (duas metades iguais, em cima e embaixo),
     * de 1 até [cap]. Descontam o padding (24 dp), o separador (13 dp) e, por metade, o título e
     * a linha "+N mais" ([sectionFixedDp]). Altura desconhecida (<= 0) -> 4 linhas.
     */
    fun sectionRows(
        heightDp: Int,
        cap: Int = 6,
        paddingDp: Int = 24,
        dividerDp: Int = 13,
        sectionFixedDp: Int = 36,
        rowDp: Int = 20,
    ): Int {
        if (heightDp <= 0) return minOf(4, cap)
        val half = (heightDp - paddingDp - dividerDp) / 2
        return ((half - sectionFixedDp) / rowDp).coerceIn(1, cap)
    }

    /**
     * Altura (dp) realmente disponível: em pé vale o MAX_HEIGHT do launcher, deitado o
     * MIN_HEIGHT. Sem MAX informado, cai para o MIN; 0 = desconhecida.
     */
    fun effectiveHeightDp(minDp: Int, maxDp: Int, portrait: Boolean): Int =
        if (portrait && maxDp > 0) maxDp else minDp

    /** Quantas linhas cabem na altura (dp) do widget, limitado a [cap]. */
    fun rowsFor(heightDp: Int, cap: Int, fixedDp: Int = 44, rowDp: Int = 18): Int {
        if (heightDp <= 0) return cap
        return ((heightDp - fixedDp) / rowDp).coerceIn(1, cap)
    }
}
