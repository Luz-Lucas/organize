package dev.organizacional.organizacional

import android.view.MotionEvent

/**
 * Decisão pura (testável em JUnit) de quando pedir entrega **sem agrupar** do input.
 *
 * O Android agrupa o input por vsync e o Flutter (AndroidTouchProcessor) ignora os pontos históricos do
 * MotionEvent: a S Pen manda 240–360 Hz, mas o app recebia ~60–120 amostras por segundo e os cantos das
 * letras (pontas do U e do C, curvas do S) saíam cortados. Com `requestUnbufferedDispatch` no DOWN o
 * sistema entrega cada amostra na hora, pelo resto do gesto.
 */
object StylusInput {
    fun shouldRequestUnbuffered(actionMasked: Int, toolType: Int): Boolean =
        actionMasked == MotionEvent.ACTION_DOWN &&
            (toolType == MotionEvent.TOOL_TYPE_STYLUS || toolType == MotionEvent.TOOL_TYPE_ERASER)
}
