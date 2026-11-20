package com.briskers.briskers_app

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract as DC
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.InputStream
import java.security.MessageDigest

/** Stream originals and folder snapshots through Android's persisted folder grant.
 * No broad storage permission, network, deletion, or live database access. */
class BriskersBackupBridge(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "com.briskers/backup")
    private var pending: MethodChannel.Result? = null
    private val requestCode = 7450
    private val resolver get() = activity.contentResolver
    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method == "pickFolder") {
                if (pending != null) { result.error("busy", "Folder picker is open", null) }
                else {
                    pending = result
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).addFlags(
                        Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                        Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
                    activity.startActivityForResult(intent, requestCode)
                }
            } else {
                Thread {
                    try {
                        val answer: Any? = when(call.method) {
                            "copyOriginal" -> {
                                val uri = Uri.parse(call.argument<String>("uri")!!)
                                require(uri.scheme == "content")
                                val target = ownedFile(call.argument<String>("destination")!!)
                                target.parentFile!!.mkdirs()
                                resolver.openInputStream(uri)!!.use { input -> target.outputStream().use { input.copyTo(it) } }
                                null
                            }
                            "copyApk" -> {
                                val target = ownedFile(call.argument<String>("destination")!!)
                                target.parentFile!!.mkdirs()
                                require(activity.applicationInfo.splitSourceDirs.isNullOrEmpty()) { "Split APK requires its matching installer" }
                                File(activity.applicationInfo.sourceDir).copyTo(target, overwrite = false)
                                null
                            }
                            "exportFolder" -> {
                                val tree = Uri.parse(call.argument<String>("tree")!!)
                                val source = ownedFile(call.argument<String>("source")!!)
                                val name = safeName(call.argument<String>("name")!!)
                                val root = DC.buildDocumentUriUsingTree(tree, DC.getTreeDocumentId(tree))
                                val briskers = directory(root, "Briskers_Backup")
                                val backups = directory(briskers, "Backups")
                                require(children(backups).none { it.name == name }) { "Backup already exists" }
                                val destination = DC.createDocument(resolver, backups, DC.Document.MIME_TYPE_DIR, name)!!
                                export(source, destination)
                                destination.toString()
                            }
                            "importFolder" -> {
                                val tree = Uri.parse(call.argument<String>("tree")!!)
                                val source = DC.buildDocumentUriUsingTree(tree, DC.getTreeDocumentId(tree))
                                val target = ownedFile(call.argument<String>("destination")!!)
                                require(!target.exists()) { "Restore staging already exists" }
                                var remaining = 100000
                                fun copyFolder(uri: Uri, folder: File, depth: Int) {
                                    require(depth < 32) { "Backup folders too deep" }
                                    require(folder.mkdirs()) { "Cannot create restore folder" }
                                    for (child in children(uri)) {
                                        require(--remaining >= 0) { "Too many backup files" }
                                        val file = File(folder, safeName(child.name))
                                        require(!file.exists()) { "Duplicate backup filename" }
                                        if (child.directory) copyFolder(child.uri, file, depth + 1)
                                        else resolver.openInputStream(child.uri)!!.use { input ->
                                            file.outputStream().use { output -> input.copyTo(output) }
                                        }
                                    }
                                }
                                copyFolder(source, target, 0)
                                null
                            }
                            else -> throw IllegalArgumentException("Unknown backup operation")
                        }
                        activity.runOnUiThread { result.success(answer) }
                    } catch (error: Exception) {
                        activity.runOnUiThread { result.error("backup_failed", error.message ?: "Backup operation failed", null) }
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
            val flags = data.flags and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
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
            DC.Document.COLUMN_MIME_TYPE), null, null, null)!!.use { cursor ->
            while(cursor.moveToNext()) children.add(Child(
                DC.buildDocumentUriUsingTree(tree, cursor.getString(0)), cursor.getString(1),
                cursor.getString(2) == DC.Document.MIME_TYPE_DIR))
        }
        return children
    }
    private fun directory(parent: Uri, name: String): Uri {
        val found = children(parent).singleOrNull { it.name == name }
        if (found != null) { require(found.directory); return found.uri }
        return DC.createDocument(resolver, parent, DC.Document.MIME_TYPE_DIR, name)!!
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
    private fun hash(input: InputStream): ByteArray {
        val digest = MessageDigest.getInstance("SHA-256")
        val buffer = ByteArray(128 * 1024)
        while(true) { val count = input.read(buffer); if(count < 0) break; digest.update(buffer, 0, count) }
        return digest.digest()
    }
    private fun export(source: File, target: Uri) {
        // Every payload is copied and read back before exposing the completion
        // manifest. A killed/failed copy cannot masquerade as a finished backup.
        val files = source.listFiles()!!.sortedBy { if(it.name == "backup-info.json") 1 else 0 }
        for (file in files) {
            require(!java.nio.file.Files.isSymbolicLink(file.toPath()))
            val name = safeName(file.name)
            if(file.isDirectory) {
                val child = DC.createDocument(resolver, target, DC.Document.MIME_TYPE_DIR, name)!!
                export(file, child)
            } else {
                val child = DC.createDocument(resolver, target, "application/octet-stream", name)!!
                file.inputStream().use { input -> resolver.openOutputStream(child, "w")!!.use { input.copyTo(it) } }
                val originalHash = file.inputStream().use { hash(it) }
                val copiedHash = resolver.openInputStream(child)!!.use { hash(it) }
                require(originalHash.contentEquals(copiedHash)) { "Backup copy verification failed" }
            }
        }
    }
}
