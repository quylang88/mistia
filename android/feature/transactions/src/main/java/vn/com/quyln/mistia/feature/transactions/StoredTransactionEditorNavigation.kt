package vn.com.quyln.mistia.feature.transactions

import androidx.compose.runtime.saveable.Saver
import java.util.UUID

/** Navigation stores only an owned record identity; content is fetched again from the repository. */
data class StoredTransactionEditorNavigation(val owner:String,val recordId:String?) {
    companion object {
        fun saver(owner:String):Saver<StoredTransactionEditorNavigation,Any> = Saver(
            save={target ->
                if(target.owner!=owner || target.recordId?.let {runCatching {UUID.fromString(it).toString()==it}.getOrDefault(false)}==false) null
                else listOf(target.owner,target.recordId.orEmpty())
            },
            restore={value ->
                val items=value as? List<*>
                val id=items?.getOrNull(1) as? String
                if(items?.size!=2 || items[0]!=owner || id==null || (id.isNotEmpty() && !runCatching {UUID.fromString(id).toString()==id}.getOrDefault(false))) null
                else StoredTransactionEditorNavigation(owner,id.ifEmpty {null})
            },
        )
    }
}
