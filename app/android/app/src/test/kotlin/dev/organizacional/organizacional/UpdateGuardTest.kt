package dev.organizacional.organizacional

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.nio.file.Files

class UpdateGuardTest {
    @get:Rule val tmp = TemporaryFolder()

    private fun root(): File = File(tmp.root, "cache/updates").apply { mkdirs() }

    private fun file(root: File, rel: String, text: String = "x"): File =
        File(root, rel).apply { parentFile?.mkdirs(); writeText(text) }

    private fun link(at: File, to: File): File? = try {
        at.parentFile?.mkdirs()
        Files.createSymbolicLink(at.toPath(), to.toPath())
        at
    } catch (e: Exception) {
        null
    }

    @Test fun apkInsideTheUpdatesFolderIsInstallable() {
        val root = root()
        assertTrue(UpdateGuard.isInstallable(root, file(root, "organizacional-1.1.0+5.apk")))
        assertTrue(UpdateGuard.isInstallable(root, file(root, "MAIUSCULO.APK")))
    }

    @Test fun onlyApkFilesAreInstallable() {
        val root = root()
        assertFalse(UpdateGuard.isInstallable(root, file(root, "dados.db")))
        assertFalse(UpdateGuard.isInstallable(root, file(root, "pacote.tar.gz")))
        assertFalse(UpdateGuard.isInstallable(root, file(root, "apk")))
        assertFalse(UpdateGuard.isInstallable(root, file(root, "a.apk.txt")))
    }

    @Test fun parentTraversalIsRefused() {
        val root = root()
        File(tmp.root, "cache/fora.apk").writeText("x")
        assertFalse(UpdateGuard.isInstallable(root, File(root, "../fora.apk")))
        assertFalse(UpdateGuard.isInstallable(root, File(root, "sub/../../fora.apk")))
    }

    @Test fun otherAppFoldersAreRefused() {
        val root = root()
        val driveCache = file(File(tmp.root, "files"), "drive_cache/F1/x.apk")
        val sibling = file(File(tmp.root, "cache"), "updates_evil/x.apk")
        assertFalse(UpdateGuard.isInstallable(root, driveCache))
        assertFalse(UpdateGuard.isInstallable(root, sibling))
    }

    @Test fun theRootAndFoldersAreRefused() {
        val root = root()
        assertFalse(UpdateGuard.isInstallable(root, root))
        val dir = File(root, "pasta.apk").apply { mkdirs() }
        assertFalse(UpdateGuard.isInstallable(root, dir))
    }

    @Test fun missingFileIsRefused() {
        assertFalse(UpdateGuard.isInstallable(root(), File(root(), "nao-existe.apk")))
    }

    @Test fun symlinkPointingOutsideIsRefused() {
        val root = root()
        val outside = File(tmp.root, "privado.apk").apply { writeText("x") }
        val l = link(File(root, "atalho.apk"), outside) ?: return
        assertFalse(UpdateGuard.isInstallable(root, l))
    }

    @Test fun symlinkedFolderIsRefused() {
        val root = root()
        val outsideDir = File(tmp.root, "externo").apply { mkdirs() }
        File(outsideDir, "x.apk").writeText("x")
        link(File(root, "pasta"), outsideDir) ?: return
        assertFalse(UpdateGuard.isInstallable(root, File(root, "pasta/x.apk")))
    }

    @Test fun mimeIsTheApkType() {
        assertEquals("application/vnd.android.package-archive", UpdateGuard.APK_MIME)
    }
}
