package com.briskers.briskers_app

import java.io.File
import java.io.FilterOutputStream
import java.io.IOException
import java.nio.file.Files
import java.security.MessageDigest

private fun sha(bytes: ByteArray): String =
    MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }

fun main() {
    val root = Files.createTempDirectory("briskers-transfer-test").toFile()
    try {
        val source = File(root, "source").apply { mkdir() }
        fun fixture(path: String, bytes: ByteArray): BackupPayload {
            val file = File(source, path)
            file.parentFile.mkdirs()
            file.writeBytes(bytes)
            return BackupPayload(path, bytes.size.toLong(), sha(bytes))
        }

        val database = fixture("Database/shop.sqlite", ByteArray(5 * 1024 * 1024) { it.toByte() })
        val document = fixture("Documents/invoice.pdf", byteArrayOf(1, 2, 3))
        val photos = (1..5_000).map { fixture("Photos/$it.jpg", byteArrayOf(it.toByte())) }
        val payload = listOf(database) + photos + document
        val previous = File(root, "earlier-backup").apply { writeText("unchanged") }

        fun transfer(
            name: String,
            entries: List<BackupPayload>,
            change: (File) -> Unit = {},
            beforeWrite: (String) -> Unit = {},
            interruptWrite: Boolean = false,
        ): List<Map<String, Any>> {
            val target = File(root, name).apply { check(mkdir()) }
            var time = 0L
            val updates = mutableListOf<Map<String, Any>>()
            BriskersBackupTransfer(clock = { time += 100L; time }, report = { updates += it }).export(
                source,
                entries,
                copyToDestination = { path, write ->
                    beforeWrite(path)
                    val file = File(target, path)
                    file.parentFile.mkdirs()
                    file.outputStream().use { output ->
                        if (interruptWrite) {
                            write(object : FilterOutputStream(output) {
                                override fun write(bytes: ByteArray, offset: Int, length: Int) {
                                    out.write(bytes, offset, length / 2)
                                    throw IOException("Interrupted during a file")
                                }
                            })
                        } else {
                            write(output)
                        }
                    }
                    change(file)
                },
                openDestination = { File(target, it).inputStream() },
            )
            return updates
        }

        val events = transfer("large-copy", payload)
        val completed = events.last()
        check(completed["copied"] == 5002 && completed["total"] == 5002)
        check(completed["bytes"] == payload.sumOf { it.bytes })
        check(completed["bytes"] == completed["checked"] && completed["bytes"] == completed["verified"])
        check(events.any { it["copied"] == 0 && (it.getValue("bytes") as Long) in 1 until database.bytes })
        check(events.any { it["operation"] == "Verification" && it["verified"] == 0L &&
            (it.getValue("checked") as Long) in 1 until database.bytes })
        check(events.size < 8_000) { "Progress events were not throttled" }
        for (field in listOf("copied", "bytes", "checked", "verified")) {
            check(events.zipWithNext().all { (a, b) ->
                (a.getValue(field) as Number).toLong() <= (b.getValue(field) as Number).toLong()
            })
        }

        val interrupted = runCatching {
            transfer("interrupted", payload, interruptWrite = true)
        }.exceptionOrNull()
        check(interrupted is IOException)
        check(File(root, "interrupted/${database.path}").length() in 1 until database.bytes)
        check(transfer("retry", listOf(database, document)).last()["copied"] == 2)
        check(previous.readText() == "unchanged")

        val badHash = runCatching {
            transfer("corrupt", listOf(document), change = { it.writeBytes(byteArrayOf(1, 2, 4)) })
        }.exceptionOrNull()
        check(badHash is IOException && badHash.message!!.contains("verification failed"))

        val revoked = runCatching {
            transfer("revoked", listOf(document), beforeWrite = { throw SecurityException("Revoked") })
        }.exceptionOrNull()
        check(revoked is SecurityException)
        check(File(source, document.path).delete())
        val missing = runCatching { transfer("missing", listOf(document)) }.exceptionOrNull()
        check(missing is IOException && missing.message!!.contains("Missing backup file"))
        Files.createSymbolicLink(File(source, document.path).toPath(), previous.toPath())
        val symlink = runCatching { transfer("symlink", listOf(document)) }.exceptionOrNull()
        check(symlink is IOException && symlink.message!!.contains("Invalid backup source path"))
        println("5,002 files, large-file progress, retry, permissions, corruption and missing-file checks passed")
    } finally {
        root.deleteRecursively()
    }
}
