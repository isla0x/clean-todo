package com.isla0x.haruring

import android.app.Activity
import android.content.Context
import android.content.Intent
import com.android.billingclient.api.AcknowledgePurchaseParams
import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.BillingClientStateListener
import com.android.billingclient.api.BillingFlowParams
import com.android.billingclient.api.BillingResult
import com.android.billingclient.api.PendingPurchasesParams
import com.android.billingclient.api.ProductDetails
import com.android.billingclient.api.Purchase
import com.android.billingclient.api.PurchasesUpdatedListener
import com.android.billingclient.api.QueryProductDetailsParams
import com.android.billingclient.api.QueryPurchasesParams
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** 앱(Flutter)과 안드로이드 기능(위젯 저장소, 구글 결제, 체험 기간)을 이어주는 다리예요. */
class HaruNative(private val activity: Activity, private val channel: MethodChannel) :
    PurchasesUpdatedListener {

    companion object {
        const val PRODUCT_ID = "haruring_pro"
        const val PREFS = "haru"
    }

    private val prefs = activity.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    private var client: BillingClient? = null
    private var pendingBuy: MethodChannel.Result? = null
    private var pendingLink: String? = null

    // ── 연결 ──

    fun handleIntent(intent: Intent?) {
        val link = intent?.getStringExtra("haruLink") ?: return
        intent.removeExtra("haruLink")
        pendingLink = link
        channel.invokeMethod("linkAvailable", null)
    }

    fun close() {
        client?.endConnection()
        client = null
    }

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "widgetSync" -> {
                val e = prefs.edit()
                call.argument<String>("items")?.let { e.putString("items_v1", it) }
                call.argument<String>("pro")?.let { e.putString("pro_v1", it) }
                e.apply()
                HaruWidget.refresh(activity)
                result.success(null)
            }
            "takeToggles" -> {
                val s = prefs.getString("toggles_v1", "[]") ?: "[]"
                prefs.edit().remove("toggles_v1").apply()
                result.success(s)
            }
            "takePendingLink" -> {
                val l = pendingLink
                pendingLink = null
                result.success(l)
            }
            "proStatus" -> checkOwned { owned ->
                val out = HashMap<String, Any>()
                out["purchased"] = owned
                if (prefs.contains("trialStart")) out["trialStart"] = prefs.getLong("trialStart", 0L)
                result.success(out)
            }
            "productPrice" -> queryProduct { d ->
                result.success(d?.oneTimePurchaseOfferDetails?.formattedPrice)
            }
            "startTrial" -> {
                if (!prefs.contains("trialStart")) {
                    prefs.edit().putLong("trialStart", System.currentTimeMillis()).apply()
                }
                result.success(prefs.getLong("trialStart", 0L))
            }
            "purchase" -> purchase(result)
            "restore" -> checkOwned { owned -> result.success(owned) }
            else -> result.notImplemented()
        }
    }

    // ── 구글 결제 ──

    private fun withClient(block: (BillingClient?) -> Unit) {
        val existing = client
        if (existing != null && existing.isReady) {
            block(existing)
            return
        }
        val c = BillingClient.newBuilder(activity)
            .setListener(this)
            .enablePendingPurchases(PendingPurchasesParams.newBuilder().enableOneTimeProducts().build())
            .build()
        client = c
        var answered = false
        c.startConnection(object : BillingClientStateListener {
            override fun onBillingSetupFinished(r: BillingResult) {
                if (answered) return
                answered = true
                block(if (r.responseCode == BillingClient.BillingResponseCode.OK) c else null)
            }

            override fun onBillingServiceDisconnected() {
                if (answered) return
                answered = true
                block(null)
            }
        })
    }

    /** 이 기기 구글 계정이 PRO를 샀는지. 인터넷이 안 되면 마지막으로 확인한 값을 써요. */
    private fun checkOwned(done: (Boolean) -> Unit) {
        withClient { c ->
            if (c == null) {
                done(prefs.getBoolean("purchased", false))
                return@withClient
            }
            val params = QueryPurchasesParams.newBuilder().setProductType(BillingClient.ProductType.INAPP).build()
            c.queryPurchasesAsync(params) { r, list ->
                if (r.responseCode != BillingClient.BillingResponseCode.OK) {
                    done(prefs.getBoolean("purchased", false))
                    return@queryPurchasesAsync
                }
                var owned = false
                for (p in list) {
                    if (p.products.contains(PRODUCT_ID) && p.purchaseState == Purchase.PurchaseState.PURCHASED) {
                        owned = true
                        acknowledge(c, p)
                    }
                }
                prefs.edit().putBoolean("purchased", owned).apply()
                done(owned)
            }
        }
    }

    private fun acknowledge(c: BillingClient, p: Purchase) {
        if (p.isAcknowledged) return
        c.acknowledgePurchase(
            AcknowledgePurchaseParams.newBuilder().setPurchaseToken(p.purchaseToken).build()
        ) { }
    }

    private fun queryProduct(done: (ProductDetails?) -> Unit) {
        withClient { c ->
            if (c == null) {
                done(null)
                return@withClient
            }
            val product = QueryProductDetailsParams.Product.newBuilder()
                .setProductId(PRODUCT_ID)
                .setProductType(BillingClient.ProductType.INAPP)
                .build()
            val params = QueryProductDetailsParams.newBuilder().setProductList(listOf(product)).build()
            c.queryProductDetailsAsync(params) { r, details ->
                done(if (r.responseCode == BillingClient.BillingResponseCode.OK) details.firstOrNull() else null)
            }
        }
    }

    private fun purchase(result: MethodChannel.Result) {
        queryProduct { d ->
            val c = client
            if (d == null || c == null) {
                result.success("error:product")
                return@queryProduct
            }
            val pd = BillingFlowParams.ProductDetailsParams.newBuilder().setProductDetails(d).build()
            val flow = BillingFlowParams.newBuilder().setProductDetailsParamsList(listOf(pd)).build()
            pendingBuy = result
            val r = c.launchBillingFlow(activity, flow)
            if (r.responseCode != BillingClient.BillingResponseCode.OK) {
                pendingBuy = null
                result.success("error:${r.debugMessage}")
            }
        }
    }

    override fun onPurchasesUpdated(r: BillingResult, purchases: MutableList<Purchase>?) {
        val reply = pendingBuy
        pendingBuy = null
        when (r.responseCode) {
            BillingClient.BillingResponseCode.OK -> {
                var state = "error:empty"
                for (p in purchases ?: emptyList()) {
                    if (!p.products.contains(PRODUCT_ID)) continue
                    if (p.purchaseState == Purchase.PurchaseState.PURCHASED) {
                        client?.let { acknowledge(it, p) }
                        prefs.edit().putBoolean("purchased", true).apply()
                        state = "purchased"
                    } else if (p.purchaseState == Purchase.PurchaseState.PENDING) {
                        state = "pending"
                    }
                }
                if (reply != null) reply.success(state) else channel.invokeMethod("proChanged", null)
            }
            BillingClient.BillingResponseCode.USER_CANCELED -> reply?.success("cancelled")
            BillingClient.BillingResponseCode.ITEM_ALREADY_OWNED -> {
                prefs.edit().putBoolean("purchased", true).apply()
                if (reply != null) reply.success("purchased") else channel.invokeMethod("proChanged", null)
            }
            else -> reply?.success("error:${r.debugMessage}")
        }
    }
}
