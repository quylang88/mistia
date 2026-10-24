package vn.com.quyln.mistia.core.model

import org.junit.Assert.*
import org.junit.Test

class InvestmentProductImagesTest {
    private val owner=UserId("11111111-1111-1111-1111-111111111111")
    private val asset="22222222-2222-2222-2222-222222222222"
    private val objectId="abcdef12-3456-4789-abcd-1234567890ab"
    private val path="11111111-1111-1111-1111-111111111111/22222222-2222-2222-2222-222222222222/abcdef12-3456-4789-abcd-1234567890ab.jpg"
    @Test fun newObjectUsesTheCanonicalPrivateOwnerAssetAndImmutableJpegIdentity() {
        assertEquals(path,InvestmentProductImagePath.create(owner,asset,objectId).value)
    }
    @Test fun aStoredCanonicalPrivatePathCanBeReadOnlyForItsExpectedOwnerAndAsset() {
        assertEquals(path,InvestmentProductImagePath.parse(owner,asset,path).value)
        for((expectedOwner,expectedAsset) in listOf(UserId("33333333-3333-3333-3333-333333333333") to asset,owner to "44444444-4444-4444-4444-444444444444")) {
            assertTrue(runCatching{InvestmentProductImagePath.parse(expectedOwner,expectedAsset,path)}.exceptionOrNull() is IllegalArgumentException)
        }
    }
    @Test fun urlsAbsolutePathsTraversalEncodedSeparatorsAndMalformedObjectNamesAreRejected() {
        for(raw in listOf("/"+path,"https://example.com/"+path,path.replace("/","%2F"),path.replace(asset,".."),path.replace(objectId,"../"+objectId),
            path.replace(".jpg",".png"),path.replace(".jpg",".JPG"),path+"?token=private",path+"/extra",path.replace(objectId,"bad"),path.replace(objectId,objectId.uppercase()),path+" ","")) {
            assertTrue("Unsafe private image path: "+raw,runCatching{InvestmentProductImagePath.parse(owner,asset,raw)}.exceptionOrNull() is IllegalArgumentException)
        }
    }
    @Test fun creationRejectsNoncanonicalOwnerAssetOrObjectInsteadOfNormalizingAnotherIdentity() {
        for((o,a,id) in listOf(Triple(UserId("bad"),asset,objectId),Triple(owner,"../"+asset,objectId),Triple(owner,asset,objectId+".jpg"),Triple(owner,asset,objectId.uppercase()))) {
            assertTrue(runCatching{InvestmentProductImagePath.create(o,a,id)}.exceptionOrNull() is IllegalArgumentException)
        }
    }
}
