package dev.organizacional.organizacional.widgets

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.ZoneId
import java.time.ZonedDateTime

class WidgetDataTest {
    private val sp = ZoneId.of("America/Sao_Paulo")
    private fun ms(y: Int, m: Int, d: Int, h: Int = 0, min: Int = 0) =
        ZonedDateTime.of(y, m, d, h, min, 0, 0, sp).toInstant().toEpochMilli()

    private fun ev(title: String, s: Long, e: Long, kind: String = "outro", allDay: Boolean = false) =
        WidgetEvent(title, title, s, e, allDay, null, kind)

    @Test fun overnightEventShowsTodayAndTomorrow() {
        val e = ev("Plantão", ms(2026, 10, 11, 22), ms(2026, 10, 12, 2))
        val d11 = ms(2026, 10, 11, 12)
        val d12 = ms(2026, 10, 12, 12)
        assertEquals(1, WidgetData.eventsToday(listOf(e), d11, sp).size)
        assertEquals(1, WidgetData.eventsToday(listOf(e), d12, sp).size)
        assertEquals("22:00 → amanhã", WidgetData.eventTimeLabel(e, d11, sp))
        assertEquals("→ 02:00", WidgetData.eventTimeLabel(e, d12, sp))
        assertEquals(0, WidgetData.eventsToday(listOf(e), ms(2026, 10, 13, 12), sp).size)
    }

    @Test fun daysUntilUsesCalendarDays() {
        // 23:30 hoje -> 00:30 amanhã: 1 h de diferença, 1 dia de calendário.
        assertEquals(1, WidgetData.daysUntil(ms(2026, 10, 12, 0, 30), ms(2026, 10, 11, 23, 30), sp))
        assertEquals(0, WidgetData.daysUntil(ms(2026, 10, 11, 23, 59), ms(2026, 10, 11, 0, 1), sp))
        assertEquals(-1, WidgetData.daysUntil(ms(2026, 10, 10, 23), ms(2026, 10, 11, 1), sp))
    }

    @Test fun dayLabels() {
        val now = ms(2026, 10, 11, 12)
        assertEquals("hoje", WidgetData.dayLabel(ms(2026, 10, 11, 8), now, sp))
        assertEquals("amanhã", WidgetData.dayLabel(ms(2026, 10, 12, 23), now, sp))
        assertEquals("20/10", WidgetData.dayLabel(ms(2026, 10, 20), now, sp))
        assertTrue(WidgetData.isOverdue(ms(2026, 10, 10, 23), now, sp))
        assertTrue(!WidgetData.isOverdue(ms(2026, 10, 11, 1), now, sp))
    }

    @Test fun nextExamAndWhen() {
        val now = ms(2026, 10, 11, 12)
        val past = ev("Prova 1", ms(2026, 10, 10, 8), ms(2026, 10, 10, 10), "prova")
        val p2 = ev("Prova 2", ms(2026, 10, 14, 8), ms(2026, 10, 14, 10), "prova")
        assertEquals(p2, WidgetData.nextExam(listOf(past, p2, ev("M02", now, now + 1)), now))
        assertEquals("em 3 dias", WidgetData.examWhen(p2, now, sp))
        assertEquals("amanhã às 08:00", WidgetData.examWhen(ev("x", ms(2026, 10, 12, 8), ms(2026, 10, 12, 9)), now, sp))
        assertNull(WidgetData.nextExam(listOf(past), now))
    }

    @Test fun parsingIsTolerant() {
        assertEquals(WidgetData.VIOLETA, WidgetData.parseThemeJson("lixo"))
        assertEquals(WidgetData.VIOLETA, WidgetData.parseThemeJson(null))
        assertTrue(WidgetData.parseEventsJson("{").isEmpty())
        assertTrue(WidgetData.parseTasksJson(null).isEmpty())
        assertEquals(0xFF160F1E.toInt(), WidgetData.parseColor("#160F1E", 0))
        assertEquals(7, WidgetData.parseColor("zzz", 7))
        val evs = WidgetData.parseEventsJson(
            """[{"id":"a","title":"Say \"oi\"\n😀","start":5,"end":9,"allDay":false,"location":null,"kind":"prova"}]""",
        )
        assertEquals("Say \"oi\"\n😀", evs[0].title)
        assertNull(evs[0].location)
        val ts = WidgetData.parseTasksJson("""[{"id":"1","title":"t","status":"doing","due":null}]""")
        assertNull(ts[0].due)
    }

    @Test fun staleAfterThreeHours() {
        assertTrue(WidgetData.isStale(0L, 4L * 3600 * 1000))
        assertTrue(!WidgetData.isStale(0L, 2L * 3600 * 1000))
    }

    @Test fun splitRowsSharesSpaceAndKeepsAtLeastOneEach() {
        assertEquals(4 to 4, WidgetData.splitRows(8, 10, 10))
        assertEquals(2 to 3, WidgetData.splitRows(5, 2, 9))
        assertEquals(1 to 1, WidgetData.splitRows(2, 0, 0))
        assertEquals(1 to 1, WidgetData.splitRows(0, 4, 4))
        assertEquals(2 to 3, WidgetData.splitRows(5, 4, 4))
        assertEquals(1 to 4, WidgetData.splitRows(8, 0, 9))
    }

    @Test fun rowColorsFollowTheDisplayRules() {
        val t = WidgetData.VIOLETA
        val now = ms(2026, 10, 11, 12)
        val ongoing = ev("a", ms(2026, 10, 11, 11), ms(2026, 10, 11, 13))
        val done = ev("b", ms(2026, 10, 11, 8), ms(2026, 10, 11, 9))
        val later = ev("c", ms(2026, 10, 11, 15), ms(2026, 10, 11, 16))
        assertEquals(t.accentText, WidgetData.eventTitleColor(ongoing, now, t))
        assertEquals(t.accentText, WidgetData.eventTimeColor(ongoing, now, t))
        assertEquals(t.inkMuted, WidgetData.eventTitleColor(done, now, t))
        assertEquals(t.ink, WidgetData.eventTitleColor(later, now, t))
        assertEquals(t.inkMuted, WidgetData.eventTimeColor(later, now, t))
        assertEquals(t.danger, WidgetData.taskDueColor(ms(2026, 10, 10, 20), now, sp, t))
        assertEquals(t.inkMuted, WidgetData.taskDueColor(ms(2026, 10, 11, 8), now, sp, t))
        assertEquals(t.accentText, WidgetData.taskTitleColor(WidgetTask("1", "x", "doing", null), t))
        assertEquals(t.ink, WidgetData.taskTitleColor(WidgetTask("1", "x", "todo", null), t))
    }
}
