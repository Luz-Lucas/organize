package dev.organizacional.organizacional

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.nio.file.Files

class DriveCacheGuardTest {
    @get:Rule val tmp = TemporaryFolder()

    private fun root(): File = File(tmp.root, "files/drive_cache").apply { mkdirs() }

    private fun file(root: File, rel: String, text: String = "x"): File =
        File(root, rel).apply { parentFile?.mkdirs(); writeText(text) }

    /** Cria um link simbólico; null se o sistema de arquivos não suporta (o teste então não verifica nada). */
    private fun link(at: File, to: File): File? = try {
        at.parentFile?.mkdirs()
        Files.createSymbolicLink(at.toPath(), to.toPath())
        at
    } catch (e: Exception) {
        null
    }

    @Test fun fileInsideTheRootIsAccepted() {
        val root = root()
        assertTrue(DriveCacheGuard.isOpenable(root, file(root, "F1/Aula.pdf")))
        assertTrue(DriveCacheGuard.isInside(root, file(root, "F1/Aula.pdf")))
    }

    @Test fun parentTraversalIsRefused() {
        val root = root()
        File(tmp.root, "files/segredo.db").writeText("x")
        assertFalse(DriveCacheGuard.isInside(root, File(root, "../segredo.db")))
        assertFalse(DriveCacheGuard.isInside(root, File(root, "F1/../../segredo.db")))
        assertFalse(DriveCacheGuard.isOpenable(root, File(root, "../segredo.db")))
    }

    @Test fun siblingFolderWithTheSamePrefixIsRefused() {
        val root = root()
        val evil = file(File(tmp.root, "files"), "drive_cache_evil/F1/Aula.pdf")
        assertFalse(DriveCacheGuard.isInside(root, evil))
    }

    @Test fun theRootItselfIsRefused() {
        val root = root()
        assertFalse(DriveCacheGuard.isInside(root, root))
        assertFalse(DriveCacheGuard.isOpenable(root, root))
    }

    @Test fun symlinkPointingOutsideIsRefused() {
        val root = root()
        val outside = File(tmp.root, "privado.txt").apply { writeText("x") }
        val l = link(File(root, "F1/atalho.pdf"), outside) ?: return
        assertFalse(DriveCacheGuard.isInside(root, l))
        assertFalse(DriveCacheGuard.isOpenable(root, l))
    }

    @Test fun symlinkPointingInsideTheRootIsAlsoRefused() {
        val root = root()
        val real = file(root, "F1/real.pdf")
        val l = link(File(root, "F2/atalho.pdf"), real) ?: return
        assertFalse(DriveCacheGuard.isOpenable(root, l))
    }

    @Test fun fileUnderASymlinkedFolderIsRefused() {
        val root = root()
        val outsideDir = File(tmp.root, "pasta_fora").apply { mkdirs() }
        File(outsideDir, "Aula.pdf").writeText("x")
        link(File(root, "F1"), outsideDir) ?: return
        assertFalse(DriveCacheGuard.isOpenable(root, File(root, "F1/Aula.pdf")))
    }

    @Test fun rootReachedThroughASymlinkStillWorks() {
        val root = root()
        file(root, "F1/Aula.pdf")
        val viaLink = link(File(tmp.root, "atalho_raiz"), root) ?: return
        assertTrue(DriveCacheGuard.isOpenable(viaLink, File(viaLink, "F1/Aula.pdf")))
    }

    @Test fun fileMustExistAndNotBeADirectory() {
        val root = root()
        assertFalse(DriveCacheGuard.isOpenable(root, File(root, "F1/nao-existe.pdf")))
        assertFalse(DriveCacheGuard.isOpenable(root, File(root, "F1/pasta.pdf").apply { mkdirs() }))
    }

    @Test fun anyFileTypeIsOpenable() {
        val root = root()
        assertTrue(DriveCacheGuard.isOpenable(root, file(root, "F1/Aula.sdocx")))
        assertTrue(DriveCacheGuard.isOpenable(root, file(root, "F2/Trabalho.docx")))
        assertTrue(DriveCacheGuard.isOpenable(root, file(root, "F3/sem_extensao")))
    }

    @Test fun mimeKeepsSpecificTypesAndFallsBackToOpaqueBinary() {
        assertEquals("application/pdf", DriveCacheGuard.safeMime("application/pdf"))
        assertEquals("application/pdf", DriveCacheGuard.safeMime(" Application/PDF "))
        assertEquals("image/svg+xml", DriveCacheGuard.safeMime("image/svg+xml"))
        for (bad in listOf(null, "", "   ", "*/*", "text/*", "texto solto", "a/b\r\nX: y", "application/pdf; x=y", "/pdf", "application/")) {
            assertEquals("application/octet-stream", DriveCacheGuard.safeMime(bad))
        }
    }

    @Test fun authorityDerivesFromThePackageAndStaysInsideIt() {
        val a = DriveCacheGuard.authority("dev.organizacional.organizacional")
        assertEquals("dev.organizacional.organizacional.drive_files", a)
        // O ShareGuard recusa essa autoridade vinda de fora: ninguém consegue apontar o app para ela.
        assertFalse(ShareGuard.isAcceptableUri("content", a, "dev.organizacional.organizacional"))
    }

    @Test fun theCacheFolderNameMatchesTheOneTheDartSideUses() {
        assertEquals("drive_cache", DriveCacheGuard.DIR)
    }
}
