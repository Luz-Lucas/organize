package dev.organizacional.organizacional.widgets

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate
import java.time.YearMonth
import java.time.ZoneId
import java.time.ZonedDateTime

class CalendarDataTest {
    private val sp = ZoneId.of("America/Sao_Paulo")
    private fun ms(y: Int, m: Int, d: Int, h: Int = 0, min: Int = 0) =
        ZonedDateTime.of(y, m, d, h, min, 0, 0, sp).toInstant().toEpochMilli()

    private fun ev(
        id: String, s: Long, e: Long, allDay: Boolean = false, tag: Int? = null,
    ) = WidgetEvent(id, id, s, e, allDay, null, "outro", tag)

    private val accent = 0xFFC0A9FF.toInt()

    // ---- Grade (Review Focus 1) ----

    @Test fun gridHas42CellsStartingOnMonday() {
        val g = CalendarData.monthGrid(YearMonth.of(2026, 10)) // 1/out/2026 é quinta
        assertEquals(42, g.size)
        assertEquals(LocalDate.of(2026, 9, 28), g.first())
        assertEquals(LocalDate.of(2026, 11, 8), g.last())
        assertEquals(java.time.DayOfWeek.MONDAY, g.first().dayOfWeek)
    }

    @Test fun monthStartingOnSundayHasSixLeadingDaysAndSixWeeks() {
        val g = CalendarData.monthGrid(YearMonth.of(2026, 11)) // 1/nov/2026 é domingo
        assertEquals(LocalDate.of(2026, 10, 26), g.first())
        assertEquals(LocalDate.of(2026, 11, 1), g[6])
        assertEquals(LocalDate.of(2026, 11, 30), g[35])
        assertEquals(LocalDate.of(2026, 12, 6), g.last())
    }

    @Test fun monthStartingOnMondayHasNoLeadingDays() {
        val g = CalendarData.monthGrid(YearMonth.of(2026, 6)) // 1/jun/2026 é segunda
        assertEquals(LocalDate.of(2026, 6, 1), g.first())
    }

    @Test fun februaryStartingOnSundayStillFillsSixRows() {
        val g = CalendarData.monthGrid(YearMonth.of(2026, 2)) // 1/fev/2026 é domingo
        assertEquals(LocalDate.of(2026, 1, 26), g.first())
        assertEquals(LocalDate.of(2026, 3, 8), g.last())
    }

    // ---- Eventos por dia (Review Focus 2) ----

    @Test fun overnightEventAppearsOnBothDaysOnly() {
        val e = ev("plantao", ms(2026, 10, 11, 22), ms(2026, 10, 12, 2))
        fun on(d: Int) = CalendarData.eventsOnDate(listOf(e), LocalDate.of(2026, 10, d), sp).size
        assertEquals(0, on(10))
        assertEquals(1, on(11))
        assertEquals(1, on(12))
        assertEquals(0, on(13))
    }

    @Test fun multiDayAllDayEventAppearsOnEveryDayItTouches() {
        // 12 a 14/out, dia inteiro, fim = 00:00 do dia 15 (exclusivo).
        val e = ev("viagem", ms(2026, 10, 12), ms(2026, 10, 15), allDay = true)
        fun on(d: Int) = CalendarData.eventsOnDate(listOf(e), LocalDate.of(2026, 10, d), sp).size
        assertEquals(0, on(11))
        assertEquals(1, on(12))
        assertEquals(1, on(13))
        assertEquals(1, on(14))
        assertEquals(0, on(15))
    }

    @Test fun eventEndingExactlyAtMidnightDoesNotTouchNextDay() {
        val e = ev("noite", ms(2026, 10, 11, 20), ms(2026, 10, 12, 0))
        assertEquals(1, CalendarData.eventsOnDate(listOf(e), LocalDate.of(2026, 10, 11), sp).size)
        assertEquals(0, CalendarData.eventsOnDate(listOf(e), LocalDate.of(2026, 10, 12), sp).size)
    }

    @Test fun zeroLengthEventCountsOnItsDay() {
        val e = ev("ponto", ms(2026, 10, 11, 9), ms(2026, 10, 11, 9))
        assertEquals(1, CalendarData.eventsOnDate(listOf(e), LocalDate.of(2026, 10, 11), sp).size)
        assertEquals(0, CalendarData.eventsOnDate(listOf(e), LocalDate.of(2026, 10, 12), sp).size)
    }

    @Test fun dayEventsHaveAllDayFirstThenByStart() {
        val a = ev("tarde", ms(2026, 10, 11, 15), ms(2026, 10, 11, 16))
        val b = ev("manha", ms(2026, 10, 11, 8), ms(2026, 10, 11, 9))
        val c = ev("dia", ms(2026, 10, 11), ms(2026, 10, 12), allDay = true)
        val r = CalendarData.eventsOnDate(listOf(a, b, c), LocalDate.of(2026, 10, 11), sp)
        assertEquals(listOf("dia", "manha", "tarde"), r.map { it.id })
    }

    // ---- Células ----

    @Test fun cellsMarkTodaySelectedDotsAndOtherMonths() {
        val month = YearMonth.of(2026, 10)
        val today = LocalDate.of(2026, 10, 20)
        val selected = LocalDate.of(2026, 10, 22)
        val tagged = ev("a", ms(2026, 10, 22, 9), ms(2026, 10, 22, 10), tag = 0xFF3E63DD.toInt())
        val plain = ev("b", ms(2026, 10, 25, 9), ms(2026, 10, 25, 10))
        val cells = CalendarData.cells(month, selected, today, listOf(tagged, plain), accent, sp)
        assertEquals(42, cells.size)
        fun cell(d: LocalDate) = cells.first { it.date == d }
        assertTrue(cell(today).isToday)
        assertFalse(cell(today).isSelected)
        assertTrue(cell(selected).isSelected)
        assertEquals(0xFF3E63DD.toInt(), cell(selected).dotColor)
        assertEquals(accent, cell(LocalDate.of(2026, 10, 25)).dotColor)
        assertNull(cell(LocalDate.of(2026, 10, 21)).dotColor)
        assertFalse(cell(LocalDate.of(2026, 9, 30)).inMonth)
        assertTrue(cell(LocalDate.of(2026, 10, 1)).inMonth)
        assertFalse(cell(LocalDate.of(2026, 11, 1)).inMonth)
    }

    @Test fun dotPrefersTheFirstTagColorOfTheDay() {
        val plain = ev("a", ms(2026, 10, 22, 8), ms(2026, 10, 22, 9))
        val tagged = ev("b", ms(2026, 10, 22, 10), ms(2026, 10, 22, 11), tag = 0xFFAA0000.toInt())
        val cells = CalendarData.cells(
            YearMonth.of(2026, 10), LocalDate.of(2026, 10, 1), LocalDate.of(2026, 10, 1),
            listOf(plain, tagged), accent, sp,
        )
        assertEquals(0xFFAA0000.toInt(), cells.first { it.date == LocalDate.of(2026, 10, 22) }.dotColor)
    }

    @Test fun eventsOfNeighbourMonthsShowOnDimmedCells() {
        val e = ev("a", ms(2026, 9, 30, 9), ms(2026, 9, 30, 10))
        val cells = CalendarData.cells(
            YearMonth.of(2026, 10), LocalDate.of(2026, 10, 1), LocalDate.of(2026, 10, 1), listOf(e), accent, sp,
        )
        val c = cells.first { it.date == LocalDate.of(2026, 9, 30) }
        assertFalse(c.inMonth)
        assertEquals(accent, c.dotColor)
    }

    // ---- Estado (dia escolhido / mês exibido) ----

    private val today = LocalDate.of(2026, 10, 20)
    private val range = CalendarData.Range(ms(2026, 9, 1), ms(2026, 12, 1))

    @Test fun noStoredStateStartsOnToday() {
        val s = CalendarData.resolve(null, today)
        assertEquals(today, s.selected)
        assertEquals(YearMonth.of(2026, 10), s.month)
        assertEquals(today, s.on)
    }

    @Test fun storedStateIsKeptWithinTheSameDay() {
        val stored = CalendarData.State(YearMonth.of(2026, 11), LocalDate.of(2026, 11, 3), today)
        assertEquals(stored, CalendarData.resolve(stored, today))
    }

    @Test fun whenTheDayRollsOverSelectionGoesBackToToday() {
        // Review Focus 3: escolhido ontem para 5/nov; hoje é outro dia -> volta para hoje.
        val stored = CalendarData.State(YearMonth.of(2026, 11), LocalDate.of(2026, 11, 5), today)
        val tomorrow = today.plusDays(1)
        val s = CalendarData.resolve(stored, tomorrow)
        assertEquals(tomorrow, s.selected)
        assertEquals(YearMonth.of(2026, 10), s.month)
        assertEquals(tomorrow, s.on)
    }

    @Test fun stateEncodeDecodeRoundTripAndGarbage() {
        val s = CalendarData.State(YearMonth.of(2026, 11), LocalDate.of(2026, 11, 3), today)
        assertEquals(s, CalendarData.State.decode(s.encode()))
        assertNull(CalendarData.State.decode(null))
        assertNull(CalendarData.State.decode(""))
        assertNull(CalendarData.State.decode("lixo"))
        assertNull(CalendarData.State.decode("2026-13|2026-11-03|2026-10-20"))
    }

    @Test fun pickChangesOnlyTheSelectedDay() {
        val s = CalendarData.resolve(null, today)
        val p = CalendarData.pick(s, LocalDate.of(2026, 10, 25))
        assertEquals(LocalDate.of(2026, 10, 25), p.selected)
        assertEquals(s.month, p.month)
        assertEquals(today, p.on)
    }

    @Test fun shiftMovesMonthAndSelectsFirstDayOrTodayForCurrentMonth() {
        val s = CalendarData.resolve(null, today)
        val next = CalendarData.shift(s, +1, range, today, sp)
        assertEquals(YearMonth.of(2026, 11), next.month)
        assertEquals(LocalDate.of(2026, 11, 1), next.selected)
        val back = CalendarData.shift(next, -1, range, today, sp)
        assertEquals(YearMonth.of(2026, 10), back.month)
        assertEquals(today, back.selected)
    }

    @Test fun shiftStopsAtTheDataWindow() {
        val s = CalendarData.resolve(null, today)
        val prev = CalendarData.shift(s, -1, range, today, sp)
        assertEquals(YearMonth.of(2026, 9), prev.month)
        assertEquals(prev, CalendarData.shift(prev, -1, range, today, sp)) // além do início
        val next = CalendarData.shift(CalendarData.shift(s, +1, range, today, sp), +1, range, today, sp)
        assertEquals(YearMonth.of(2026, 11), next.month) // dezembro está fora (to é exclusivo)
    }

    @Test fun withoutARangeOnlyNeighbourMonthsOfTodayAreAllowed() {
        val s = CalendarData.resolve(null, today)
        val n1 = CalendarData.shift(s, +1, null, today, sp)
        assertEquals(YearMonth.of(2026, 11), n1.month)
        assertEquals(n1, CalendarData.shift(n1, +1, null, today, sp))
    }

    @Test fun parseRange() {
        val r = CalendarData.parseRange("""{"from":10,"to":20}""")!!
        assertEquals(10L, r.from)
        assertEquals(20L, r.to)
        assertNull(CalendarData.parseRange(null))
        assertNull(CalendarData.parseRange("{"))
        assertNull(CalendarData.parseRange("""{"from":10}"""))
    }

    // ---- Textos ----

    @Test fun titles() {
        assertEquals("outubro 2026", CalendarData.monthTitle(YearMonth.of(2026, 10)))
        assertEquals("março 2027", CalendarData.monthTitle(YearMonth.of(2027, 3)))
        assertEquals("qui, 22 out", CalendarData.dayTitle(LocalDate.of(2026, 10, 22)))
        assertEquals("dom, 1 nov", CalendarData.dayTitle(LocalDate.of(2026, 11, 1)))
        assertEquals(listOf("S", "T", "Q", "Q", "S", "S", "D"), CalendarData.WEEKDAY_INITIALS)
    }

    @Test fun eventRowsGrowWithHeightAndStayBetweenOneAndSix() {
        assertEquals(3, CalendarData.eventRows(0)) // altura desconhecida
        assertEquals(1, CalendarData.eventRows(250))
        assertTrue(CalendarData.eventRows(320) > CalendarData.eventRows(250))
        assertEquals(6, CalendarData.eventRows(900))
    }
}
