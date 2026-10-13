package com.homevault.app

import com.google.android.play.core.integrity.IntegrityManagerFactory
import com.google.android.play.core.integrity.StandardIntegrityManager
import com.google.android.play.core.integrity.StandardIntegrityManager.PrepareIntegrityTokenRequest
import com.google.android.play.core.integrity.StandardIntegrityManager.StandardIntegrityTokenProvider
import com.google.android.play.core.integrity.StandardIntegrityManager.StandardIntegrityTokenRequest
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Play Integrity bridge (standard API). Dart side: lib/data/integrity/app_check.dart.
 *
 * `prepare(cloudProjectNumber)` warms up a token provider once per process;
 * `token(requestHash)` returns an integrity token bound to that hash. Errors
 * surface as PlatformException codes and the Dart side degrades to "no token".
 */
class MainActivity : FlutterActivity() {

    private var provider: StandardIntegrityTokenProvider? = null
    private var preparing = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "prepare" -> prepare(call.argument<Number>("cloudProjectNumber")?.toLong(), result)
                "token" -> token(call.argument<String>("requestHash"), result)
                else -> result.notImplemented()
            }
        }
    }

    private fun prepare(projectNumber: Long?, result: MethodChannel.Result) {
        if (projectNumber == null || projectNumber <= 0) {
            result.error("bad_args", "cloudProjectNumber required", null)
            return
        }
        if (provider != null) {
            result.success(true)
            return
        }
        if (preparing) {
            result.success(false)
            return
        }
        preparing = true
        val manager: StandardIntegrityManager = IntegrityManagerFactory.createStandard(applicationContext)
        manager
            .prepareIntegrityToken(
                PrepareIntegrityTokenRequest.builder().setCloudProjectNumber(projectNumber).build()
            )
            .addOnSuccessListener { p ->
                provider = p
                preparing = false
                result.success(true)
            }
            .addOnFailureListener { e ->
                preparing = false
                result.error("prepare_failed", e.message, null)
            }
    }

    private fun token(requestHash: String?, result: MethodChannel.Result) {
        val p = provider
        if (p == null) {
            result.error("not_prepared", "call prepare first", null)
            return
        }
        if (requestHash.isNullOrEmpty()) {
            result.error("bad_args", "requestHash required", null)
            return
        }
        p.request(StandardIntegrityTokenRequest.builder().setRequestHash(requestHash).build())
            .addOnSuccessListener { t -> result.success(t.token()) }
            .addOnFailureListener { e -> result.error("request_failed", e.message, null) }
    }

    companion object {
        private const val CHANNEL = "homevault/app_check"
    }
}
