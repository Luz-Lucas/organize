package dev.organizacional.organizacional.widgets

import android.text.SpannableString
import android.text.Spanned
import android.text.style.ForegroundColorSpan

/** Título do evento para o widget: com etiqueta, leva na frente um ponto na cor dela. */
internal fun taggedTitle(e: WidgetEvent): CharSequence {
    val color = e.tagColor ?: return e.title
    val text = SpannableString(WidgetData.titleWithDot(e))
    text.setSpan(ForegroundColorSpan(color), 0, WidgetData.TAG_DOT.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
    return text
}
