package dev.organizacional.organizacional.widgets

import org.json.JSONArray
import org.json.JSONObject
import java.net.URI

data class ShopItem(val id: String, val name: String, val quantity: String)
data class ShopSectionData(val name: String, val label: String, val items: List<ShopItem>)
data class Shop(val listId: String?, val listName: String, val sections: List<ShopSectionData>)

/** Uma linha desenhada no widget Mercado: cabeçalho de seção ou item. */
sealed class ShopLine {
    data class Header(val label: String) : ShopLine()
    data class Item(val id: String, val name: String, val quantity: String) : ShopLine()
}

data class ShopLines(val lines: List<ShopLine>, val hidden: Int)

/** Lógica pura do widget Mercado: leitura de `w_shop`, remoção local do item tocado e linhas conforme a altura. */
object ShopData {
    const val KEY_SHOP = "w_shop"
    private const val DEFAULT_NAME = "Mercado"

    fun parse(json: String?): Shop {
        val o = try {
            if (json.isNullOrBlank()) null else JSONObject(json)
        } catch (_: Exception) {
            null
        } ?: return Shop(null, DEFAULT_NAME, emptyList())
        val sections = ArrayList<ShopSectionData>()
        val arr = o.optJSONArray("sections") ?: JSONArray()
        for (i in 0 until arr.length()) {
            val s = arr.optJSONObject(i) ?: continue
            val itemsArr = s.optJSONArray("items") ?: JSONArray()
            val items = ArrayList<ShopItem>()
            for (j in 0 until itemsArr.length()) {
                val it = itemsArr.optJSONObject(j) ?: continue
                val id = it.optString("id", "")
                if (id.isEmpty()) continue
                items.add(ShopItem(id, it.optString("name", ""), it.optString("quantity", "")))
            }
            if (items.isNotEmpty()) {
                sections.add(ShopSectionData(s.optString("name", ""), s.optString("label", ""), items))
            }
        }
        return Shop(
            listId = if (o.isNull("listId")) null else o.optString("listId", "").ifBlank { null },
            listName = o.optString("listName", DEFAULT_NAME).ifBlank { DEFAULT_NAME },
            sections = sections,
        )
    }

    fun count(shop: Shop): Int = shop.sections.sumOf { it.items.size }

    /** "Mercado · 3 itens" / "Mercado · 1 item" / só o nome quando não há pendências. */
    fun title(shop: Shop): String {
        val n = count(shop)
        return when (n) {
            0 -> shop.listName
            1 -> "${shop.listName} · 1 item"
            else -> "${shop.listName} · $n itens"
        }
    }

    /**
     * JSON de [json] sem o item [id] (e sem a seção que ficou vazia); `null` se o item não existe
     * ou o JSON é inválido (nada a gravar).
     */
    fun removeItem(json: String?, id: String): String? {
        val o = try {
            if (json.isNullOrBlank()) null else JSONObject(json)
        } catch (_: Exception) {
            null
        } ?: return null
        val sections = o.optJSONArray("sections") ?: return null
        val kept = JSONArray()
        var found = false
        for (i in 0 until sections.length()) {
            val s = sections.optJSONObject(i) ?: continue
            val items = s.optJSONArray("items") ?: JSONArray()
            val keptItems = JSONArray()
            for (j in 0 until items.length()) {
                val it = items.optJSONObject(j) ?: continue
                if (it.optString("id", "") == id) found = true else keptItems.put(it)
            }
            if (keptItems.length() > 0) {
                s.put("items", keptItems)
                kept.put(s)
            }
        }
        if (!found) return null
        o.put("sections", kept)
        return o.toString()
    }

    /**
     * Até [maxLines] linhas (cabeçalhos + itens). Um cabeçalho nunca fica sozinho no fim; [ShopLines.hidden]
     * conta os itens que não couberam (para o "+N").
     */
    fun lines(shop: Shop, maxLines: Int): ShopLines {
        val all = ArrayList<ShopLine>()
        for (s in shop.sections) {
            all.add(ShopLine.Header(s.label))
            for (i in s.items) all.add(ShopLine.Item(i.id, i.name, i.quantity))
        }
        val total = count(shop)
        if (all.size <= maxLines) return ShopLines(all, 0)
        val shown = ArrayList(all.take(maxLines))
        if (shown.lastOrNull() is ShopLine.Header) shown.removeAt(shown.size - 1)
        return ShopLines(shown, total - shown.count { it is ShopLine.Item })
    }

    /** Linhas que cabem na altura (dp): título, "+N" e padding ocupam [fixedDp]. Desconhecida (<= 0) -> 8. */
    fun maxLines(heightDp: Int, cap: Int = 12, fixedDp: Int = 66, rowDp: Int = 22): Int {
        if (heightDp <= 0) return minOf(8, cap)
        return ((heightDp - fixedDp) / rowDp).coerceIn(3, cap)
    }

    // ---- Link do toque (mesma forma que widget_shop_action.dart) ------------

    fun checkUri(itemId: String): String = "organizacional://mercado/check?id=$itemId"

    fun itemIdFromUri(uri: String?): String? {
        if (uri == null) return null
        return try {
            val u = URI(uri)
            if (u.scheme != "organizacional" || u.host != "mercado" || u.path != "/check") return null
            u.rawQuery?.split("&")?.firstOrNull { it.startsWith("id=") }?.removePrefix("id=")?.ifEmpty { null }
        } catch (_: Exception) {
            null
        }
    }
}
