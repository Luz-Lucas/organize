package dev.organizacional.organizacional

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

class SamsungOpenGuardTest {
    @get:Rule val tmp = TemporaryFolder()

    private fun root(): File = File(tmp.root, "cache/samsung_open").apply { mkdirs() }

    @Test fun fileInsideTheRootIsAccepted() {
        val root = root()
        val f = File(root, "Aula.sdocx").apply { writeText("x") }
        assertTrue(SamsungOpenGuard.isInside(root, f))
    }

    @Test fun nestedFileInsideTheRootIsAccepted() {
        val root = root()
        val f = File(root, "sub/Aula.sdocx").apply { parentFile.mkdirs(); writeText("x") }
        assertTrue(SamsungOpenGuard.isInside(root, f))
    }

    @Test fun parentTraversalIsRefused() {
        val root = root()
        File(tmp.root, "cache/segredo.db").writeText("x")
        assertFalse(SamsungOpenGuard.isInside(root, File(root, "../segredo.db")))
        assertFalse(SamsungOpenGuard.isInside(root, File(root, "../../cache/segredo.db")))
    }

    @Test fun siblingFolderWithTheSamePrefixIsRefused() {
        val root = root()
        val evil = File(tmp.root, "cache/samsung_open_evil/Aula.sdocx").apply { parentFile.mkdirs(); writeText("x") }
        assertFalse(SamsungOpenGuard.isInside(root, evil))
    }

    @Test fun theRootItselfIsRefused() {
        val root = root()
        assertFalse(SamsungOpenGuard.isInside(root, root))
    }

    @Test fun symlinkPointingOutsideIsRefused() {
        val root = root()
        val outside = File(tmp.root, "privado.txt").apply { writeText("x") }
        val link = File(root, "atalho.sdocx")
        try {
            java.nio.file.Files.createSymbolicLink(link.toPath(), outside.toPath())
        } catch (e: Exception) {
            return // sistema de arquivos sem symlink: nada a verificar
        }
        assertFalse(SamsungOpenGuard.isInside(root, link))
    }

    @Test fun fileMustExistAndNotBeADirectory() {
        val root = root()
        assertFalse(SamsungOpenGuard.isOpenable(root, File(root, "nao-existe.sdocx")))
        assertFalse(SamsungOpenGuard.isOpenable(root, File(root, "pasta.sdocx").apply { mkdirs() }))
        assertTrue(SamsungOpenGuard.isOpenable(root, File(root, "Aula.sdocx").apply { writeText("x") }))
    }

    @Test fun onlySdocxIsOpened() {
        val root = root()
        assertFalse(SamsungOpenGuard.isOpenable(root, File(root, "Aula.pdf").apply { writeText("x") }))
        assertTrue(SamsungOpenGuard.isOpenable(root, File(root, "Prova.SDOCX").apply { writeText("x") }))
    }

    @Test fun triesTheSamsungPackageFirstThenTheSystemChooser() {
        assertEquals(listOf<String?>("com.samsung.android.app.notes", null), SamsungOpenGuard.packageAttempts())
    }

    @Test fun authorityDerivesFromThePackageAndStaysInsideIt() {
        val a = SamsungOpenGuard.authority("dev.organizacional.organizacional")
        assertEquals("dev.organizacional.organizacional.samsung_files", a)
        // O ShareGuard recusa essa autoridade vinda de fora: ninguém consegue apontar o app para ela.
        assertFalse(ShareGuard.isAcceptableUri("content", a, "dev.organizacional.organizacional"))
    }

    @Test fun mimeIsOpaqueBinary() {
        assertEquals("application/octet-stream", SamsungOpenGuard.MIME)
        assertNull(SamsungOpenGuard.MIME.takeIf { '*' in it })
    }
}
