package com.briskers.briskers_app

import java.io.File
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.security.MessageDigest

internal data class BackupPayload(val path: String, val bytes: Long, val sha256: String)

internal class BriskersBackupTransfer(
    private val clock: () -> Long,
    private val report: (Map<String, Any>) -> Unit,
) {
    fun export(
        source: File,
        payload: List<BackupPayload>,
        copyToDestination: (String, (OutputStream) -> Unit) -> Unit,
        openDestination: (String) -> InputStream,
    ) {
        val totalBytes = payload.sumOf { it.bytes }
        var lastProgressAt = 0L
        var copied = 0
        var transferred = 0L
        var checked = 0L
        var verified = 0L

        fun progress(operation: String, force: Boolean = false) {
            val now = clock()
            if (!force && now - lastProgressAt < 200L) return
            lastProgressAt = now
            report(mapOf(
                "operation" to operation, "copied" to copied, "total" to payload.size,
                "bytes" to transferred, "checked" to checked, "verified" to verified,
                "totalBytes" to totalBytes,
            ))
        }

        progress("Database", force = true)
        val buffer = ByteArray(128 * 1024)
        for (entry in payload) {
            val original = File(source, entry.path)
            if (!original.isFile || java.nio.file.Files.isSymbolicLink(original.toPath())) {
                throw IOException("Missing backup file: ${entry.path}")
            }
            val operation = when (entry.path.substringBefore('/')) {
                "Database" -> "Database"
                "App" -> "APK"
                "Photos", "Receipts" -> "Photos"
                else -> "Documents"
            }
            var size = 0L
            copyToDestination(entry.path) { output ->
                original.inputStream().use { input ->
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        size += count
                        if (size > entry.bytes) throw IOException("Backup source changed: ${entry.path}")
                        output.write(buffer, 0, count)
                        transferred += count
                        progress(operation)
                    }
                }
            }
            if (size != entry.bytes) throw IOException("Backup source changed: ${entry.path}")
            copied++
            progress("Verification")
            verify(openDestination(entry.path), entry, buffer) { count ->
                checked += count
                progress("Verification")
            }
            verified += entry.bytes
        }
        progress("Verification", force = true)
    }

    companion object {
        fun verify(
            input: InputStream,
            entry: BackupPayload,
            buffer: ByteArray = ByteArray(128 * 1024),
            onRead: (Int) -> Unit = {},
        ) {
            val digest = MessageDigest.getInstance("SHA-256")
            var bytes = 0L
            input.use {
                while (true) {
                    val count = it.read(buffer)
                    if (count < 0) break
                    bytes += count
                    if (bytes > entry.bytes) throw IOException("Backup copy verification failed: ${entry.path}")
                    digest.update(buffer, 0, count)
                    onRead(count)
                }
            }
            val hash = digest.digest().joinToString("") { "%02x".format(it) }
            if (bytes != entry.bytes || hash != entry.sha256) {
                throw IOException("Backup copy verification failed: ${entry.path}")
            }
        }
    }
}
