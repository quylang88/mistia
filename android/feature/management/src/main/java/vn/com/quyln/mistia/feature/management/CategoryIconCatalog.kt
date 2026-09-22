package vn.com.quyln.mistia.feature.management

import android.content.Context
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonPrimitive
import vn.com.quyln.mistia.core.model.TransactionCategoryKind

internal data class CategoryIconOption(
    val token: String,
    val colorHex: String,
    val fallbackIcon: String,
)

internal class CategoryIconCatalog private constructor(
    private val byKind: Map<TransactionCategoryKind, List<CategoryIconOption>>,
) {
    private val byToken = byKind.values.flatten().associateBy(CategoryIconOption::token)

    fun options(kind: TransactionCategoryKind): List<CategoryIconOption> = byKind[kind].orEmpty()
    fun option(token: String): CategoryIconOption? = byToken[token]

    companion object {
        private const val ASSET_NAME = "MistiaSystemCategories.json"
        @Volatile private var cached: CategoryIconCatalog? = null

        fun load(context: Context): CategoryIconCatalog = cached ?: synchronized(this) {
            cached ?: context.assets.open(ASSET_NAME).bufferedReader().use { reader ->
                parse(reader.readText()).also { cached = it }
            }
        }

        internal fun parse(source: String): CategoryIconCatalog {
            val parents = Json.parseToJsonElement(source) as JsonArray
            val activeParents = parents.mapNotNull { element ->
                val parent = element as? JsonObject ?: return@mapNotNull null
                if (!parent.active()) return@mapNotNull null
                val kind = parent.string("kind")?.let(TransactionCategoryKind::fromWireValue)
                    ?: return@mapNotNull null
                kind to parent
            }
            return CategoryIconCatalog(
                TransactionCategoryKind.entries.associateWith { kind ->
                    val matching = activeParents.filter { it.first == kind }.map(Pair<TransactionCategoryKind, JsonObject>::second)
                    val parentOptions = matching.mapNotNull(::iconOption)
                    val childOptions = matching.flatMap { parent ->
                        (parent["children"] as? JsonArray).orEmpty()
                            .mapNotNull { it as? JsonObject }
                            .filter { it.active() }
                            .mapNotNull(::iconOption)
                    }
                    parentOptions + childOptions
                }
            )
        }

        private fun iconOption(value: JsonObject): CategoryIconOption? {
            val token = value.string("icon") ?: return null
            val color = value.string("color") ?: return null
            val fallback = value.string("fallbackIcon") ?: return null
            return CategoryIconOption(token, color, fallback)
        }

        private fun JsonObject.active(): Boolean =
            (get("active")?.jsonPrimitive?.booleanOrNull) == true

        private fun JsonObject.string(key: String): String? =
            get(key)?.jsonPrimitive?.contentOrNull?.takeIf(String::isNotBlank)
    }
}

internal enum class CategoryIconFamily {
    FOOD,
    HOME,
    TRANSPORT,
    SHOPPING,
    HEALTH,
    WORK,
    GIFT,
    INCOME,
    OTHER,
}

internal fun categoryIconFamily(fallbackIcon: String?, kind: TransactionCategoryKind?): CategoryIconFamily {
    val value = fallbackIcon.orEmpty().lowercase()
    return when {
        listOf("cart", "fork", "basket", "takeout", "cup", "birthday.cake").any(value::contains) ->
            CategoryIconFamily.FOOD
        listOf("house", "building", "bolt", "drop", "wifi", "phone", "bed.double").any(value::contains) ->
            CategoryIconFamily.HOME
        listOf("car", "bus", "tram", "airplane", "fuelpump", "parkingsign", "bicycle").any(value::contains) ->
            CategoryIconFamily.TRANSPORT
        listOf("bag", "tshirt", "shoe", "hanger", "cart.fill.badge").any(value::contains) ->
            CategoryIconFamily.SHOPPING
        listOf("cross.case", "heart", "pills", "stethoscope", "figure.run").any(value::contains) ->
            CategoryIconFamily.HEALTH
        listOf("briefcase", "storefront", "laptop", "graduationcap", "book").any(value::contains) ->
            CategoryIconFamily.WORK
        listOf("gift", "person.2", "hands", "figure.2").any(value::contains) ->
            CategoryIconFamily.GIFT
        kind == TransactionCategoryKind.INCOME -> CategoryIconFamily.INCOME
        else -> CategoryIconFamily.OTHER
    }
}
