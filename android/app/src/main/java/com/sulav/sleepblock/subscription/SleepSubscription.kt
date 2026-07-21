package com.sulav.sleepblock.subscription

import android.app.Activity
import android.content.Context
import android.util.Log
import com.revenuecat.purchases.CustomerInfo
import com.revenuecat.purchases.LogLevel
import com.revenuecat.purchases.Package
import com.revenuecat.purchases.Purchases
import com.revenuecat.purchases.PurchasesConfiguration
import com.revenuecat.purchases.PurchasesError
import com.revenuecat.purchases.interfaces.ReceiveCustomerInfoCallback
import com.revenuecat.purchases.interfaces.ReceiveOfferingsCallback
import com.revenuecat.purchases.interfaces.UpdatedCustomerInfoListener
import com.revenuecat.purchases.models.GoogleReplacementMode
import com.revenuecat.purchases.purchaseWith
import com.sulav.sleepblock.BuildConfig
import kotlin.coroutines.resume
import kotlinx.coroutines.suspendCancellableCoroutine

/**
 * Kotlin mirror of ios SleepSubscription.swift: the `pro` entitlement as a
 * three-state answer (the paywall gate acts only on a *resolved*
 * NOT_ENTITLED), plans fetched from the current offering, and the same dev
 * policy — an unconfigured build (no RevenueCat key) resolves ENTITLED at
 * init and never gates.
 */
enum class EntitlementState { UNKNOWN, ENTITLED, NOT_ENTITLED }

/**
 * Display-only detail about the active subscription for the Settings status
 * row — distinct from [EntitlementState], which stays the gate's three-state
 * answer. Null until the first fetch resolves, in dev mode, or when there is
 * no entitlement to describe; the Settings group hides while null.
 */
data class SubscriptionStatus(
    val tier: Tier,
    val willRenew: Boolean,
    /** Epoch millis of the renewal/end date, when known. */
    val expiresAtMillis: Long?,
    val isAnnual: Boolean,
) {
    enum class Tier { TRIAL, PRO, NONE }
}

/** One purchasable plan, price strings straight from the store. */
data class SleepPlan(
    val id: String,
    val title: String,
    val isAnnual: Boolean,
    val price: String,
    val monthlyEquivalent: String?,
    val trialDays: Int,
    val rcPackage: Package?,
)

interface SubscriptionProviding {
    val isConfigured: Boolean
    fun start(onChange: (EntitlementState, SubscriptionStatus?) -> Unit)
    suspend fun fetchPlans(): List<SleepPlan>
    /** Null when the user cancelled; throws with a user message on failure. */
    suspend fun purchase(activity: Activity, plan: SleepPlan): EntitlementState?
    suspend fun restore(): EntitlementState
    fun logIn(accountID: String)
    fun logOut()
}

object SleepSubscriptionFactory {
    fun makeDefault(context: Context): SubscriptionProviding {
        // TEMPORARY: paywall disabled for demo screen recording.
        // To re-enable, remove this line and uncomment the block below.
        Log.i(TAG, "Paywall temporarily disabled for demo — all users entitled")
        return DisabledSubscription

        // val key = BuildConfig.REVENUECAT_API_KEY
        // if (key.isEmpty() || key.startsWith("your-")) {
        //     Log.i(TAG, "RevenueCat key missing — dev mode, no paywall")
        //     return DisabledSubscription
        // }
        // return RevenueCatSubscription(context, key)
    }

    const val TAG = "SleepSubscription"
}

object DisabledSubscription : SubscriptionProviding {
    override val isConfigured = false
    override fun start(onChange: (EntitlementState, SubscriptionStatus?) -> Unit) =
        onChange(EntitlementState.ENTITLED, null)
    override suspend fun fetchPlans(): List<SleepPlan> = emptyList()
    override suspend fun purchase(activity: Activity, plan: SleepPlan): EntitlementState? = EntitlementState.ENTITLED
    override suspend fun restore(): EntitlementState = EntitlementState.ENTITLED
    override fun logIn(accountID: String) {}
    override fun logOut() {}
}

class RevenueCatSubscription(context: Context, apiKey: String) : SubscriptionProviding {

    override val isConfigured = true

    init {
        Purchases.logLevel = if (BuildConfig.DEBUG) LogLevel.DEBUG else LogLevel.INFO
        Purchases.configure(PurchasesConfiguration.Builder(context, apiKey).build())
    }

    override fun start(onChange: (EntitlementState, SubscriptionStatus?) -> Unit) {
        // The listener replays cached info immediately, so a subscriber
        // resolves offline too — same behavior the iOS client relies on.
        Purchases.sharedInstance.updatedCustomerInfoListener =
            UpdatedCustomerInfoListener { info -> onChange(entitlement(info), status(info)) }
        Purchases.sharedInstance.getCustomerInfo(object : ReceiveCustomerInfoCallback {
            override fun onReceived(customerInfo: CustomerInfo) =
                onChange(entitlement(customerInfo), status(customerInfo))
            override fun onError(error: PurchasesError) {
                Log.e(SleepSubscriptionFactory.TAG, "customerInfo failed: ${error.message}")
            }
        })
    }

    /** Settings display detail, read straight off the `pro` entitlement. */
    private fun status(info: CustomerInfo): SubscriptionStatus? {
        val pro = info.entitlements.all["pro"] ?: return null
        if (!pro.isActive) return null
        return SubscriptionStatus(
            tier = if (pro.periodType == com.revenuecat.purchases.PeriodType.TRIAL) {
                SubscriptionStatus.Tier.TRIAL
            } else {
                SubscriptionStatus.Tier.PRO
            },
            willRenew = pro.willRenew,
            expiresAtMillis = pro.expirationDate?.time,
            isAnnual = "year" in pro.productIdentifier.lowercase() ||
                "annual" in pro.productIdentifier.lowercase(),
        )
    }

    override suspend fun fetchPlans(): List<SleepPlan> = suspendCancellableCoroutine { cont ->
        Purchases.sharedInstance.getOfferings(object : ReceiveOfferingsCallback {
            override fun onReceived(offerings: com.revenuecat.purchases.Offerings) {
                val packages = offerings.current?.availablePackages.orEmpty()
                cont.resume(packages.map { pkg ->
                    val product = pkg.product
                    val isAnnual = pkg.packageType == com.revenuecat.purchases.PackageType.ANNUAL
                    val trialDays = product.defaultOption?.freePhase?.billingPeriod?.let { period ->
                        when (period.unit) {
                            com.revenuecat.purchases.models.Period.Unit.DAY -> period.value
                            com.revenuecat.purchases.models.Period.Unit.WEEK -> period.value * 7
                            else -> 0
                        }
                    } ?: 0
                    SleepPlan(
                        id = pkg.identifier,
                        title = if (isAnnual) "Annual" else "Monthly",
                        isAnnual = isAnnual,
                        price = product.price.formatted,
                        monthlyEquivalent = if (isAnnual) {
                            product.pricePerMonth()?.formatted
                        } else null,
                        trialDays = trialDays,
                        rcPackage = pkg,
                    )
                })
            }

            override fun onError(error: PurchasesError) {
                Log.e(SleepSubscriptionFactory.TAG, "offerings failed: ${error.message}")
                cont.resume(emptyList())
            }
        })
    }

    override suspend fun purchase(activity: Activity, plan: SleepPlan): EntitlementState? =
        suspendCancellableCoroutine { cont ->
            val pkg = plan.rcPackage ?: run {
                cont.resume(null)
                return@suspendCancellableCoroutine
            }
            Purchases.sharedInstance.purchaseWith(
                com.revenuecat.purchases.PurchaseParams.Builder(activity, pkg).build(),
                onError = { error, userCancelled ->
                    if (userCancelled) cont.resume(null)
                    else cont.resumeWith(Result.failure(SubscriptionException(error.message)))
                },
                onSuccess = { _, customerInfo -> cont.resume(entitlement(customerInfo)) },
            )
        }

    override suspend fun restore(): EntitlementState = suspendCancellableCoroutine { cont ->
        Purchases.sharedInstance.restorePurchases(object : ReceiveCustomerInfoCallback {
            override fun onReceived(customerInfo: CustomerInfo) = cont.resume(entitlement(customerInfo))
            override fun onError(error: PurchasesError) =
                cont.resumeWith(Result.failure(SubscriptionException(error.message)))
        })
    }

    override fun logIn(accountID: String) {
        Purchases.sharedInstance.logIn(accountID, object : com.revenuecat.purchases.interfaces.LogInCallback {
            override fun onReceived(customerInfo: CustomerInfo, created: Boolean) {}
            override fun onError(error: PurchasesError) {
                Log.e(SleepSubscriptionFactory.TAG, "logIn failed: ${error.message}")
            }
        })
    }

    override fun logOut() {
        runCatching { Purchases.sharedInstance.logOut(null) }
    }

    private fun entitlement(info: CustomerInfo): EntitlementState =
        if (info.entitlements.active.containsKey("pro")) EntitlementState.ENTITLED
        else EntitlementState.NOT_ENTITLED
}

class SubscriptionException(message: String) : Exception(message)
