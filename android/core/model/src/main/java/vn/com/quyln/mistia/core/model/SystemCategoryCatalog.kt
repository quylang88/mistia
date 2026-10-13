package vn.com.quyln.mistia.core.model

import java.nio.ByteBuffer
import java.security.MessageDigest
import java.util.UUID
import kotlinx.serialization.json.*

data class SystemCategoryDefinition(
    val key:String,
    val parentKey:String?,
    val kind:TransactionCategoryKind,
    val iconSymbolName:String,
    val fallbackIconSymbolName:String,
    val iconColorHex:String,
    val translations:Map<String,String>,
    val aliases:List<String>,
    val isActive:Boolean,
    /** Swift bootstrap ordering: active parent index, or active sibling index. */
    val sortOrder:Int?,
) {
    val name:String get()=translations["vi"] ?: key
    val nameEnglish:String get()=translations["en"] ?: name
    val nameJapanese:String get()=translations["ja"] ?: name
    val knownDefaultNames:Set<String> get()=listOfNotNull(translations["vi"],translations["en"],translations["ja"]).toSet()+aliases
}

class SystemCategoryCatalog private constructor(val definitions:List<SystemCategoryDefinition>) {
    val activeDefinitions:List<SystemCategoryDefinition> = definitions.filter(SystemCategoryDefinition::isActive)
    companion object {
        fun parse(source:String):SystemCategoryCatalog {
            val parents=Json.parseToJsonElement(source) as? JsonArray ?: throw IllegalArgumentException("Category registry must be an array")
            val definitions=mutableListOf<SystemCategoryDefinition>()
            var activeParentIndex=0
            parents.forEach { element ->
                val parent=element as? JsonObject ?: throw IllegalArgumentException("Category parent must be an object")
                val kind=TransactionCategoryKind.fromWireValue(parent.string("kind")) ?: throw IllegalArgumentException("Invalid category kind")
                val active=parent.active()
                val parentKey=parent.string("id")
                definitions+=parent.definition(null,kind,active,if(active) activeParentIndex++ else null)
                val children=when(val value=parent["children"]) {
                    null,JsonNull -> emptyList()
                    is JsonArray -> value.toList()
                    else -> throw IllegalArgumentException("Category children must be an array")
                }
                var activeChildIndex=0
                children.forEach { childElement ->
                    val child=childElement as? JsonObject ?: throw IllegalArgumentException("Category child must be an object")
                    val childActive=active && child.active()
                    definitions+=child.definition(parentKey,kind,childActive,if(childActive) activeChildIndex++ else null)
                }
            }
            require(definitions.map {it.key}.toSet().size==definitions.size) { "Duplicate system category keys" }
            return SystemCategoryCatalog(definitions.toList())
        }
        private fun JsonObject.definition(parent:String?,kind:TransactionCategoryKind,active:Boolean,sort:Int?):SystemCategoryDefinition {
            val color=string("color")
            require(Regex("#[0-9A-Fa-f]{6}").matches(color)) { "Invalid registry color" }
            val translations=(get("translations") as? JsonObject ?: throw IllegalArgumentException("Missing translations"))
                .mapValues { (_,value) -> requireString(value) }
            val aliases=(get("aliases") as? JsonArray ?: throw IllegalArgumentException("Missing aliases")).map(::requireString)
            return SystemCategoryDefinition(string("id"),parent,kind,string("icon"),string("fallbackIcon"),color,translations,aliases,active,sort)
        }
        private fun JsonObject.active():Boolean=(get("active") as? JsonPrimitive)?.takeUnless {it.isString}?.booleanOrNull
            ?: throw IllegalArgumentException("Missing category active flag")
        private fun JsonObject.string(key:String):String=requireString(get(key)).also {require(it.isNotEmpty())}
        private fun requireString(element:JsonElement?):String=(element as? JsonPrimitive)?.takeIf {it.isString}?.content
            ?: throw IllegalArgumentException("Invalid category registry string")
    }
}

/** Exact Swift SHA1 namespace/version/variant contract, distinct from Java nameUUIDFromBytes. */
object SystemCategoryIdentity {
    private const val namespace="vn.com.quyln.mistia.system-category"
    fun canonicalId(key:String):String=stable("$namespace.$key")
    fun cloudId(key:String,owner:UserId):String=stable("$namespace.cloud.${uuid(owner.value)}.${canonicalId(key)}")
    fun familyId(remoteCategoryId:String,owner:UserId):String=stable("$namespace.family.${uuid(owner.value)}.${uuid(remoteCategoryId)}")
    private fun uuid(value:String):UUID {
        require(Regex("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}").matches(value))
        return UUID.fromString(value)
    }
    private fun stable(value:String):String {
        val bytes=MessageDigest.getInstance("SHA-1").digest(value.toByteArray(Charsets.UTF_8)).copyOf(16)
        bytes[6]=((bytes[6].toInt() and 0x0F) or 0x50).toByte()
        bytes[8]=((bytes[8].toInt() and 0x3F) or 0x80).toByte()
        val buffer=ByteBuffer.wrap(bytes)
        return UUID(buffer.long,buffer.long).toString()
    }
}
