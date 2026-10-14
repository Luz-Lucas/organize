package dev.organizacional.organizacional

import android.view.MotionEvent
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class StylusInputTest {
    @Test fun requestsUnbufferedOnStylusDown() {
        assertTrue(StylusInput.shouldRequestUnbuffered(MotionEvent.ACTION_DOWN, MotionEvent.TOOL_TYPE_STYLUS))
    }

    @Test fun requestsUnbufferedOnEraserEndDown() {
        assertTrue(StylusInput.shouldRequestUnbuffered(MotionEvent.ACTION_DOWN, MotionEvent.TOOL_TYPE_ERASER))
    }

    @Test fun ignoresFingerAndMouse() {
        assertFalse(StylusInput.shouldRequestUnbuffered(MotionEvent.ACTION_DOWN, MotionEvent.TOOL_TYPE_FINGER))
        assertFalse(StylusInput.shouldRequestUnbuffered(MotionEvent.ACTION_DOWN, MotionEvent.TOOL_TYPE_MOUSE))
        assertFalse(StylusInput.shouldRequestUnbuffered(MotionEvent.ACTION_DOWN, MotionEvent.TOOL_TYPE_UNKNOWN))
    }

    @Test fun onlyTheDownStartsTheGesture() {
        // O pedido vale para o gesto inteiro a partir do DOWN; os demais eventos não repetem.
        assertFalse(StylusInput.shouldRequestUnbuffered(MotionEvent.ACTION_MOVE, MotionEvent.TOOL_TYPE_STYLUS))
        assertFalse(StylusInput.shouldRequestUnbuffered(MotionEvent.ACTION_UP, MotionEvent.TOOL_TYPE_STYLUS))
        assertFalse(StylusInput.shouldRequestUnbuffered(MotionEvent.ACTION_CANCEL, MotionEvent.TOOL_TYPE_STYLUS))
        assertFalse(StylusInput.shouldRequestUnbuffered(MotionEvent.ACTION_POINTER_DOWN, MotionEvent.TOOL_TYPE_STYLUS))
    }
}
