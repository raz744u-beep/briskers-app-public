package com.briskers.briskers_app

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract as DC
import android.os.SystemClock
import android.system.ErrnoException
import android.system.OsConstants
import android.webkit.MimeTypeMap
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.security.DigestInputStream
import java.security.MessageDigest
import java.util.Locale
import org.json.JSONObject

/** Stream originals and folder snapshots through Android's persisted folder grant.
 * No broad storage permission, network, deletion, or live database access. */
class BriskersBackupBridge(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "com.briskers/backup")
    private var pending: MethodChannel.Result? = null
    private val requestCode = 7450
    private val resolver get() = activity.contentResolver
    private var working = false

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method in setOf("pickFolder", "pickRestoreFolder", "pickExpenseIqOriginalsFolder")) {
                if (pending != null || working) { result.error("busy", "A backup operation is already running", null) }
                else {
                    pending = result
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).addFlags(
                        Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                        Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
                    if (call.method == "pickFolder") {
                        intent.addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                    }
                    try {
                        activity.startActivityForResult(intent, requestCode)
                    } catch (error: Exception) {
                        pending = null
                        result.error("folder_permission", "Android could not open the folder picker.", null)
                    }
                }
            } else if (working || pending != null) {
                result.error("busy", "A backup operation is already running", null)
            } else {
                working = true
                Thread {
                    try {
                        val answer: Any? = when(call.method) {
                            "copyOriginal" -> {
                                val uri = Uri.parse(call.argument<String>("uri")!!)
                                require(uri.scheme == "content")
                                val target = ownedFile(call.argument<String>("destination")!!)
                                target.parentFile!!.mkdirs()
                                read(uri).use { input -> target.outputStream().use { input.copyTo(it) } }
                                null
                            }
                            "listExpenseIqOriginals" ->
                                listExpenseIqOriginals(Uri.parse(call.argument<String>("tree")!!))
                            "copyExpenseIqOriginal" -> {
                                val uri = Uri.parse(call.argument<String>("uri")!!)
                                require(uri.authority == "com.android.externalstorage.documents" &&
                                    DC.getTreeDocumentId(uri).equals("primary:ExpenseIQ/Photos", ignoreCase = true) &&
                                    DC.getDocumentId(uri).startsWith("primary:ExpenseIQ/Photos/", ignoreCase = true))
                                val target = ownedFile(call.argument<String>("destination")!!)
                                require(!target.exists())
                                val digest = MessageDigest.getInstance("SHA-256")
                                read(uri).use { original ->
                                    DigestInputStream(original, digest).use { input ->
                                        target.outputStream().use { input.copyTo(it, 128 * 1024) }
                                    }
                                }
                                digest.digest().joinToString("") { "%02x".format(it.toInt() and 0xff) }
                            }
                            "copyApk" -> {
                                val target = ownedFile(call.argument<String>("destination")!!)
                                target.parentFile!!.mkdirs()
                                if (!activity.applicationInfo.splitSourceDirs.isNullOrEmpty()) {
                                    throw UnsupportedOperationException("Split APK requires its matching installer")
                                }
                                File(activity.applicationInfo.sourceDir).copyTo(target, overwrite = false)
                                null
                            }
                            "exportFolder" -> {
                                val tree = Uri.parse(call.argument<String>("tree")!!)
                                val source = ownedFile(call.argument<String>("source")!!)
                                val name = safeName(call.argument<String>("name")!!)
                                requireFolderPermission(tree, write = true)
                                exportFolder(source, tree, name)
                            }
                            "importFolder" -> {
                                val tree = Uri.parse(call.argument<String>("tree")!!)
                                requireFolderPermission(tree, write = false)
                                val source = DC.buildDocumentUriUsingTree(tree, DC.getTreeDocumentId(tree))
                                val target = ownedFile(call.argument<String>("destination")!!)
                                require(!target.exists()) { "Restore staging already exists" }
                                require(children(source).any { it.name == "backup-info.json" && !it.directory }) {
                                    "Select one dated backup folder containing backup-info.json"
                                }
                                var remaining = 100000
                                fun copyFolder(uri: Uri, folder: File, depth: Int) {
                                    require(depth < 32) { "Backup folders too deep" }
                                    require(folder.mkdirs()) { "Cannot create restore folder" }
                                    for (child in children(uri)) {
                                        require(--remaining >= 0) { "Too many backup files" }
                                        val file = File(folder, safeName(child.name))
                                        require(!file.exists()) { "Duplicate backup filename" }
                                        if (child.directory) copyFolder(child.uri, file, depth + 1)
                                        else read(child.uri).use { input ->
                                            file.outputStream().use { output -> input.copyTo(output) }
                                        }
                                    }
                                }
                                copyFolder(source, target, 0)
                                null
                            }
                            else -> throw IllegalArgumentException("Unknown backup operation")
                        }
                        activity.runOnUiThread {
                            working = false
                            result.success(answer)
                        }
                    } catch (error: Exception) {
                        val causes = generateSequence<Throwable>(error) { it.cause }
                        val outOfSpace = causes.any {
                            (it is ErrnoException && it.errno == OsConstants.ENOSPC) ||
                                it.message.orEmpty().contains("ENOSPC", ignoreCase = true) ||
                                it.message.orEmpty().contains("No space left", ignoreCase = true)
                        }
                        val permission = causes.any { it is SecurityException }
                        val code = when {
                            outOfSpace -> "storage_full"
                            permission -> "folder_permission"
                            error is UnsupportedOperationException && call.method == "copyApk" -> "apk_unsupported"
                            else -> "backup_failed"
                        }
                        val message = when {
                            outOfSpace -> "There is not enough space on the device or in the selected folder."
                            permission -> "Android access was revoked. Select the folder again and tap Use this folder."
                            else -> error.message ?: "File transfer was interrupted."
                        }
                        activity.runOnUiThread {
                            working = false
                            result.error(code, message, null)
                        }
                    }
                }.start()
            }
        }
    }
    fun onActivityResult(request: Int, code: Int, data: Intent?): Boolean {
        if (request != requestCode) return false
        val result = pending ?: return true
        pending = null
        val uri = data?.data
        if (code != Activity.RESULT_OK || uri == null) { result.success(null); return true }
        try {
            val flags = (data?.flags ?: 0) and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            resolver.takePersistableUriPermission(uri, flags)
            result.success(uri.toString())
        } catch (error: Exception) { result.error("folder_permission", error.message, null) }
        return true
    }
    private data class Child(val uri: Uri, val name: String, val directory: Boolean)
    private fun children(parent: Uri): List<Child> {
        val tree = parent
        val id = DC.getDocumentId(parent)
        val query = DC.buildChildDocumentsUriUsingTree(tree, id)
        val children = mutableListOf<Child>()
        resolver.query(query, arrayOf(DC.Document.COLUMN_DOCUMENT_ID, DC.Document.COLUMN_DISPLAY_NAME,
            DC.Document.COLUMN_MIME_TYPE), null, null, null)?.use { cursor ->
            while(cursor.moveToNext()) children.add(Child(
                DC.buildDocumentUriUsingTree(tree, cursor.getString(0)), cursor.getString(1),
                cursor.getString(2) == DC.Document.MIME_TYPE_DIR))
        } ?: throw IOException("Cannot list the selected backup folder.")
        return children
    }
    private fun listExpenseIqOriginals(tree: Uri): List<Map<String, Any?>> {
        val rootId = DC.getTreeDocumentId(tree)
        require(tree.authority == "com.android.externalstorage.documents" &&
            rootId.equals("primary:ExpenseIQ/Photos", ignoreCase = true)) {
            "Select Internal storage / ExpenseIQ / photos"
        }
        val files = mutableListOf<Map<String, Any?>>()
        val folders = java.util.ArrayDeque<Pair<String, String>>()
        folders.add(rootId to "")
        val visited = mutableSetOf<String>()
        val extensions = setOf("jpg", "jpeg", "png", "webp", "heic", "heif", "gif", "bmp", "tif", "tiff", "avif")
        while (folders.isNotEmpty()) {
            val (id, prefix) = folders.removeFirst()
            check(visited.add(id)) { "Duplicate folder returned by Android" }
            val query = DC.buildChildDocumentsUriUsingTree(tree, id)
            val columns = arrayOf(DC.Document.COLUMN_DOCUMENT_ID, DC.Document.COLUMN_DISPLAY_NAME,
                DC.Document.COLUMN_MIME_TYPE, DC.Document.COLUMN_SIZE, DC.Document.COLUMN_LAST_MODIFIED)
            checkNotNull(resolver.query(query, columns, null, null, null)) { "Could not read the photo folder" }
                .use { cursor ->
                    while (cursor.moveToNext()) {
                        val childId = cursor.getString(0)
                        val name = safeName(cursor.getString(1))
                        val type = cursor.getString(2).orEmpty()
                        val path = if (prefix.isEmpty()) name else "$prefix/$name"
                        if (type == DC.Document.MIME_TYPE_DIR) {
                            folders.add(childId to path)
                        } else if (type.startsWith("image/") || name.substringAfterLast('.').lowercase() in extensions) {
                            files.add(mapOf(
                                "path" to path,
                                "uri" to DC.buildDocumentUriUsingTree(tree, childId).toString(),
                                "size" to if (cursor.isNull(3)) null else cursor.getLong(3),
                                "modified" to if (cursor.isNull(4)) null else cursor.getLong(4),
                            ))
                        }
                    }
                }
        }
        return files
    }
    private fun directory(parent: Uri, name: String): Uri {
        val matches = children(parent).filter { it.name == name }
        require(matches.size <= 1) { "Multiple folders named $name" }
        val found = matches.singleOrNull()
        if (found != null) {
            require(found.directory) { "$name is a file. Choose another folder." }
            return found.uri
        }
        return create(parent, DC.Document.MIME_TYPE_DIR, name)
    }
    private fun safeName(name: String): String {
        require(name.isNotEmpty() && name != "." && name != ".." && !name.contains('/') &&
            !name.contains('\\') && !name.contains(':')) { "Unsafe backup filename" }
        return name
    }
    private fun ownedFile(path: String): File {
        val file = File(path).canonicalFile
        val roots = listOf(activity.filesDir.canonicalPath, activity.cacheDir.canonicalPath,
            File(activity.applicationInfo.dataDir, "app_flutter").canonicalPath)
        require(roots.any { file.path.startsWith("$it/") }) { "File is outside app storage" }
        return file
    }
    private fun requireFolderPermission(tree: Uri, write: Boolean) {
        if (resolver.persistedUriPermissions.none {
            it.uri == tree && it.isReadPermission && (!write || it.isWritePermission)
        }) {
            throw SecurityException("Backup folder permission is unavailable")
        }
    }

    private fun create(parent: Uri, type: String, name: String): Uri =
        DC.createDocument(resolver, parent, type, name)
            ?: throw IOException("Cannot create $name in the selected folder.")

    private fun read(uri: Uri) = resolver.openInputStream(uri)
        ?: throw IOException("Android could not read a backup file.")

    private fun write(uri: Uri) = resolver.openOutputStream(uri, "w")
        ?: throw IOException("Android could not open a backup file for writing.")

    private fun exportFolder(source: File, tree: Uri, name: String): String {
        val manifestName = "backup-info.json"
        val manifest = File(source, manifestName).readBytes()
        val files = JSONObject(String(manifest, Charsets.UTF_8)).getJSONObject("files")
        val payload = files.keys().asSequence().map { path ->
            val parts = path.split('/')
            parts.forEach { safeName(it) }
            require(parts.size == 2) { "Invalid backup payload path" }
            val entry = files.getJSONObject(path)
            val length = entry.getLong("bytes")
            require(length >= 0) { "Invalid backup file length" }
            BackupPayload(path, length, entry.getString("sha256"))
        }.sortedWith(compareBy {
            when (it.path.substringBefore('/')) {
                "Database" -> 0
                "Photos", "Receipts" -> 1
                "App" -> 3
                else -> 2
            }
        }).toList()

        val root = DC.buildDocumentUriUsingTree(tree, DC.getTreeDocumentId(tree))
        val backups = directory(directory(root, "Briskers_Backup"), "Backups")
        require(children(backups).none { it.name == name }) { "Backup already exists" }
        val destination = create(backups, DC.Document.MIME_TYPE_DIR, name)
        val folders = mutableMapOf<String, Uri>()
        var currentFile: Uri? = null
        BriskersBackupTransfer(SystemClock::elapsedRealtime) { update ->
            activity.runOnUiThread { channel.invokeMethod("backupProgress", update) }
        }.export(
            source,
            payload,
            copyToDestination = { path, copy ->
                val area = path.substringBefore('/')
                val parent = folders.getOrPut(area) {
                    create(destination, DC.Document.MIME_TYPE_DIR, area)
                }
                val filename = path.substringAfter('/')
                val extension = filename.substringAfterLast('.', "").lowercase(Locale.ROOT)
                val mime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension)
                    ?: "application/octet-stream"
                val uri = create(parent, mime, filename)
                currentFile = uri
                write(uri).use(copy)
            },
            openDestination = { read(checkNotNull(currentFile)) },
        )

        // Providers may change display names on create. Verify the actual
        // directory layout before exposing the completion marker.
        val layout = payload.groupBy { it.path.substringBefore('/') }
        val actualFolders = children(destination).associate { it.name to DC.getDocumentId(it.uri) }
        require(actualFolders == folders.mapValues { DC.getDocumentId(it.value) }) {
            "Android changed the backup folder layout."
        }
        for ((area, entries) in layout) {
            val actual = children(folders.getValue(area)).filterNot { it.directory }.map { it.name }.sorted()
            require(actual == entries.map { it.path.substringAfter('/') }.sorted()) {
                "Android changed one or more backup filenames in $area."
            }
        }

        val staged = create(destination, "application/json", "backup-info-pending.json")
        write(staged).use { it.write(manifest) }
        val sha = MessageDigest.getInstance("SHA-256").digest(manifest)
            .joinToString("") { "%02x".format(it) }
        BriskersBackupTransfer.verify(
            read(staged),
            BackupPayload(manifestName, manifest.size.toLong(), sha),
        )
        val published = DC.renameDocument(resolver, staged, manifestName)
            ?: throw IOException("Android could not finish the backup manifest. Select another folder.")
        require(children(destination).any {
            it.name == manifestName && DC.getDocumentId(it.uri) == DC.getDocumentId(published)
        }) {
            "Android changed the backup manifest filename. Select another folder."
        }
        return destination.toString()
    }
}
