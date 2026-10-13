package dev.organizacional.organizacional

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

class SamsungFoldersTest {
    @get:Rule val tmp = TemporaryFolder()

    private fun dir(vararg parts: String): File = File(tmp.root, parts.joinToString("/")).apply { mkdirs() }

    private fun names(found: List<File>): List<String> = found.map { it.relativeTo(tmp.root).path }

    @Test fun emptyStorageFindsNothing() {
        assertTrue(SamsungFolders.find(tmp.root).isEmpty())
    }

    @Test fun missingRootFindsNothing() {
        assertTrue(SamsungFolders.find(File(tmp.root, "nao-existe")).isEmpty())
    }

    @Test fun fixedCandidatesComeInTheAgreedOrder() {
        // criados fora de ordem de propósito
        dir("Download")
        dir("Documents", "Samsung")
        dir("Samsung Notes")
        dir("Download", "Samsung Notes")
        dir("Documents", "Samsung Notes")
        assertEquals(
            listOf("Documents/Samsung Notes", "Download/Samsung Notes", "Samsung Notes", "Documents/Samsung", "Download"),
            names(SamsungFolders.find(tmp.root)),
        )
    }

    @Test fun onlyExistingCandidatesAreReturned() {
        dir("Download")
        dir("Documents", "Samsung Notes")
        assertEquals(listOf("Documents/Samsung Notes", "Download"), names(SamsungFolders.find(tmp.root)))
    }

    @Test fun plainFilesWithCandidateNamesAreIgnored() {
        File(tmp.root, "Samsung Notes").writeText("nao sou pasta")
        File(tmp.root, "Download").writeText("nem eu")
        assertTrue(SamsungFolders.find(tmp.root).isEmpty())
    }

    @Test fun searchesByNameUpToDepthThree() {
        dir("a", "b", "Samsung Notes")          // profundidade 3: achada
        dir("a", "b", "c", "Samsung Notes")     // profundidade 4: fora do limite
        assertEquals(listOf("a/b/Samsung Notes"), names(SamsungFolders.find(tmp.root)))
    }

    @Test fun searchMatchesTheNameIgnoringCase() {
        dir("x", "samsung notes")
        assertEquals(listOf("x/samsung notes"), names(SamsungFolders.find(tmp.root)))
    }

    @Test fun deepMatchesComeAfterTheFixedOnesAndShallowerFirst() {
        dir("Download")
        dir("z", "Samsung Notes")
        dir("a", "b", "Samsung Notes")
        assertEquals(listOf("Download", "z/Samsung Notes", "a/b/Samsung Notes"), names(SamsungFolders.find(tmp.root)))
    }

    @Test fun aFixedCandidateIsNotListedTwice() {
        dir("Documents", "Samsung Notes")
        dir("Samsung Notes")
        val found = names(SamsungFolders.find(tmp.root))
        assertEquals(listOf("Documents/Samsung Notes", "Samsung Notes"), found)
    }

    @Test fun skipsAndroidDataAndHiddenFolders() {
        dir("Android", "data", "Samsung Notes")
        dir(".cache", "Samsung Notes")
        dir("Android", "Samsung Notes")
        assertTrue(SamsungFolders.find(tmp.root).isEmpty())
    }

    @Test fun packageNameIsTheSamsungNotesApp() {
        assertEquals("com.samsung.android.app.notes", SamsungFolders.PACKAGE)
    }

    @Test fun treeUriLabelUsesTheLastPathSegment() {
        assertEquals("Samsung Notes", SamsungFolders.labelFromDocumentId("primary:Documents/Samsung Notes"))
        assertEquals("Notas", SamsungFolders.labelFromDocumentId("1A2B-3C4D:Notas"))
        assertEquals("Armazenamento interno", SamsungFolders.labelFromDocumentId("primary:"))
        assertEquals("pasta", SamsungFolders.labelFromDocumentId(""))
    }
}
