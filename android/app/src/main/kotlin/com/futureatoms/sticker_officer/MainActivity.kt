package com.futureatoms.sticker_officer

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.security.MessageDigest

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "com.futureatoms.sticker_officer/whatsapp"
        private const val SHARE_IMPORT_CHANNEL = "com.futureatoms.sticker_officer/share_import"
        private const val AUTHORITY = StickerContentProvider.AUTHORITY
        private const val TAG = "StickerOfficer"
        private const val ADD_STICKER_PACK_REQUEST_CODE = 200
    }

    private var pendingMethodResult: MethodChannel.Result? = null
    private var pendingPackIdentifier: String? = null
    private var shareImportChannel: MethodChannel? = null
    private var pendingSharedMedia: List<Map<String, String?>> = emptyList()

    /**
     * Returns WEBP_LOSSLESS on API 30+ or the deprecated WEBP on older devices.
     * WEBP_LOSSLESS was added in API 30; using it on older APIs causes a crash.
     */
    @Suppress("DEPRECATION")
    private fun webpLossless(): Bitmap.CompressFormat {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Bitmap.CompressFormat.WEBP_LOSSLESS
        } else {
            Bitmap.CompressFormat.WEBP
        }
    }

    /**
     * Returns WEBP_LOSSY on API 30+ or the deprecated WEBP on older devices.
     */
    @Suppress("DEPRECATION")
    private fun webpLossy(): Bitmap.CompressFormat {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Bitmap.CompressFormat.WEBP_LOSSY
        } else {
            Bitmap.CompressFormat.WEBP
        }
    }

    /**
     * Checks whether the given bytes start with a valid WebP header (RIFF....WEBP).
     */
    private fun isValidWebpFile(file: File): Boolean {
        if (!file.exists() || file.length() < 12) return false
        val header = ByteArray(12)
        file.inputStream().use { it.read(header) }
        // RIFF at offset 0 and WEBP at offset 8
        return header[0] == 'R'.code.toByte() &&
                header[1] == 'I'.code.toByte() &&
                header[2] == 'F'.code.toByte() &&
                header[3] == 'F'.code.toByte() &&
                header[8] == 'W'.code.toByte() &&
                header[9] == 'E'.code.toByte() &&
                header[10] == 'B'.code.toByte() &&
                header[11] == 'P'.code.toByte()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        shareImportChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SHARE_IMPORT_CHANNEL
        ).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "getPendingSharedMedia" -> {
                        val sharedMedia = pendingSharedMedia
                        pendingSharedMedia = emptyList()
                        result.success(sharedMedia)
                    }
                    else -> result.notImplemented()
                }
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "addStickerPackToWhatsApp" -> {
                    val identifier = call.argument<String>("identifier")
                    val name = call.argument<String>("name")
                    val publisher = call.argument<String>("publisher")
                    val stickerPaths = call.argument<List<String>>("stickerPaths")
                    val trayIconPath = call.argument<String>("trayIconPath")

                    if (identifier == null || name == null || stickerPaths == null || trayIconPath == null) {
                        result.error("INVALID_ARGS", "Missing required arguments", null)
                        return@setMethodCallHandler
                    }

                    try {
                        if (pendingMethodResult != null) {
                            result.success(
                                mapOf(
                                    "success" to false,
                                    "message" to "A WhatsApp export is already in progress."
                                )
                            )
                            return@setMethodCallHandler
                        }

                        val effectivePublisher = publisher ?: "StickerOfficer"
                        val sourceSignature = buildPackSourceSignature(
                            identifier = identifier,
                            name = name,
                            publisher = effectivePublisher,
                            stickerPaths = stickerPaths,
                            trayIconPath = trayIconPath
                        )

                        val alreadyWhitelisted = WhatsAppWhitelistCheck.isPackWhitelistedAnywhere(this, identifier)
                        if (alreadyWhitelisted && isPreparedPackReusable(identifier, sourceSignature)) {
                            android.util.Log.d(TAG, "Pack $identifier already whitelisted and cache is fresh; skipping rebuild")
                            result.success(mapOf(
                                "success" to true,
                                "message" to "Sticker pack is already available in WhatsApp."
                            ))
                            return@setMethodCallHandler
                        }

                        // 1. Prepare the pack directory with WhatsApp-compatible assets.
                        val packDir = prepareStickerPack(
                            identifier = identifier,
                            name = name,
                            publisher = effectivePublisher,
                            stickerPaths = stickerPaths,
                            trayIconPath = trayIconPath,
                            sourceSignature = sourceSignature
                        )

                        if (packDir == null) {
                            result.success(mapOf(
                                "success" to false,
                                "message" to "Oops! We couldn't get your stickers ready. Make sure you have at least 3 sticker images in the pack."
                            ))
                            return@setMethodCallHandler
                        }

                        // Verify the pack has enough stickers
                        val webpFiles = packDir.listFiles()?.filter {
                            it.extension == "webp" && it.name != "tray_icon.webp"
                        } ?: emptyList()

                        if (webpFiles.size < 3) {
                            result.success(mapOf(
                                "success" to false,
                                "message" to "Almost there! Only ${webpFiles.size} stickers were ready. You need at least 3 to make a pack."
                            ))
                            return@setMethodCallHandler
                        }

                        // 2. Check if WhatsApp is installed.
                        if (!isWhatsAppInstalled()) {
                            result.success(mapOf(
                                "success" to false,
                                "message" to "WhatsApp isn't installed yet! Install WhatsApp first, then come back to add your stickers."
                            ))
                            return@setMethodCallHandler
                        }

                        // 3. If WhatsApp already has this pack, return immediately.
                        if (alreadyWhitelisted || WhatsAppWhitelistCheck.isPackWhitelistedAnywhere(this, identifier)) {
                            result.success(mapOf(
                                "success" to true,
                                "message" to "Sticker pack is already available in WhatsApp."
                            ))
                            return@setMethodCallHandler
                        }

                        // 4. Launch WhatsApp's add-pack flow and wait for a real result.
                        pendingMethodResult = result
                        pendingPackIdentifier = identifier

                        val launched = launchAddStickerPackIntent(identifier, name)
                        if (!launched) {
                            finishPendingAdd(
                                success = false,
                                message = "Hmm, we couldn't open WhatsApp. Make sure it's installed and up to date!"
                            )
                        }
                    } catch (e: Exception) {
                        android.util.Log.e(TAG, "WhatsApp export error", e)
                        clearPendingAdd()
                        result.success(mapOf(
                            "success" to false,
                            "message" to "Something went wrong while preparing your stickers. Please try again!"
                        ))
                    }
                }
                "isWhatsAppInstalled" -> {
                    result.success(isWhatsAppInstalled())
                }
                else -> result.notImplemented()
            }
        }

        captureIncomingSharedMedia(intent, notifyFlutter = false)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureIncomingSharedMedia(intent, notifyFlutter = true)
    }

    /**
     * Converts sticker PNG/image files to WebP and organizes them in the
     * internal storage directory that the ContentProvider serves.
     */
    private fun prepareStickerPack(
        identifier: String,
        name: String,
        publisher: String,
        stickerPaths: List<String>,
        trayIconPath: String,
        sourceSignature: String
    ): File? {
        val stickersBaseDir = File(filesDir, "sticker_packs")
        val packDir = File(stickersBaseDir, identifier)

        if (isPreparedPackReusable(identifier, sourceSignature)) {
            android.util.Log.d(TAG, "Reusing cached sticker pack for $identifier")
            return packDir
        }

        // Clean existing pack
        if (packDir.exists()) packDir.deleteRecursively()
        packDir.mkdirs()

        // Update the image data version on every export so WhatsApp refreshes changed packs.
        val imageDataVersion = System.currentTimeMillis().toString()
        File(packDir, "pack_info.txt").writeText("$name\n$publisher\n$imageDataVersion")
        File(packDir, "pack_signature.txt").writeText(sourceSignature)

        // Convert and save tray icon as a 96x96 PNG, matching the official sample app.
        try {
            val trayFile = File(trayIconPath)
            val trayOutputFile = File(packDir, "tray_icon.png")
            if (trayFile.exists()) {
                val trayBitmap = BitmapFactory.decodeFile(trayIconPath)
                if (trayBitmap != null) {
                    val scaledTray = Bitmap.createScaledBitmap(trayBitmap, 96, 96, true)
                    val trayBaos = ByteArrayOutputStream()
                    scaledTray.compress(Bitmap.CompressFormat.PNG, 100, trayBaos)
                    val trayBytes = trayBaos.toByteArray()

                    trayOutputFile.writeBytes(trayBytes)
                    android.util.Log.d(TAG, "Tray icon: ${trayBytes.size} bytes")
                    scaledTray.recycle()
                    trayBitmap.recycle()
                } else {
                    android.util.Log.e(TAG, "Could not decode tray icon: $trayIconPath")
                }
            } else {
                // Create a simple placeholder tray icon
                val placeholder = Bitmap.createBitmap(96, 96, Bitmap.Config.ARGB_8888)
                val baos = ByteArrayOutputStream()
                placeholder.compress(Bitmap.CompressFormat.PNG, 100, baos)
                trayOutputFile.writeBytes(baos.toByteArray())
                android.util.Log.d(TAG, "Tray icon (placeholder): ${baos.size()} bytes")
                placeholder.recycle()
            }
        } catch (e: Exception) {
            android.util.Log.e(TAG, "Tray icon creation failed: ${e.message}", e)
            // Create emergency fallback tray icon
            try {
                val placeholder = Bitmap.createBitmap(96, 96, Bitmap.Config.ARGB_8888)
                val baos = ByteArrayOutputStream()
                placeholder.compress(Bitmap.CompressFormat.PNG, 100, baos)
                File(packDir, "tray_icon.png").writeBytes(baos.toByteArray())
                placeholder.recycle()
            } catch (fallbackError: Exception) {
                android.util.Log.e(TAG, "Even fallback tray icon failed: ${fallbackError.message}")
            }
        }

        // Convert each sticker to 512x512 WebP
        var stickerCount = 0
        for ((index, path) in stickerPaths.withIndex()) {
            try {
                val srcFile = File(path)
                if (!srcFile.exists()) {
                    android.util.Log.d(TAG, "Sticker file not found: $path")
                    continue
                }

                // Configure BitmapFactory to handle large images
                val options = BitmapFactory.Options().apply {
                    inPreferredConfig = Bitmap.Config.ARGB_8888
                }
                val bitmap = BitmapFactory.decodeFile(path, options)
                if (bitmap == null) {
                    android.util.Log.e(TAG, "Failed to decode sticker: $path")
                    continue
                }

                // Skip very tiny placeholder images (1x1 or 2x2 pixels)
                if (bitmap.width < 4 || bitmap.height < 4) {
                    android.util.Log.d(TAG, "Skipping tiny image ${bitmap.width}x${bitmap.height}: $path")
                    bitmap.recycle()
                    continue
                }

                // Scale to 512x512 maintaining aspect ratio, centered on transparent canvas
                val targetSize = 512
                val scale = minOf(
                    targetSize.toFloat() / bitmap.width,
                    targetSize.toFloat() / bitmap.height
                )
                val scaledW = (bitmap.width * scale).toInt().coerceAtLeast(1)
                val scaledH = (bitmap.height * scale).toInt().coerceAtLeast(1)

                val canvas = Bitmap.createBitmap(targetSize, targetSize, Bitmap.Config.ARGB_8888)
                val scaledBitmap = Bitmap.createScaledBitmap(bitmap, scaledW, scaledH, true)
                val canvasGraphics = android.graphics.Canvas(canvas)
                val left = (targetSize - scaledW) / 2f
                val top = (targetSize - scaledH) / 2f
                canvasGraphics.drawBitmap(scaledBitmap, left, top, null)

                // Encode as WebP — try lossless first (preserves transparency),
                // fall back to lossy with quality reduction to fit under 100KB
                val stickerFile = File(packDir, "sticker_${stickerCount + 1}.webp")
                var encoded: ByteArray

                // Try lossless first
                val losslessBaos = ByteArrayOutputStream()
                canvas.compress(webpLossless(), 100, losslessBaos)
                encoded = losslessBaos.toByteArray()

                // If lossless is too big, use lossy with quality reduction
                if (encoded.size > 100 * 1024) {
                    var quality = 80
                    do {
                        val baos = ByteArrayOutputStream()
                        canvas.compress(webpLossy(), quality, baos)
                        encoded = baos.toByteArray()
                        quality -= 10
                    } while (encoded.size > 100 * 1024 && quality > 10)
                }

                android.util.Log.d(TAG, "Sticker ${stickerCount + 1}: ${encoded.size} bytes (${if (encoded.size <= 100 * 1024) "OK" else "TOO BIG"})")

                stickerFile.writeBytes(encoded)

                // Validate the WebP file before counting it
                if (isValidWebpFile(stickerFile)) {
                    stickerCount++
                } else {
                    android.util.Log.e(TAG, "Sticker ${stickerCount + 1} produced invalid WebP, skipping")
                    stickerFile.delete()
                }

                scaledBitmap.recycle()
                canvas.recycle()
                bitmap.recycle()
            } catch (e: Exception) {
                android.util.Log.e(TAG, "Error processing sticker $index: ${e.message}", e)
            }
        }

        // Log all files in the pack directory for debugging
        android.util.Log.d(TAG, "Prepared $stickerCount stickers for pack $identifier in ${packDir.absolutePath}")
        packDir.listFiles()?.forEach { file ->
            android.util.Log.d(TAG, "  -> ${file.name} (${file.length()} bytes)")
        }
        return if (stickerCount >= 3) packDir else null
    }

    private fun isPreparedPackReusable(identifier: String, sourceSignature: String): Boolean {
        val packDir = File(File(filesDir, "sticker_packs"), identifier)
        if (!packDir.exists() || !packDir.isDirectory) {
            return false
        }

        val signatureFile = File(packDir, "pack_signature.txt")
        if (!signatureFile.exists() || signatureFile.readText() != sourceSignature) {
            return false
        }

        val trayIconExists = File(packDir, "tray_icon.png").exists() || File(packDir, "tray_icon.webp").exists()
        if (!trayIconExists) {
            return false
        }

        val preparedStickers = packDir.listFiles()
            ?.filter {
                it.isFile &&
                    it.extension == "webp" &&
                    !it.name.startsWith("tray_icon") &&
                    isValidWebpFile(it)
            }
            ?: emptyList()

        return preparedStickers.size >= 3
    }

    private fun buildPackSourceSignature(
        identifier: String,
        name: String,
        publisher: String,
        stickerPaths: List<String>,
        trayIconPath: String
    ): String {
        val digest = MessageDigest.getInstance("SHA-256")

        fun add(value: String) {
            digest.update(value.toByteArray(Charsets.UTF_8))
            digest.update(byteArrayOf(0))
        }

        add(identifier)
        add(name)
        add(publisher)
        add(trayIconPath)
        appendFileMetadata(digest, File(trayIconPath))

        for (stickerPath in stickerPaths) {
            add(stickerPath)
            appendFileMetadata(digest, File(stickerPath))
        }

        return digest.digest().joinToString("") { byte -> "%02x".format(byte) }
    }

    private fun appendFileMetadata(digest: MessageDigest, file: File) {
        digest.update(byteArrayOf((if (file.exists()) 1 else 0).toByte()))
        digest.update(file.length().toString().toByteArray(Charsets.UTF_8))
        digest.update(byteArrayOf(0))
        digest.update(file.lastModified().toString().toByteArray(Charsets.UTF_8))
        digest.update(byteArrayOf(0))
    }

    /**
     * Sends the intent to WhatsApp to add the sticker pack.
     */
    private fun launchAddStickerPackIntent(identifier: String, name: String): Boolean {
        val whatsappPackage = WhatsAppWhitelistCheck.nextEligiblePackage(this, identifier) ?: return false

        android.util.Log.d(TAG, "Launching WhatsApp intent for pack: $identifier, authority: $AUTHORITY, package=$whatsappPackage")

        val intent = Intent().apply {
            action = "com.whatsapp.intent.action.ENABLE_STICKER_PACK"
            putExtra("sticker_pack_id", identifier)
            putExtra("sticker_pack_authority", AUTHORITY)
            putExtra("sticker_pack_name", name)
            setPackage(whatsappPackage)
        }

        return try {
            startActivityForResult(intent, ADD_STICKER_PACK_REQUEST_CODE)
            true
        } catch (e: ActivityNotFoundException) {
            android.util.Log.e(TAG, "WhatsApp activity not found", e)
            false
        } catch (e: Exception) {
            android.util.Log.e(TAG, "Failed to launch WhatsApp: ${e.message}", e)
            false
        }
    }

    private fun isWhatsAppInstalled(): Boolean {
        return WhatsAppWhitelistCheck.isAnyWhatsAppInstalled(packageManager)
    }

    private fun isPackageInstalled(packageName: String): Boolean {
        return try {
            packageManager.getPackageInfo(packageName, PackageManager.GET_META_DATA)
            true
        } catch (e: PackageManager.NameNotFoundException) {
            false
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        if (requestCode != ADD_STICKER_PACK_REQUEST_CODE) {
            return
        }

        val identifier = pendingPackIdentifier
        if (identifier.isNullOrBlank()) {
            clearPendingAdd()
            return
        }

        if (WhatsAppWhitelistCheck.isPackWhitelistedAnywhere(this, identifier)) {
            finishPendingAdd(
                success = true,
                message = "Sticker pack added to WhatsApp."
            )
            return
        }

        val validationError = data?.getStringExtra("validation_error")
        when {
            resultCode == Activity.RESULT_OK -> finishPendingAdd(
                success = true,
                message = "Sticker pack added to WhatsApp."
            )
            !validationError.isNullOrBlank() -> finishPendingAdd(
                success = false,
                message = "WhatsApp rejected this sticker pack: $validationError"
            )
            else -> finishPendingAdd(
                success = false,
                message = "Sticker pack wasn't added to WhatsApp."
            )
        }
    }

    private fun finishPendingAdd(success: Boolean, message: String) {
        pendingMethodResult?.success(
            mapOf(
                "success" to success,
                "message" to message
            )
        )
        clearPendingAdd()
    }

    private fun clearPendingAdd() {
        pendingMethodResult = null
        pendingPackIdentifier = null
    }

    private fun captureIncomingSharedMedia(intent: Intent?, notifyFlutter: Boolean) {
        if (intent == null) {
            return
        }

        val sharedMedia = extractSharedMedia(intent)
        if (sharedMedia.isEmpty()) {
            return
        }

        android.util.Log.d(TAG, "Captured ${sharedMedia.size} shared media item(s)")

        if (notifyFlutter && shareImportChannel != null) {
            shareImportChannel?.invokeMethod("sharedMediaReceived", sharedMedia)
            pendingSharedMedia = emptyList()
        } else {
            pendingSharedMedia = sharedMedia
        }
    }

    private fun extractSharedMedia(intent: Intent): List<Map<String, String?>> {
        if (intent.action != Intent.ACTION_SEND && intent.action != Intent.ACTION_SEND_MULTIPLE) {
            return emptyList()
        }

        val uris = mutableListOf<Uri>()
        getSingleSharedUri(intent)?.let(uris::add)
        uris.addAll(getMultipleSharedUris(intent))
        intent.clipData?.let { clipData ->
            for (index in 0 until clipData.itemCount) {
                clipData.getItemAt(index).uri?.let(uris::add)
            }
        }

        return uris
            .distinct()
            .mapIndexedNotNull { index, uri -> copySharedUriToCache(uri, index) }
    }

    @Suppress("DEPRECATION")
    private fun getSingleSharedUri(intent: Intent): Uri? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri
        }
    }

    @Suppress("DEPRECATION")
    private fun getMultipleSharedUris(intent: Intent): List<Uri> {
        val uris = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM)
        }
        return uris ?: emptyList()
    }

    private fun copySharedUriToCache(uri: Uri, index: Int): Map<String, String?>? {
        return try {
            val displayName = resolveDisplayName(uri)
            val mimeType = contentResolver.getType(uri)
            val extension = resolveSharedExtension(displayName, mimeType)

            if (!isSupportedSharedImage(mimeType, extension)) {
                android.util.Log.d(TAG, "Skipping unsupported shared URI: $uri mime=$mimeType")
                return null
            }

            val importDir = File(cacheDir, "shared_imports").apply { mkdirs() }
            val safeBaseName = sanitizeBaseName(displayName ?: "shared_sticker_$index")
            val outputFile = File(
                importDir,
                "${System.currentTimeMillis()}_${index}_${safeBaseName}.$extension"
            )

            contentResolver.openInputStream(uri)?.use { input ->
                outputFile.outputStream().use { output ->
                    input.copyTo(output)
                }
            } ?: return null

            mapOf(
                "path" to outputFile.absolutePath,
                "mimeType" to mimeType,
                "name" to displayName
            )
        } catch (error: Exception) {
            android.util.Log.e(TAG, "Failed to import shared URI: $uri", error)
            null
        }
    }

    private fun resolveDisplayName(uri: Uri): String? {
        if (uri.scheme == "file") {
            return uri.lastPathSegment
        }

        return contentResolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME),
            null,
            null,
            null
        )?.use { cursor ->
            val columnIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (columnIndex >= 0 && cursor.moveToFirst()) {
                cursor.getString(columnIndex)
            } else {
                null
            }
        }
    }

    private fun resolveSharedExtension(displayName: String?, mimeType: String?): String {
        val normalizedMime = mimeType?.lowercase()
        if (normalizedMime == "image/webp") return "webp"
        if (normalizedMime == "image/png") return "png"
        if (normalizedMime == "image/jpeg" || normalizedMime == "image/jpg") return "jpg"

        val candidate = displayName ?: ""
        val dotIndex = candidate.lastIndexOf('.')
        if (dotIndex >= 0 && dotIndex < candidate.length - 1) {
            return candidate.substring(dotIndex + 1).lowercase()
        }

        return "png"
    }

    private fun isSupportedSharedImage(mimeType: String?, extension: String): Boolean {
        if (mimeType?.startsWith("image/") == true) {
            return true
        }

        return extension == "png" ||
                extension == "jpg" ||
                extension == "jpeg" ||
                extension == "webp"
    }

    private fun sanitizeBaseName(displayName: String): String {
        val withoutExtension = displayName.substringBeforeLast('.', displayName)
        val sanitized = withoutExtension.replace(Regex("[^A-Za-z0-9._-]"), "_")
        return sanitized.ifBlank { "shared_sticker" }.take(48)
    }
}
