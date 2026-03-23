package com.futureatoms.sticker_officer

import android.content.ContentResolver
import android.content.Context
import android.content.pm.PackageManager
import android.content.pm.ProviderInfo
import android.database.Cursor
import android.net.Uri

object WhatsAppWhitelistCheck {
    const val CONSUMER_PACKAGE = "com.whatsapp"
    const val BUSINESS_PACKAGE = "com.whatsapp.w4b"

    private const val CONTENT_PROVIDER_SUFFIX = ".provider.sticker_whitelist_check"
    private const val QUERY_PATH = "is_whitelisted"
    private const val AUTHORITY_QUERY_PARAM = "authority"
    private const val IDENTIFIER_QUERY_PARAM = "identifier"
    private const val QUERY_RESULT_COLUMN = "result"

    fun isAnyWhatsAppInstalled(packageManager: PackageManager): Boolean {
        return isPackageInstalled(CONSUMER_PACKAGE, packageManager) ||
            isPackageInstalled(BUSINESS_PACKAGE, packageManager)
    }

    fun nextEligiblePackage(context: Context, identifier: String): String? {
        val packageManager = context.packageManager
        val consumerInstalled = isPackageInstalled(CONSUMER_PACKAGE, packageManager)
        val businessInstalled = isPackageInstalled(BUSINESS_PACKAGE, packageManager)

        if (consumerInstalled && !isPackWhitelisted(context, identifier, CONSUMER_PACKAGE)) {
            return CONSUMER_PACKAGE
        }

        if (businessInstalled && !isPackWhitelisted(context, identifier, BUSINESS_PACKAGE)) {
            return BUSINESS_PACKAGE
        }

        return null
    }

    fun isPackWhitelistedAnywhere(context: Context, identifier: String): Boolean {
        val packageManager = context.packageManager
        val consumerWhitelisted = isPackageInstalled(CONSUMER_PACKAGE, packageManager) &&
            isPackWhitelisted(context, identifier, CONSUMER_PACKAGE)
        val businessWhitelisted = isPackageInstalled(BUSINESS_PACKAGE, packageManager) &&
            isPackWhitelisted(context, identifier, BUSINESS_PACKAGE)

        return consumerWhitelisted || businessWhitelisted
    }

    fun isPackageInstalled(packageName: String, packageManager: PackageManager): Boolean {
        return try {
            val appInfo = packageManager.getApplicationInfo(packageName, 0)
            appInfo.enabled
        } catch (_: PackageManager.NameNotFoundException) {
            false
        }
    }

    private fun isPackWhitelisted(context: Context, identifier: String, packageName: String): Boolean {
        val packageManager = context.packageManager
        val authority = packageName + CONTENT_PROVIDER_SUFFIX
        val providerInfo: ProviderInfo = packageManager.resolveContentProvider(
            authority,
            PackageManager.GET_META_DATA
        ) ?: return false

        if (!providerInfo.enabled) {
            return false
        }

        val queryUri = Uri.Builder()
            .scheme(ContentResolver.SCHEME_CONTENT)
            .authority(authority)
            .appendPath(QUERY_PATH)
            .appendQueryParameter(AUTHORITY_QUERY_PARAM, StickerContentProvider.AUTHORITY)
            .appendQueryParameter(IDENTIFIER_QUERY_PARAM, identifier)
            .build()

        return try {
            context.contentResolver.query(queryUri, null, null, null, null).use { cursor: Cursor? ->
                if (cursor != null && cursor.moveToFirst()) {
                    cursor.getInt(cursor.getColumnIndexOrThrow(QUERY_RESULT_COLUMN)) == 1
                } else {
                    false
                }
            }
        } catch (_: Exception) {
            false
        }
    }
}
