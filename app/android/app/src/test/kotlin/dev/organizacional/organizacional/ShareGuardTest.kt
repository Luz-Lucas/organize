package dev.organizacional.organizacional

import android.content.Intent
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.InputStream

class ShareGuardTest {
    private val pkg = "dev.organizacional.organizacional"

    // --- só content:// de outro app ---------------------------------------------------------

    @Test fun acceptsContentFromAnotherApp() {
        assertTrue(ShareGuard.isAcceptableUri("content", "com.samsung.android.app.notes.fileprovider", pkg))
        assertTrue(ShareGuard.isAcceptableUri("CONTENT", "media", pkg))
        assertTrue(ShareGuard.isAcceptableUri("content", "com.android.providers.media.documents", pkg))
    }

    @Test fun rejectsOtherSchemes() {
        assertFalse(ShareGuard.isAcceptableUri("file", "", pkg))
        assertFalse(ShareGuard.isAcceptableUri("file", "algo", pkg))
        assertFalse(ShareGuard.isAcceptableUri("http", "example.com", pkg))
        assertFalse(ShareGuard.isAcceptableUri("https", "example.com", pkg))
        assertFalse(ShareGuard.isAcceptableUri("android.resource", pkg, pkg))
        assertFalse(ShareGuard.isAcceptableUri(null, "x", pkg))
    }

    @Test fun rejectsBlankAuthority() {
        assertFalse(ShareGuard.isAcceptableUri("content", null, pkg))
        assertFalse(ShareGuard.isAcceptableUri("content", "  ", pkg))
    }

    @Test fun rejectsOwnPackageAuthoritiesIncludingOwnFileProvider() {
        assertFalse(ShareGuard.isAcceptableUri("content", pkg, pkg))
        assertFalse(ShareGuard.isAcceptableUri("content", "$pkg.fileprovider", pkg))
        assertFalse(ShareGuard.isAcceptableUri("content", "$pkg.flutter.share_provider", pkg))
        assertFalse(ShareGuard.isAcceptableUri("content", pkg.uppercase(), pkg))
    }

    @Test fun rejectsOwnAuthorityHiddenBehindUserIdPrefix() {
        // content://<userId>@authority é o formato multiusuário do Android: mesmo provider.
        assertFalse(ShareGuard.isAcceptableUri("content", "10@$pkg.fileprovider", pkg))
        assertFalse(ShareGuard.isAcceptableUri("content", "0@$pkg", pkg))
    }

    @Test fun ownPackageAsMereSubstringOfAnotherAuthorityIsFine() {
        assertTrue(ShareGuard.isAcceptableUri("content", "outro.app.$pkg", pkg))
        assertTrue(ShareGuard.isAcceptableUri("content", "${pkg}x", pkg))
    }

    // --- teto de 100 MB na cópia ------------------------------------------------------------

    @Test fun copiesWithinTheLimit() {
        val data = ByteArray(5000) { it.toByte() }
        val out = ByteArrayOutputStream()
        assertTrue(ShareGuard.copyLimited(ByteArrayInputStream(data), out, 5000))
        assertEquals(5000, out.size())
    }

    @Test fun stopsAndReportsFailureWhenOverTheLimit() {
        val out = ByteArrayOutputStream()
        // 10 000 bytes, teto de 4 096: tem de parar sem ler tudo.
        val src = CountingStream(10_000)
        assertFalse(ShareGuard.copyLimited(src, out, 4096, bufferSize = 1024))
        assertTrue("copiou além do teto: ${out.size()}", out.size() <= 4096 + 1024)
        assertTrue("leu o arquivo inteiro: ${src.read}", src.read < 10_000)
    }

    @Test fun exactlyAtTheLimitStillCopies() {
        val out = ByteArrayOutputStream()
        assertTrue(ShareGuard.copyLimited(ByteArrayInputStream(ByteArray(4096)), out, 4096, bufferSize = 1024))
        assertEquals(4096, out.size())
    }

    @Test fun defaultLimitIs100MiB() {
        assertEquals(100L * 1024 * 1024, ShareGuard.MAX_FILE_BYTES)
    }

    // --- mime com * deduzido pela extensão --------------------------------------------------

    private val table = mapOf("pdf" to "application/pdf", "png" to "image/png", "txt" to "text/plain")
    private val lookup: (String) -> String? = { table[it] }

    @Test fun keepsConcreteMime() {
        assertEquals("image/jpeg", ShareGuard.resolveMime("image/jpeg", "image/*", "foto.pdf", lookup))
    }

    @Test fun wildcardReportedFallsBackToConcreteFallback() {
        assertEquals("image/png", ShareGuard.resolveMime("*/*", "image/png", "x", lookup))
    }

    @Test fun wildcardEverywhereIsDeducedFromTheExtension() {
        assertEquals("application/pdf", ShareGuard.resolveMime("*/*", "application/*", "Edital.PDF", lookup))
        assertEquals("image/png", ShareGuard.resolveMime(null, "image/*", "a.b.png", lookup))
    }

    @Test fun unknownExtensionWithWildcardGivesNull() {
        assertNull(ShareGuard.resolveMime("*/*", "*/*", "arquivo.xyz", lookup))
        assertNull(ShareGuard.resolveMime(null, null, "semextensao", lookup))
    }

    @Test fun nullMimesWithKnownExtensionAreDeduced() {
        assertEquals("text/plain", ShareGuard.resolveMime(null, null, "notas.txt", lookup))
    }

    // --- intent reaberto pelo histórico -----------------------------------------------------

    @Test fun ignoresIntentLaunchedFromHistory() {
        assertTrue(ShareGuard.launchedFromHistory(Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY))
        assertTrue(ShareGuard.launchedFromHistory(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY))
        assertFalse(ShareGuard.launchedFromHistory(Intent.FLAG_ACTIVITY_NEW_TASK))
        assertFalse(ShareGuard.launchedFromHistory(0))
    }

    private class CountingStream(private val total: Int) : InputStream() {
        var read = 0
        override fun read(): Int = if (read >= total) -1 else { read++; 1 }
        override fun read(b: ByteArray, off: Int, len: Int): Int {
            if (read >= total) return -1
            val n = minOf(len, total - read)
            read += n
            return n
        }
    }
}
