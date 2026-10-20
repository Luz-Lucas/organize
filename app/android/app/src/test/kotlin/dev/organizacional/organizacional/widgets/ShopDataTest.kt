package dev.organizacional.organizacional.widgets

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ShopDataTest {
    private val json = """
        {"listId":"l1","listName":"Mercado","sections":[
          {"name":"hortifruti","label":"Hortifrúti","items":[
            {"id":"1","name":"Alface","quantity":""},
            {"id":"2","name":"Maçã","quantity":"6"}]},
          {"name":"mercearia","label":"Mercearia","items":[
            {"id":"3","name":"Arroz","quantity":"2 kg"}]}
        ]}
    """.trimIndent()

    @Test fun parsesListSectionsAndItems() {
        val s = ShopData.parse(json)
        assertEquals("l1", s.listId)
        assertEquals("Mercado", s.listName)
        assertEquals(listOf("Hortifrúti", "Mercearia"), s.sections.map { it.label })
        assertEquals(listOf("Alface", "Maçã"), s.sections[0].items.map { it.name })
        assertEquals("2 kg", s.sections[1].items.single().quantity)
        assertEquals(3, ShopData.count(s))
    }

    @Test fun noListYetOrGarbageIsAnEmptyShopWithoutError() {
        // Review Focus 5: usuário nunca abriu Compras.
        val none = ShopData.parse("""{"listId":null,"listName":"Mercado","sections":[]}""")
        assertNull(none.listId)
        assertEquals(0, ShopData.count(none))
        assertEquals(0, ShopData.count(ShopData.parse(null)))
        assertEquals(0, ShopData.count(ShopData.parse("")))
        assertEquals(0, ShopData.count(ShopData.parse("{")))
        assertEquals("Mercado", ShopData.parse("lixo").listName)
    }

    @Test fun title() {
        assertEquals("Mercado · 3 itens", ShopData.title(ShopData.parse(json)))
        val one = ShopData.parse(ShopData.removeItem(ShopData.removeItem(json, "1")!!, "2")!!)
        assertEquals("Mercado · 1 item", ShopData.title(one))
        assertEquals("Mercado", ShopData.title(ShopData.parse(null)))
        assertEquals(
            "Feira",
            ShopData.title(ShopData.parse("""{"listId":"x","listName":"Feira","sections":[]}""")),
        )
    }

    @Test fun removeItemDropsItAndEmptySections() {
        val after = ShopData.removeItem(json, "3")!!
        val s = ShopData.parse(after)
        assertEquals(listOf("Hortifrúti"), s.sections.map { it.label })
        assertEquals(2, ShopData.count(s))
        assertEquals("l1", s.listId)
        assertEquals("Mercado", s.listName)
    }

    @Test fun removeItemKeepsOtherItemsOfTheSection() {
        val s = ShopData.parse(ShopData.removeItem(json, "1")!!)
        assertEquals(listOf("Maçã"), s.sections[0].items.map { it.name })
    }

    @Test fun removeUnknownItemOrBadJsonChangesNothing() {
        assertNull(ShopData.removeItem(json, "zzz"))
        assertNull(ShopData.removeItem(null, "1"))
        assertNull(ShopData.removeItem("{", "1"))
    }

    @Test fun linesHaveHeadersBeforeTheirItems() {
        val l = ShopData.lines(ShopData.parse(json), maxLines = 12)
        assertEquals(0, l.hidden)
        assertEquals(
            listOf("H:Hortifrúti", "I:Alface", "I:Maçã", "H:Mercearia", "I:Arroz"),
            l.lines.map(::tag),
        )
    }

    @Test fun linesTruncateAndCountHiddenItems() {
        val l = ShopData.lines(ShopData.parse(json), maxLines = 4)
        assertEquals(listOf("H:Hortifrúti", "I:Alface", "I:Maçã"), l.lines.map(::tag))
        // O cabeçalho "Mercearia" não fica sozinho no fim: sai junto com o item que esconde.
        assertEquals(1, l.hidden)
    }

    @Test fun linesFillExactlyMaxLinesWhenTheCutFallsOnAnItem() {
        val l = ShopData.lines(ShopData.parse(json), maxLines = 3)
        assertEquals(listOf("H:Hortifrúti", "I:Alface", "I:Maçã"), l.lines.map(::tag))
        assertEquals(1, l.hidden)
        assertTrue(l.lines.last() is ShopLine.Item)
    }

    @Test fun maxLinesFollowsHeightWithinBounds() {
        assertEquals(8, ShopData.maxLines(0)) // desconhecida
        assertTrue(ShopData.maxLines(250) >= 3)
        assertTrue(ShopData.maxLines(500) > ShopData.maxLines(250))
        assertEquals(12, ShopData.maxLines(2000))
    }

    @Test fun tapUriUsesTheSameShapeAsTheDartSide() {
        assertEquals("organizacional://mercado/check?id=abc-1", ShopData.checkUri("abc-1"))
        assertEquals("abc-1", ShopData.itemIdFromUri("organizacional://mercado/check?id=abc-1"))
        assertNull(ShopData.itemIdFromUri("organizacional://compras"))
        assertNull(ShopData.itemIdFromUri(null))
    }

    private fun tag(l: ShopLine) = when (l) {
        is ShopLine.Header -> "H:${l.label}"
        is ShopLine.Item -> "I:${l.name}"
    }
}
