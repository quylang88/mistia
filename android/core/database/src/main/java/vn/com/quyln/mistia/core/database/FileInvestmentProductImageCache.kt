package vn.com.quyln.mistia.core.database

import java.io.File
import java.io.FileOutputStream
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import kotlin.coroutines.CoroutineContext
import kotlinx.coroutines.*
import kotlinx.serialization.json.*
import vn.com.quyln.mistia.core.model.*

/** Local immutable candidates. A RESERVED candidate cannot be discarded by a late form callback. */
class FileInvestmentProductImageCache(
    private val baseDirectory:File,private val currentOwner:()->UserId?,
    private val idProvider:()->String={UUID.randomUUID().toString()},
) {
    private data class Entry(val candidate:InvestmentProductImageCandidate,val imageBytes:Int,val thumbnailBytes:Int,
        val state:String,val revision:String?=null,val previousPath:String?=null,val extra:JsonObject=buildJsonObject{})
    private data class Publication(val ticket:InvestmentProductImagePublication,val state:String,val cleanupQueued:Boolean=false,val extra:JsonObject=buildJsonObject{})
    private data class Manifest(val entries:LinkedHashMap<String,Entry>,val publications:LinkedHashMap<String,Publication>,
        val links:LinkedHashMap<String,String>,val ready:LinkedHashSet<String>,val extra:JsonObject)

    suspend fun stage(owner:UserId,assetId:String,image:ByteArray,thumbnail:ByteArray):Result<InvestmentProductImageCandidate> {
        currentCoroutineContext().ensureActive()
        val copies=try{requireJpeg(image);requireJpeg(thumbnail);image.copyOf() to thumbnail.copyOf()}
            catch(error:Exception){return Result.failure(error)}
        val (full,thumb)=copies
        return guarded(owner){caller->
            requireJpeg(full);requireJpeg(thumb)
            val path=InvestmentProductImagePath.create(owner,assetId,idProvider()).value
            val candidate=InvestmentProductImageCandidate(owner.value,assetId,path,hash(full),hash(thumb))
            val manifest=load(owner)
            manifest.entries[path]?.let{existing->
                require(existing.candidate==candidate){"Immutable product image identity has different bytes"}
                read(owner,existing,false);read(owner,existing,true)
                return@guarded candidate
            }
            val imageFile=imageFile(owner,candidate,false);val thumbFile=imageFile(owner,candidate,true)
            require(!imageFile.exists() && !thumbFile.exists()){"Unpublished product image identity is occupied"}
            try {
                writeAtomically(imageFile,full){checkOwner(owner,caller)}
                writeAtomically(thumbFile,thumb){checkOwner(owner,caller)}
                manifest.entries[path]=Entry(candidate,full.size,thumb.size,"staged")
                save(owner,manifest,caller)
                candidate
            }catch(error:Throwable) {
                // An error/cancellation is not proof that the durable manifest did not commit.
                try {
                    val durable=load(owner).entries[path]
                    if(durable==null){imageFile.delete();thumbFile.delete()}
                    else if(durable.candidate==candidate){read(owner,durable,false);read(owner,durable,true)}
                }catch(probe:Throwable){if(probe!==error)error.addSuppressed(probe)}
                throw error
            }
        }
    }
    suspend fun cachedImageData(owner:UserId,assetId:String,path:String,thumbnail:Boolean=true):Result<ByteArray?> = guarded(owner){
        InvestmentProductImagePath.parse(owner,assetId,path)
        val entry=load(owner).entries[path] ?: return@guarded null
        read(owner,entry,thumbnail)
    }
    suspend fun cacheDownloaded(owner:UserId,assetId:String,path:String,image:ByteArray,thumbnail:ByteArray):Result<Unit> {
        currentCoroutineContext().ensureActive()
        val copies=try{requireJpeg(image);requireJpeg(thumbnail);image.copyOf() to thumbnail.copyOf()}
            catch(error:Exception){return Result.failure(error)}
        return guarded(owner){caller->
            InvestmentProductImagePath.parse(owner,assetId,path)
            val (full,thumb)=copies;requireJpeg(full);requireJpeg(thumb)
            val candidate=InvestmentProductImageCandidate(owner.value,assetId,path,hash(full),hash(thumb))
            val manifest=load(owner)
            manifest.entries[path]?.let{existing->
                require(existing.candidate==candidate){"Immutable downloaded product image differs"}
                read(owner,existing,false);read(owner,existing,true)
                return@guarded Unit
            }
            val imageFile=imageFile(owner,candidate,false);val thumbFile=imageFile(owner,candidate,true)
            require(!imageFile.exists() && !thumbFile.exists()){"Downloaded product image identity is occupied"}
            try {
                writeAtomically(imageFile,full){checkOwner(owner,caller)}
                writeAtomically(thumbFile,thumb){checkOwner(owner,caller)}
                manifest.entries[path]=Entry(candidate,full.size,thumb.size,"downloaded")
                save(owner,manifest,caller)
            }catch(error:Throwable) {
                try{if(load(owner).entries[path]==null){imageFile.delete();thumbFile.delete()}}
                catch(probe:Throwable){if(probe!==error)error.addSuppressed(probe)}
                throw error
            }
        }
    }
    suspend fun imageData(owner:UserId,candidate:InvestmentProductImageCandidate,thumbnail:Boolean=false):Result<ByteArray> = guarded(owner){
        validate(owner,candidate)
        val entry=load(owner).entries[candidate.path] ?: error("Product image candidate is unavailable")
        require(entry.candidate==candidate){"Product image candidate changed"}
        read(owner,entry,thumbnail)
    }
    suspend fun reservePublication(owner:UserId,candidate:InvestmentProductImageCandidate,previousPath:String?,revision:String):Result<InvestmentProductImagePublication> = guarded(owner){caller->
        validate(owner,candidate);require(financeRawUuid(revision)==revision){"Invalid product image publication identity"}
        previousPath?.let{InvestmentProductImagePath.parse(owner,candidate.assetId,it);require(it!=candidate.path)}
        val manifest=load(owner);val entry=manifest.entries[candidate.path] ?: error("Product image candidate is unavailable")
        require(entry.candidate==candidate){"Product image candidate changed"}
        read(owner,entry,false);read(owner,entry,true)
        val ticket=InvestmentProductImagePublication(candidate,revision,previousPath)
        val previous=manifest.publications[revision]
        if(previous!=null)require(previous.ticket==ticket){"Product image publication identity is occupied"}
        else {
            require(entry.state=="staged"){"Product image has another publication reservation"}
            manifest.entries[candidate.path]=entry.copy(state="reserved",revision=revision,previousPath=previousPath)
            manifest.publications[revision]=Publication(ticket,"reserved")
            save(owner,manifest,caller)
        }
        InvestmentProductImagePublication(candidate,revision,previousPath)
    }
    suspend fun discardCandidate(owner:UserId,candidate:InvestmentProductImageCandidate):Result<Boolean> = guarded(owner){caller->
        validate(owner,candidate)
        val manifest=load(owner);val entry=manifest.entries[candidate.path] ?: return@guarded false
        require(entry.candidate==candidate){"Product image candidate changed"}
        if(entry.state!="staged")return@guarded false
        manifest.entries.remove(candidate.path);save(owner,manifest,caller)
        imageFile(owner,candidate,false).delete();imageFile(owner,candidate,true).delete()
        true
    }

    suspend fun reserveRemoval(owner:UserId,assetId:String,previousPath:String?,revision:String):Result<InvestmentProductImagePublication> = guarded(owner){caller->
        val ticket=InvestmentProductImagePublication(owner.value,assetId,revision,previousPath,null)
        validate(owner,ticket)
        val manifest=load(owner);val previous=manifest.publications[revision]
        if(previous!=null)require(previous.ticket==ticket){"Product image publication identity is occupied"}
        else {manifest.publications[revision]=Publication(ticket,"reserved");save(owner,manifest,caller)}
        ticket
    }
    suspend fun verifyPublication(owner:UserId,publication:InvestmentProductImagePublication,allowPublished:Boolean=false):Result<Boolean> = guarded(owner){
        validate(owner,publication);val manifest=load(owner)
        val saved=manifest.publications[publication.revision] ?: return@guarded false
        if(saved.ticket!=publication || (saved.state!="reserved" && !(allowPublished && saved.state in setOf("local","acknowledged"))))return@guarded false
        verifyFiles(owner,manifest,publication)
        true
    }
    suspend fun markLocalPublished(owner:UserId,publication:InvestmentProductImagePublication):Result<Boolean> = guarded(owner){caller->
        validate(owner,publication);val manifest=load(owner);val saved=manifest.publications[publication.revision] ?: return@guarded false
        if(saved.ticket!=publication)return@guarded false
        val previous=manifest.links[publication.assetId]?.let(manifest.publications::get)
        if(previous?.ticket==publication)return@guarded saved.state in setOf("local","acknowledged")
        if(saved.state!="reserved" || (previous!=null && previous.ticket.path!=publication.previousPath))return@guarded false
        verifyFiles(owner,manifest,publication)
        publication.candidate?.let{candidate->manifest.entries[candidate.path]=manifest.entries.getValue(candidate.path).copy(state="published")}
        manifest.publications[publication.revision]=saved.copy(state="local")
        manifest.links[publication.assetId]=publication.revision
        save(owner,manifest,caller);true
    }
    suspend fun pendingUploads(owner:UserId):Result<List<InvestmentProductImageCandidate>> = guarded(owner){
        val manifest=load(owner)
        manifest.links.toSortedMap().values.mapNotNull{revision->manifest.publications.getValue(revision).takeIf{it.state=="local"}?.ticket?.candidate}
            .filter{manifest.entries[it.path]?.state=="published"}
    }
    suspend fun markUploadSucceeded(owner:UserId,candidate:InvestmentProductImageCandidate):Result<Boolean> = guarded(owner){caller->
        validate(owner,candidate);val manifest=load(owner)
        val published=manifest.links[candidate.assetId]?.let(manifest.publications::get) ?: return@guarded false
        if(published.ticket.candidate!=candidate || published.state !in setOf("local","acknowledged"))return@guarded false
        val entry=manifest.entries[candidate.path] ?: return@guarded false
        read(owner,entry,false);read(owner,entry,true)
        if(entry.state=="uploaded")return@guarded true
        require(entry.state=="published"){"Product image has not been locally published"}
        manifest.entries[candidate.path]=entry.copy(state="uploaded");save(owner,manifest,caller);true
    }
    suspend fun acknowledgePublished(owner:UserId,publication:InvestmentProductImagePublication):Result<Boolean> = guarded(owner){caller->
        validate(owner,publication);val manifest=load(owner)
        val saved=manifest.publications[publication.revision] ?: return@guarded false
        if(saved.ticket!=publication || manifest.links[publication.assetId]!=publication.revision || saved.state !in setOf("local","acknowledged"))return@guarded false
        if(saved.state=="acknowledged")return@guarded true
        publication.candidate?.let{if(manifest.entries[it.path]?.state!="uploaded")return@guarded false}
        val referenced=manifest.links.values.mapNotNull{manifest.publications[it]?.ticket?.path}.toSet()+
            manifest.publications.values.filter{it.state=="reserved"}.mapNotNull{it.ticket.path}
        for((key,published) in manifest.publications.toMap())if(published.ticket.assetId==publication.assetId && published.state in setOf("local","acknowledged") && !published.cleanupQueued) {
            published.ticket.previousPath?.takeIf{it !in referenced}?.let{manifest.ready.add(it)}
            manifest.publications[key]=published.copy(cleanupQueued=true)
        }
        manifest.publications[publication.revision]=manifest.publications.getValue(publication.revision).copy(state="acknowledged")
        manifest.publications.entries.removeAll{it.key!=publication.revision && it.value.ticket.assetId==publication.assetId && it.value.state in setOf("local","acknowledged") && it.value.cleanupQueued}
        save(owner,manifest,caller);true
    }
    suspend fun readyDeletions(owner:UserId):Result<List<String>> = guarded(owner){load(owner).ready.sorted()}
    suspend fun markDeletionSucceeded(owner:UserId,assetId:String,path:String):Result<Boolean> = guarded(owner){caller->
        InvestmentProductImagePath.parse(owner,assetId,path)
        val manifest=load(owner)
        if(path !in manifest.ready || manifest.links.values.any{manifest.publications[it]?.ticket?.path==path} ||
            manifest.publications.values.any{it.state=="reserved" && it.ticket.path==path})return@guarded false
        val entry=manifest.entries[path]
        if(entry?.state in setOf("staged","reserved"))return@guarded false
        manifest.ready.remove(path);manifest.entries.remove(path);save(owner,manifest,caller)
        val relative=path.substringAfter('/')
        checkedFile(owner,"images/"+relative).delete();checkedFile(owner,"thumbnails/"+relative).delete();true
    }
    private fun validate(owner:UserId,ticket:InvestmentProductImagePublication) {
        require(ticket.ownerUserId==owner.value){"Product image publication belongs to another owner"}
        require(financeRawUuid(ticket.assetId)==ticket.assetId && financeRawUuid(ticket.revision)==ticket.revision){"Invalid product image publication identity"}
        ticket.previousPath?.let{InvestmentProductImagePath.parse(owner,ticket.assetId,it)}
        ticket.candidate?.let{validate(owner,it);require(it.assetId==ticket.assetId && it.path!=ticket.previousPath)}
    }
    private fun verifyFiles(owner:UserId,manifest:Manifest,ticket:InvestmentProductImagePublication) {
        ticket.candidate?.let{candidate->
            val entry=manifest.entries[candidate.path] ?: error("Publication image is unavailable")
            require(entry.candidate==candidate && entry.revision==ticket.revision && entry.previousPath==ticket.previousPath && entry.state in setOf("reserved","published","uploaded")){"Publication image changed"}
            read(owner,entry,false);read(owner,entry,true)
        }
    }

    private suspend fun <T> guarded(owner:UserId,action:(CoroutineContext)->T):Result<T> = try {
        val caller=currentCoroutineContext();checkOwner(owner,caller)
        withContext(Dispatchers.IO) {
            val lock=locks.getOrPut(baseDirectory.canonicalPath){Any()}
            synchronized(lock){checkOwner(owner,caller);val value=action(caller);checkOwner(owner,caller);Result.success(value)}
        }
    }catch(cancelled:CancellationException){throw cancelled}
    catch(error:Exception){Result.failure(error)}
    private fun checkOwner(owner:UserId,caller:CoroutineContext) {
        require(financeRawUuid(owner.value)==owner.value){"Invalid product image owner"}
        caller.ensureActive()
        if(currentOwner()!=owner)throw CancellationException("Product image account changed")
        caller.ensureActive()
    }
    private fun validate(owner:UserId,candidate:InvestmentProductImageCandidate) {
        require(candidate.ownerUserId==owner.value){"Product image belongs to another owner"}
        InvestmentProductImagePath.parse(owner,candidate.assetId,candidate.path)
        require(digestPattern.matches(candidate.imageSha256) && digestPattern.matches(candidate.thumbnailSha256)){"Invalid product image digest"}
    }
    private fun ownerDirectory(owner:UserId):File {
        val directory=File(baseDirectory.canonicalFile,owner.value).absoluteFile
        require(directory.canonicalFile==directory){"Unsafe product image owner directory"}
        return directory
    }
    private fun checkedFile(owner:UserId,relative:String):File {
        val file=File(ownerDirectory(owner),relative).absoluteFile
        require(file.canonicalFile==file){"Unsafe product image cache location"}
        return file
    }
    private fun imageFile(owner:UserId,candidate:InvestmentProductImageCandidate,thumbnail:Boolean):File =
        checkedFile(owner,(if(thumbnail)"thumbnails/" else "images/")+candidate.path.substringAfter('/'))
    private fun manifestFile(owner:UserId)=checkedFile(owner,"manifest.json")
    private fun read(owner:UserId,entry:Entry,thumbnail:Boolean):ByteArray {
        val file=imageFile(owner,entry.candidate,thumbnail)
        val expected=if(thumbnail)entry.thumbnailBytes else entry.imageBytes
        require(expected in 4..4_000_000 && file.isFile && file.length()==expected.toLong()){"Product image file is missing or incomplete"}
        return file.readBytes().also{data->
            requireJpeg(data)
            require(hash(data)==if(thumbnail)entry.candidate.thumbnailSha256 else entry.candidate.imageSha256){"Product image file content changed"}
        }
    }
    private fun load(owner:UserId):Manifest {
        val file=manifestFile(owner)
        if(!file.exists())return Manifest(linkedMapOf(),linkedMapOf(),linkedMapOf(),linkedSetOf(),buildJsonObject{put("version",1);put("owner",owner.value)})
        require(file.isFile && file.length() in 1..2_000_000){"Invalid product image manifest size"}
        val root=Json.parseToJsonElement(file.readText()).jsonObject
        require(root.number("version")==1 && root.text("owner")==owner.value){"Unsupported product image manifest"}
        val entries=linkedMapOf<String,Entry>()
        for(raw in root.getValue("entries").jsonArray) {
            val p=raw.jsonObject
            val candidate=InvestmentProductImageCandidate(p.text("owner"),p.text("asset"),p.text("path"),p.text("image_sha256"),p.text("thumbnail_sha256"))
            validate(owner,candidate)
            val state=p.text("state");require(state in setOf("staged","reserved","published","uploaded","downloaded")){"Unsupported product image state"}
            val revision=p.optional("revision");val previous=p.optional("previous_path")
            if(state !in setOf("staged","downloaded"))require(revision!=null && financeRawUuid(revision)==revision) else require(revision==null && previous==null)
            previous?.let{InvestmentProductImagePath.parse(owner,candidate.assetId,it);require(it!=candidate.path)}
            val full=p.number("image_bytes");val thumb=p.number("thumbnail_bytes");require(full in 4..4_000_000 && thumb in 4..4_000_000)
            require(candidate.path !in entries){"Duplicate product image manifest identity"}
            entries[candidate.path]=Entry(candidate,full,thumb,state,revision,previous,p)
        }
        val publications=linkedMapOf<String,Publication>()
        for(raw in root["publications"]?.jsonArray.orEmpty()) {
            val p=raw.jsonObject
            val candidate=p["candidate"]?.takeIf{it!=JsonNull}?.jsonObject?.let{c->InvestmentProductImageCandidate(c.text("owner"),c.text("asset"),c.text("path"),c.text("image_sha256"),c.text("thumbnail_sha256"))}
            val ticket=InvestmentProductImagePublication(p.text("owner"),p.text("asset"),p.text("revision"),p.optional("previous_path"),candidate)
            validate(owner,ticket);require(ticket.revision !in publications)
            val state=p.text("state");require(state in setOf("reserved","local","acknowledged"))
            val queued=p["cleanup_queued"]?.jsonPrimitive?.let{require(!it.isString);requireNotNull(it.booleanOrNull)} ?: false
            publications[ticket.revision]=Publication(ticket,state,queued,p)
        }
        val links=linkedMapOf<String,String>()
        for((asset,value) in root["links"]?.jsonObject.orEmpty()) {
            require(financeRawUuid(asset)==asset && value.jsonPrimitive.isString)
            val revision=value.jsonPrimitive.content
            require(publications[revision]?.let{it.ticket.assetId==asset && it.state in setOf("local","acknowledged")}==true)
            links[asset]=revision
        }
        for(entry in entries.values)if(entry.state=="reserved")require(publications[entry.revision]?.let{it.ticket.candidate==entry.candidate && it.ticket.previousPath==entry.previousPath && it.state=="reserved"}==true)
        val ready=linkedSetOf<String>()
        for(raw in root["ready_deletions"]?.jsonArray.orEmpty()) {
            require(raw.jsonPrimitive.isString);val path=raw.jsonPrimitive.content;val parts=path.split('/');require(parts.size==3)
            InvestmentProductImagePath.parse(owner,parts[1],path);require(ready.add(path))
        }
        return Manifest(entries,publications,links,ready,root)
    }
    private fun save(owner:UserId,manifest:Manifest,caller:CoroutineContext) {
        val entries=JsonArray(manifest.entries.values.map{entry->JsonObject(entry.extra+buildJsonObject {
            put("owner",owner.value);put("asset",entry.candidate.assetId);put("path",entry.candidate.path)
            put("image_sha256",entry.candidate.imageSha256);put("thumbnail_sha256",entry.candidate.thumbnailSha256)
            put("image_bytes",entry.imageBytes);put("thumbnail_bytes",entry.thumbnailBytes);put("state",entry.state)
            put("revision",entry.revision?.let(::JsonPrimitive) ?: JsonNull);put("previous_path",entry.previousPath?.let(::JsonPrimitive) ?: JsonNull)
        })})
        val publications=JsonArray(manifest.publications.values.map{p->JsonObject(p.extra+buildJsonObject {
            put("owner",owner.value);put("asset",p.ticket.assetId);put("revision",p.ticket.revision);put("previous_path",p.ticket.previousPath?.let(::JsonPrimitive) ?: JsonNull)
            put("state",p.state);put("cleanup_queued",p.cleanupQueued)
            put("candidate",p.ticket.candidate?.let{c->buildJsonObject {put("owner",c.ownerUserId);put("asset",c.assetId);put("path",c.path);put("image_sha256",c.imageSha256);put("thumbnail_sha256",c.thumbnailSha256)}} ?: JsonNull)
        })})
        val value=JsonObject(manifest.extra+buildJsonObject {
            put("entries",entries);put("publications",publications);put("links",JsonObject(manifest.links.mapValues{JsonPrimitive(it.value)}));put("ready_deletions",JsonArray(manifest.ready.sorted().map(::JsonPrimitive)))
        }).toString().toByteArray(Charsets.UTF_8)
        require(value.size<=2_000_000){"Product image manifest is full"}
        writeAtomically(manifestFile(owner),value){checkOwner(owner,caller)}
    }
    private fun writeAtomically(destination:File,data:ByteArray,beforeCommit:()->Unit) {
        val parent=destination.parentFile!!;check(parent.isDirectory || parent.mkdirs()){"Cannot create product image directory"}
        require(destination.canonicalFile==destination.absoluteFile){"Unsafe product image cache destination"}
        val temporary=File(parent,".${destination.name}.${UUID.randomUUID()}.tmp")
        try {
            FileOutputStream(temporary).use{it.write(data);it.fd.sync()}
            beforeCommit()
            Files.move(temporary.toPath(),destination.toPath(),StandardCopyOption.ATOMIC_MOVE,StandardCopyOption.REPLACE_EXISTING)
        }finally{temporary.delete()}
    }
    private fun JsonObject.text(key:String)=getValue(key).jsonPrimitive.let{require(it.isString);it.content}
    private fun JsonObject.optional(key:String):String?=get(key)?.takeIf{it!=JsonNull}?.jsonPrimitive?.let{require(it.isString);it.content}
    private fun JsonObject.number(key:String)=getValue(key).jsonPrimitive.let{require(!it.isString);requireNotNull(it.intOrNull)}
    private fun requireJpeg(bytes:ByteArray) {
        require(bytes.size in 4..4_000_000 && bytes[0]==0xff.toByte() && bytes[1]==0xd8.toByte() && bytes[bytes.lastIndex-1]==0xff.toByte() && bytes.last()==0xd9.toByte()){"Invalid prepared product JPEG"}
    }
    private fun hash(bytes:ByteArray)=MessageDigest.getInstance("SHA-256").digest(bytes).joinToString(""){"%02x".format(it)}
    companion object {
        private val locks=ConcurrentHashMap<String,Any>()
        private val digestPattern=Regex("[0-9a-f]{64}")
    }
}
