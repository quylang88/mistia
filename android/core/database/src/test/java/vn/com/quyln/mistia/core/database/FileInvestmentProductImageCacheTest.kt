package vn.com.quyln.mistia.core.database

import java.security.MessageDigest
import java.io.File
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.async
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.CoroutineStart
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import vn.com.quyln.mistia.core.model.*

class FileInvestmentProductImageCacheTest {
    @get:Rule val temporary=TemporaryFolder()
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val other=UserId("99999999-9999-9999-9999-999999999999")
    private val asset="22222222-2222-2222-2222-222222222222"
    private val objectId="33333333-3333-3333-3333-333333333333"
    private val revision="44444444-4444-4444-4444-444444444444"
    private var active:UserId?=owner
    private fun cache()=FileInvestmentProductImageCache(temporary.root,{active},{objectId})
    private fun bytes(name:String)=javaClass.classLoader!!.getResourceAsStream("investment-images/$name.jpg")!!.use{it.readBytes()}
    private fun hash(bytes:ByteArray)=MessageDigest.getInstance("SHA-256").digest(bytes).joinToString(""){"%02x".format(it)}
    @Test fun stagedFullAndThumbnailSurviveRepositoryRecreationWithExactImmutableHashes()=runBlocking {
        val full=bytes("full");val thumb=bytes("thumb");val staged=cache().stage(owner,asset,full,thumb).getOrThrow()
        assertEquals("11111111-1111-1111-1111-111111111111/22222222-2222-2222-2222-222222222222/33333333-3333-3333-3333-333333333333.jpg",staged.path)
        assertEquals(hash(full),staged.imageSha256);assertEquals(hash(thumb),staged.thumbnailSha256)
        assertArrayEquals(full,cache().imageData(owner,staged).getOrThrow());assertArrayEquals(thumb,cache().imageData(owner,staged,true).getOrThrow())
    }
    @Test fun stagedObjectCannotOverwriteDifferentBytesAtTheSameImmutableIdentity()=runBlocking {
        val source=cache();val full=bytes("full");val thumb=bytes("thumb");val staged=source.stage(owner,asset,full,thumb).getOrThrow()
        assertTrue(source.stage(owner,asset,thumb,full).isFailure)
        assertArrayEquals(full,source.imageData(owner,staged).getOrThrow());assertArrayEquals(thumb,source.imageData(owner,staged,true).getOrThrow())
    }
    @Test fun anUnlinkedCanceledCandidateCanBeDiscardedWithoutExposingItsBytesAgain()=runBlocking {
        val source=cache();val staged=source.stage(owner,asset,bytes("full"),bytes("thumb")).getOrThrow()
        assertTrue(source.discardCandidate(owner,staged).getOrThrow());assertTrue(cache().imageData(owner,staged).isFailure)
        assertFalse(source.discardCandidate(owner,staged).getOrThrow())
    }
    @Test fun reservingBeforeMetadataSavePreventsALateCancelFromDeletingTheCandidate()=runBlocking {
        val source=cache();val full=bytes("full");val staged=source.stage(owner,asset,full,bytes("thumb")).getOrThrow()
        val ticket=source.reservePublication(owner,staged,null,revision).getOrThrow()
        assertEquals(staged,ticket.candidate);assertEquals(revision,ticket.revision)
        assertFalse(cache().discardCandidate(owner,staged).getOrThrow());assertArrayEquals(full,cache().imageData(owner,staged).getOrThrow())
        assertEquals(ticket,cache().reservePublication(owner,staged,null,revision).getOrThrow())
        assertTrue(source.reservePublication(owner,staged,null,"55555555-5555-5555-5555-555555555555").isFailure)
    }
    @Test fun replacingTheActiveAccountRevokesReadAndDiscardEvenForCachedBytes()=runBlocking {
        val source=cache();val staged=source.stage(owner,asset,bytes("full"),bytes("thumb")).getOrThrow();active=other
        assertTrue(runCatching{source.imageData(owner,staged)}.exceptionOrNull() is CancellationException)
        assertTrue(source.imageData(other,staged).isFailure);assertTrue(source.discardCandidate(other,staged).isFailure)
        active=owner;assertArrayEquals(bytes("full"),source.imageData(owner,staged).getOrThrow())
    }
    @Test fun invalidPreparedJpegReturnsFailureWithoutCreatingAProductImageCandidate()=runBlocking {
        for(full in listOf(byteArrayOf(),byteArrayOf(1,2,3,4),ByteArray(4_000_001))) {
            assertTrue(cache().stage(owner,asset,full,bytes("thumb")).isFailure)
        }
        assertTrue(temporary.root.listFiles().orEmpty().isEmpty())
    }
    @Test fun cancellationInsideTheFinalOwnerCheckCannotPublishAManifest()=runBlocking {
        var checks=0;var target:Deferred<*>?=null
        val source=FileInvestmentProductImageCache(temporary.root,{
            checks++;if(checks==5)target!!.cancel(CancellationException("Last image publication fence"));active
        },{objectId})
        val work=async(start=CoroutineStart.LAZY){source.stage(owner,asset,bytes("full"),bytes("thumb"))};target=work;work.start()
        assertTrue(runCatching{work.await()}.exceptionOrNull() is CancellationException)
        assertEquals(5,checks)
        assertFalse(File(temporary.root,owner.value+"/manifest.json").exists())
        assertTrue(temporary.root.walkTopDown().none{it.isFile && it.extension=="jpg"})
    }
    @Test fun corruptCachedBytesAreHeldRatherThanSilentlyRepairedByStageRetry()=runBlocking {
        val source=cache();val full=bytes("full");val staged=source.stage(owner,asset,full,bytes("thumb")).getOrThrow()
        val file=File(temporary.root,owner.value+"/images/"+asset+"/"+objectId+".jpg")
        val damaged=full.copyOf().apply{this[20]=(this[20].toInt() xor 1).toByte()};file.writeBytes(damaged)
        assertTrue(source.imageData(owner,staged).isFailure);assertTrue(source.stage(owner,asset,full,bytes("thumb")).isFailure)
        assertArrayEquals(damaged,file.readBytes())
    }
    @Test fun unreadableManifestCannotBecomeAnEmptyStoreThatOverwritesExistingFiles()=runBlocking {
        val source=cache();val full=bytes("full");val staged=source.stage(owner,asset,full,bytes("thumb")).getOrThrow()
        val manifest=File(temporary.root,owner.value+"/manifest.json");manifest.writeText("{broken")
        assertTrue(source.imageData(owner,staged).isFailure)
        assertTrue(source.stage(owner,asset,full,bytes("thumb")).isFailure)
        assertEquals("{broken",manifest.readText())
        assertArrayEquals(full,File(temporary.root,owner.value+"/images/"+asset+"/"+objectId+".jpg").readBytes())
    }

    private fun revision(n:Int)="aaaaaaaa-aaaa-4aaa-8aaa-"+n.toString().padStart(12,'0')
    private fun sequenceCache():FileInvestmentProductImageCache {
        var next=1
        return FileInvestmentProductImageCache(temporary.root,{active},{"bbbbbbbb-bbbb-4bbb-8bbb-"+(next++).toString().padStart(12,'0')})
    }
    @Test fun onlyLocallyPublishedPhotosBecomePendingUploads()=runBlocking {
        val source=cache();val image=source.stage(owner,asset,bytes("full"),bytes("thumb")).getOrThrow()
        assertTrue(source.pendingUploads(owner).getOrThrow().isEmpty())
        val pub=source.reservePublication(owner,image,null,revision).getOrThrow()
        assertTrue(source.verifyPublication(owner,pub).getOrThrow());assertTrue(source.pendingUploads(owner).getOrThrow().isEmpty())
        assertTrue(source.markLocalPublished(owner,pub).getOrThrow())
        assertEquals(listOf(image),cache().pendingUploads(owner).getOrThrow())
        assertFalse(source.verifyPublication(owner,pub).getOrThrow());assertTrue(source.verifyPublication(owner,pub,true).getOrThrow())
        assertFalse(source.discardCandidate(owner,image).getOrThrow())
    }
    @Test fun replacementCleanupWaitsForBothObjectUploadAndTheMatchingAssetAcknowledgment()=runBlocking {
        val source=sequenceCache();val a=source.stage(owner,asset,bytes("full"),bytes("thumb")).getOrThrow()
        val first=source.reservePublication(owner,a,null,revision(1)).getOrThrow();source.markLocalPublished(owner,first).getOrThrow();source.markUploadSucceeded(owner,a).getOrThrow();source.acknowledgePublished(owner,first).getOrThrow()
        val b=source.stage(owner,asset,bytes("thumb"),bytes("full")).getOrThrow();val second=source.reservePublication(owner,b,a.path,revision(2)).getOrThrow()
        source.markLocalPublished(owner,second).getOrThrow();assertFalse(source.acknowledgePublished(owner,second).getOrThrow());assertTrue(source.readyDeletions(owner).getOrThrow().isEmpty())
        assertTrue(source.markUploadSucceeded(owner,b).getOrThrow());assertTrue(source.acknowledgePublished(owner,second).getOrThrow())
        assertEquals(listOf(a.path),cache().readyDeletions(owner).getOrThrow());assertArrayEquals(bytes("full"),source.imageData(owner,a).getOrThrow())
        assertTrue(source.markDeletionSucceeded(owner,asset,a.path).getOrThrow());assertTrue(source.imageData(owner,a).isFailure)
        assertArrayEquals(bytes("thumb"),source.imageData(owner,b).getOrThrow());assertTrue(source.readyDeletions(owner).getOrThrow().isEmpty())
        assertTrue(source.acknowledgePublished(owner,second).getOrThrow());assertTrue(source.readyDeletions(owner).getOrThrow().isEmpty())
    }
    @Test fun removingAPhotoPublishesExplicitAbsenceBeforeItsOldObjectCanBeDeleted()=runBlocking {
        val source=cache();val image=source.stage(owner,asset,bytes("full"),bytes("thumb")).getOrThrow()
        val first=source.reservePublication(owner,image,null,revision(1)).getOrThrow();source.markLocalPublished(owner,first).getOrThrow();source.markUploadSucceeded(owner,image).getOrThrow();source.acknowledgePublished(owner,first).getOrThrow()
        val removal=source.reserveRemoval(owner,asset,image.path,revision(2)).getOrThrow();assertNull(removal.path)
        assertTrue(source.verifyPublication(owner,removal).getOrThrow());assertTrue(source.readyDeletions(owner).getOrThrow().isEmpty())
        source.markLocalPublished(owner,removal).getOrThrow();assertTrue(source.pendingUploads(owner).getOrThrow().isEmpty());assertFalse(source.discardCandidate(owner,image).getOrThrow())
        source.acknowledgePublished(owner,removal).getOrThrow();assertEquals(listOf(image.path),source.readyDeletions(owner).getOrThrow())
        assertTrue(source.markDeletionSucceeded(owner,asset,image.path).getOrThrow())
    }
    @Test fun lateAssetAcknowledgmentCannotReleaseANewerPendingReplacement()=runBlocking {
        val source=sequenceCache();val a=source.stage(owner,asset,bytes("full"),bytes("thumb")).getOrThrow()
        val first=source.reservePublication(owner,a,null,revision(1)).getOrThrow();source.markLocalPublished(owner,first).getOrThrow();source.markUploadSucceeded(owner,a).getOrThrow();source.acknowledgePublished(owner,first).getOrThrow()
        val b=source.stage(owner,asset,bytes("thumb"),bytes("full")).getOrThrow();val second=source.reservePublication(owner,b,a.path,revision(2)).getOrThrow();source.markLocalPublished(owner,second).getOrThrow();source.markUploadSucceeded(owner,b).getOrThrow()
        val c=source.stage(owner,asset,bytes("full"),bytes("thumb")).getOrThrow();val third=source.reservePublication(owner,c,b.path,revision(3)).getOrThrow();source.markLocalPublished(owner,third).getOrThrow()
        assertFalse(source.acknowledgePublished(owner,second).getOrThrow());assertFalse(source.markLocalPublished(owner,second).getOrThrow())
        assertTrue(source.readyDeletions(owner).getOrThrow().isEmpty());assertEquals(listOf(c),source.pendingUploads(owner).getOrThrow())
        source.markUploadSucceeded(owner,c).getOrThrow();source.acknowledgePublished(owner,third).getOrThrow()
        assertEquals(setOf(a.path,b.path),source.readyDeletions(owner).getOrThrow().toSet());assertFalse(source.markDeletionSucceeded(owner,asset,c.path).getOrThrow())
    }

    @Test fun remotePhotoCacheSurvivesRecreationWithoutBecomingAnUploadOrDraftCandidate()=runBlocking {
        val path=owner.value+"/"+asset+"/"+objectId+".jpg"
        cache().cacheDownloaded(owner,asset,path,bytes("full"),bytes("thumb")).getOrThrow()
        assertArrayEquals(bytes("thumb"),cache().cachedImageData(owner,asset,path).getOrThrow())
        assertArrayEquals(bytes("full"),cache().cachedImageData(owner,asset,path,false).getOrThrow())
        assertTrue(cache().pendingUploads(owner).getOrThrow().isEmpty())
        assertTrue(cache().readyDeletions(owner).getOrThrow().isEmpty())
        val remote=InvestmentProductImageCandidate(owner.value,asset,path,hash(bytes("full")),hash(bytes("thumb")))
        assertTrue(cache().reservePublication(owner,remote,null,revision).isFailure)
    }
    @Test fun remoteCacheNeverOverwritesAnExistingImmutableLocalCandidate()=runBlocking {
        val source=cache();val staged=source.stage(owner,asset,bytes("full"),bytes("thumb")).getOrThrow()
        source.cacheDownloaded(owner,asset,staged.path,bytes("full"),bytes("thumb")).getOrThrow()
        assertTrue(source.cacheDownloaded(owner,asset,staged.path,bytes("thumb"),bytes("full")).isFailure)
        assertArrayEquals(bytes("full"),source.imageData(owner,staged).getOrThrow())
        assertTrue(source.discardCandidate(owner,staged).getOrThrow())
    }
    @Test fun ownerOrAssetMismatchRevokesAPathReadEvenWhenThePrivateFileExists()=runBlocking {
        val source=cache();val staged=source.stage(owner,asset,bytes("full"),bytes("thumb")).getOrThrow()
        assertArrayEquals(bytes("thumb"),source.cachedImageData(owner,asset,staged.path).getOrThrow())
        assertTrue(runCatching{source.cachedImageData(other,asset,staged.path)}.exceptionOrNull() is CancellationException)
        assertTrue(source.cachedImageData(owner,objectId,staged.path).isFailure)
        active=other
        assertTrue(runCatching{source.cachedImageData(owner,asset,staged.path)}.exceptionOrNull() is CancellationException)
    }

    @Test fun latestAcknowledgementCleansSupersededCandidatesAcrossARemoteReferenceDiscontinuity()=runBlocking {
        var serial=10
        val source=FileInvestmentProductImageCache(temporary.root,{active},{"%08d-3333-3333-3333-333333333333".format(serial++)})
        val b=source.stage(owner,asset,bytes("full"),bytes("thumb")).getOrThrow()
        val first=source.reservePublication(owner,b,null,revision).getOrThrow()
        assertTrue(source.markLocalPublished(owner,first).getOrThrow());assertTrue(source.markUploadSucceeded(owner,b).getOrThrow())
        val remote=InvestmentProductImagePath.create(owner,asset,"66666666-6666-6666-6666-666666666666").value
        val d=source.stage(owner,asset,bytes("full"),bytes("thumb")).getOrThrow()
        val latest=source.reservePublication(owner,d,remote,"77777777-7777-7777-7777-777777777777").getOrThrow()
        assertEquals(latest,source.reconcileCurrentReference(CurrentAssetImageReferenceProof(owner,asset,d.path,true,latest)).getOrThrow().first)
        val future=source.stage(owner,asset,bytes("full"),bytes("thumb")).getOrThrow()
        source.reservePublication(owner,future,d.path,"88888888-8888-8888-8888-888888888888").getOrThrow()
        assertTrue(source.markUploadSucceeded(owner,d).getOrThrow());assertTrue(source.acknowledgePublished(owner,latest).getOrThrow())
        assertEquals(setOf(b.path,remote),source.readyDeletions(owner).getOrThrow().toSet())
        assertFalse(source.markDeletionSucceeded(owner,asset,d.path).getOrThrow())
        assertFalse(source.markDeletionSucceeded(owner,asset,future.path).getOrThrow())
        assertArrayEquals(bytes("full"),source.imageData(owner,future).getOrThrow())
    }

}
