package com.futureatoms.sticker_officer

import android.content.ContentProvider
import android.content.ContentValues
import android.content.UriMatcher
import android.content.res.AssetFileDescriptor
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.util.Log
import java.io.File

/**
 * ContentProvider that WhatsApp queries to discover and load sticker packs.
 *
 * WhatsApp expects this provider to answer queries about:
 * - Available sticker packs (metadata)
 * - Stickers within each pack
 * - Individual sticker and tray icon files
 */
class StickerContentProvider : ContentProvider() {
    private data class PackMetadata(
        val name: String,
        val publisher: String,
        val imageDataVersion: String,
        val animatedStickerPack: Int
    )

    companion object {
        private const val TAG = "StickerOfficer"
        const val AUTHORITY = "com.futureatoms.sticker_officer.stickercontentprovider"

        // URI matching codes
        private const val STICKER_PACK_LIST = 1
        private const val STICKER_PACK = 2
        private const val STICKERS_IN_PACK = 3
        private const val STICKER_FILE = 4
        private const val STICKER_ASSET = 5

        // Column names that WhatsApp expects
        // Pack metadata columns
        const val STICKER_PACK_IDENTIFIER = "sticker_pack_identifier"
        const val STICKER_PACK_NAME = "sticker_pack_name"
        const val STICKER_PACK_PUBLISHER = "sticker_pack_publisher"
        const val STICKER_PACK_ICON = "sticker_pack_icon"
        const val ANDROID_APP_DOWNLOAD_LINK = "android_play_store_link"
        const val IOS_APP_DOWNLOAD_LINK = "ios_app_download_link"
        const val PUBLISHER_EMAIL = "sticker_pack_publisher_email"
        const val PUBLISHER_WEBSITE = "sticker_pack_publisher_website"
        const val PRIVACY_POLICY_WEBSITE = "sticker_pack_privacy_policy_website"
        const val LICENSE_AGREEMENT_WEBSITE = "sticker_pack_license_agreement_website"
        const val IMAGE_DATA_VERSION = "image_data_version"
        const val AVOID_CACHE = "whatsapp_will_not_cache_stickers"
        const val ANIMATED_STICKER_PACK = "animated_sticker_pack"

        // Sticker columns
        const val STICKER_FILE_NAME = "sticker_file_name"
        const val STICKER_FILE_EMOJI = "sticker_emoji"
        const val STICKER_FILE_ACCESSIBILITY_TEXT = "sticker_accessibility_text"

        private val uriMatcher = UriMatcher(UriMatcher.NO_MATCH).apply {
            addURI(AUTHORITY, "metadata", STICKER_PACK_LIST)
            addURI(AUTHORITY, "metadata/*", STICKER_PACK)
            addURI(AUTHORITY, "stickers/*", STICKERS_IN_PACK)
            addURI(AUTHORITY, "stickers_asset/*/tray_icon.webp", STICKER_FILE)
            addURI(AUTHORITY, "stickers_asset/*/tray_icon.png", STICKER_FILE)
            addURI(AUTHORITY, "stickers_asset/*/*", STICKER_ASSET)
        }
    }

    /**
     * Returns the stickers directory inside the app's internal files dir.
     */
    private fun getStickersDir(): File {
        val ctx = context ?: throw IllegalStateException("Context is null")
        return File(ctx.filesDir, "sticker_packs")
    }

    private fun readPackMetadata(packDir: File): PackMetadata {
        val metaFile = File(packDir, "pack_info.txt")
        if (!metaFile.exists()) {
            return PackMetadata(
                name = packDir.name,
                publisher = "StickerOfficer",
                imageDataVersion = "1",
                animatedStickerPack = 0
            )
        }

        val lines = metaFile.readLines()
        return PackMetadata(
            name = lines.getOrNull(0) ?: packDir.name,
            publisher = lines.getOrNull(1) ?: "StickerOfficer",
            imageDataVersion = lines.getOrNull(2) ?: "1",
            animatedStickerPack = if (lines.getOrNull(3) == "1") 1 else 0
        )
    }

    override fun onCreate(): Boolean = true

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?
    ): Cursor? {
        val matchCode = uriMatcher.match(uri)
        Log.d(TAG, "query() uri=$uri matchCode=$matchCode")

        return when (matchCode) {
            STICKER_PACK_LIST -> {
                val cursor = getPackListCursor()
                // Log pack validation summary when WhatsApp queries metadata
                val stickersDir = getStickersDir()
                if (stickersDir.exists()) {
                    stickersDir.listFiles()?.filter { it.isDirectory }?.forEach { packDir ->
                        val stickerFiles = packDir.listFiles()?.filter {
                            it.extension == "webp" && !it.name.startsWith("tray_icon")
                        } ?: emptyList()
                        val trayIcon = when {
                            File(packDir, "tray_icon.png").exists() -> File(packDir, "tray_icon.png")
                            File(packDir, "tray_icon.webp").exists() -> File(packDir, "tray_icon.webp")
                            else -> null
                        }
                        val trayExists = trayIcon != null
                        val traySize = trayIcon?.length() ?: 0L
                        Log.d(TAG, "Pack ${packDir.name}: ${stickerFiles.size} stickers, tray_icon exists=$trayExists (${traySize} bytes)")
                    }
                }
                cursor
            }
            STICKER_PACK -> {
                val identifier = uri.lastPathSegment ?: return null
                getPackCursor(identifier)
            }
            STICKERS_IN_PACK -> {
                val identifier = uri.lastPathSegment ?: return null
                getStickersCursor(identifier)
            }
            STICKER_FILE, STICKER_ASSET -> {
                // WhatsApp sometimes calls query() for sticker assets before openFile().
                // Return a minimal cursor so it doesn't think the asset is missing.
                val cursor = MatrixCursor(arrayOf(STICKER_FILE_NAME))
                val fileName = uri.lastPathSegment
                if (fileName != null) {
                    cursor.addRow(arrayOf(fileName))
                }
                cursor
            }
            else -> {
                Log.e(TAG, "Unmatched URI in query(): $uri")
                null
            }
        }
    }

    /**
     * Lists all available sticker packs. Each pack is a subdirectory in sticker_packs/.
     */
    private fun getPackListCursor(): Cursor {
        val cursor = MatrixCursor(arrayOf(
            STICKER_PACK_IDENTIFIER,
            STICKER_PACK_NAME,
            STICKER_PACK_PUBLISHER,
            STICKER_PACK_ICON,
            ANDROID_APP_DOWNLOAD_LINK,
            IOS_APP_DOWNLOAD_LINK,
            PUBLISHER_EMAIL,
            PUBLISHER_WEBSITE,
            PRIVACY_POLICY_WEBSITE,
            LICENSE_AGREEMENT_WEBSITE,
            IMAGE_DATA_VERSION,
            AVOID_CACHE,
            ANIMATED_STICKER_PACK
        ))

        val stickersDir = getStickersDir()
        if (!stickersDir.exists()) return cursor

        stickersDir.listFiles()?.filter { it.isDirectory }?.forEach { packDir ->
            val identifier = packDir.name
            val metadata = readPackMetadata(packDir)

            // Find the actual tray icon file (could be .webp or .png)
            val trayIconName = when {
                File(packDir, "tray_icon.png").exists() -> "tray_icon.png"
                File(packDir, "tray_icon.webp").exists() -> "tray_icon.webp"
                else -> "tray_icon.png" // fallback
            }

            cursor.addRow(arrayOf<Any?>(
                identifier,                                              // identifier
                metadata.name,                                           // name
                metadata.publisher,                                      // publisher
                trayIconName,                                            // tray icon filename
                "https://play.google.com/store/apps/details?id=com.futureatoms.sticker_officer",  // play store link
                "",                                                      // ios store link
                "",                                                      // publisher email
                "",                                                      // publisher website
                "https://www.example.com/privacy",                       // privacy policy
                "https://www.example.com/license",                       // license
                metadata.imageDataVersion,                               // image data version
                0,                                                       // avoid cache (0 = false)
                metadata.animatedStickerPack                             // animated flag
            ))
        }

        cursor.setNotificationUri(context?.contentResolver, Uri.parse("content://$AUTHORITY/metadata"))
        return cursor
    }

    private fun getPackCursor(identifier: String): Cursor? {
        val cursor = MatrixCursor(arrayOf(
            STICKER_PACK_IDENTIFIER,
            STICKER_PACK_NAME,
            STICKER_PACK_PUBLISHER,
            STICKER_PACK_ICON,
            ANDROID_APP_DOWNLOAD_LINK,
            IOS_APP_DOWNLOAD_LINK,
            PUBLISHER_EMAIL,
            PUBLISHER_WEBSITE,
            PRIVACY_POLICY_WEBSITE,
            LICENSE_AGREEMENT_WEBSITE,
            IMAGE_DATA_VERSION,
            AVOID_CACHE,
            ANIMATED_STICKER_PACK
        ))

        val packDir = File(getStickersDir(), identifier)
        if (!packDir.exists()) return cursor

        val metadata = readPackMetadata(packDir)

        val trayIconName = when {
            File(packDir, "tray_icon.png").exists() -> "tray_icon.png"
            File(packDir, "tray_icon.webp").exists() -> "tray_icon.webp"
            else -> "tray_icon.png"
        }

        cursor.addRow(arrayOf<Any?>(
            identifier, metadata.name, metadata.publisher, trayIconName,
            "https://play.google.com/store/apps/details?id=com.futureatoms.sticker_officer",
            "", "", "", "https://www.example.com/privacy",
            "https://www.example.com/license", metadata.imageDataVersion, 0,
            metadata.animatedStickerPack
        ))

        return cursor
    }

    /**
     * Lists stickers within a specific pack. Each .webp file (except tray_icon) is a sticker.
     */
    private fun getStickersCursor(identifier: String): Cursor {
        val cursor = MatrixCursor(
            arrayOf(
                STICKER_FILE_NAME,
                STICKER_FILE_EMOJI,
                STICKER_FILE_ACCESSIBILITY_TEXT
            )
        )

        val packDir = File(getStickersDir(), identifier)
        if (!packDir.exists()) {
            Log.e(TAG, "Pack dir not found: ${packDir.absolutePath}")
            return cursor
        }

        val stickerFiles = packDir.listFiles()
            ?.filter {
                val isSticker = (it.extension == "webp" || it.extension == "png") &&
                    !it.name.startsWith("tray_icon") &&
                    !it.name.startsWith("pack_info")
                isSticker
            }
            ?.sortedBy { it.name }

        Log.d(TAG, "Pack $identifier: found ${stickerFiles?.size ?: 0} stickers in ${packDir.absolutePath}")
        stickerFiles?.forEach { f ->
            Log.d(TAG, "  sticker: ${f.name} (${f.length()} bytes)")
        }

        stickerFiles?.forEach { file ->
            cursor.addRow(arrayOf<Any?>(file.name, "😀", "")) // WhatsApp expects all 3 columns
        }

        return cursor
    }

    /**
     * Opens a sticker or tray icon file for reading by WhatsApp.
     */
    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor? {
        val matchCode = uriMatcher.match(uri)
        Log.d(TAG, "openFile() uri=$uri matchCode=$matchCode")

        if (matchCode != STICKER_FILE && matchCode != STICKER_ASSET) {
            Log.e(TAG, "openFile() rejected — unmatched URI: $uri")
            return null
        }

        val pathSegments = uri.pathSegments
        if (pathSegments.size < 3) {
            Log.e(TAG, "openFile() rejected — too few path segments: $pathSegments")
            return null
        }

        val identifier = pathSegments[1]
        val fileName = pathSegments[2]

        // Prevent path traversal
        if (fileName.contains("..")) {
            Log.e(TAG, "openFile() rejected — path traversal attempt: $fileName")
            return null
        }

        val file = File(File(getStickersDir(), identifier), fileName)
        Log.d(TAG, "openFile() serving: ${file.absolutePath} exists=${file.exists()} size=${if (file.exists()) file.length() else 0} bytes")

        if (!file.exists()) {
            Log.e(TAG, "openFile() file not found: ${file.absolutePath}")
            return null
        }

        return ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
    }

    override fun openAssetFile(uri: Uri, mode: String): AssetFileDescriptor? {
        val descriptor = openFile(uri, mode) ?: return null
        return AssetFileDescriptor(descriptor, 0, AssetFileDescriptor.UNKNOWN_LENGTH)
    }

    override fun getType(uri: Uri): String? {
        return when (uriMatcher.match(uri)) {
            STICKER_PACK_LIST, STICKER_PACK -> "vnd.android.cursor.dir/vnd.$AUTHORITY.metadata"
            STICKERS_IN_PACK -> "vnd.android.cursor.dir/vnd.$AUTHORITY.stickers"
            STICKER_FILE, STICKER_ASSET -> {
                // Return correct MIME type based on file extension
                val fileName = uri.lastPathSegment ?: ""
                if (fileName.endsWith(".png")) "image/png" else "image/webp"
            }
            else -> null
        }
    }

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?): Int = 0
}
