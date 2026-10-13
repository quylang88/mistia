package vn.com.quyln.mistia.core.model

import org.junit.Assert.*
import org.junit.Test

class SystemCategoryCatalogTest {
    private val source=javaClass.classLoader!!.getResourceAsStream("MistiaSystemCategories.json")!!.bufferedReader().use {it.readText()}
    @Test fun `real shared catalog preserves all legacy metadata and only activates current hierarchy`() {
        val catalog=SystemCategoryCatalog.parse(source)
        assertEquals(161,catalog.definitions.size)
        assertEquals(147,catalog.activeDefinitions.size)
        assertEquals(20,catalog.activeDefinitions.count {it.parentKey==null})
        assertEquals(127,catalog.activeDefinitions.count {it.parentKey!=null})
        val byKey=catalog.definitions.associateBy {it.key}
        catalog.activeDefinitions.filter {it.parentKey!=null}.forEach {child ->
            val parent=byKey[child.parentKey]!!
            assertTrue(parent.isActive);assertEquals(parent.kind,child.kind)
        }
        assertFalse(byKey.getValue("food").isActive)
    }
    @Test fun `catalog default translations icons aliases and sibling sort match Swift seed`() {
        val catalog=SystemCategoryCatalog.parse(source)
        val grocery=catalog.definitions.single {it.key=="grocery"}
        assertEquals("Đi chợ",grocery.name);assertEquals("Groceries",grocery.nameEnglish);assertEquals("食料品",grocery.nameJapanese)
        assertEquals("parent_expense_food",grocery.parentKey);assertEquals("mistia.category.expense.food.grocery",grocery.iconSymbolName)
        assertEquals("#FF8A4C",grocery.iconColorHex);assertTrue("Đi chợ / thực phẩm" in grocery.knownDefaultNames)
        catalog.activeDefinitions.filter {it.parentKey!=null}.groupBy {it.parentKey}.values.forEach {siblings ->
            assertEquals(siblings.indices.toList(),siblings.map {it.sortOrder})
        }
    }
    @Test fun `stable UUID canonical and owner cloud identities match cross platform golden vectors`() {
        assertEquals("50cd7bc4-edb6-5bb6-9c0d-0edfa0522601",SystemCategoryIdentity.canonicalId("rent"))
        assertEquals("95c65048-8f44-558d-9ad1-1a43cdec5483",SystemCategoryIdentity.canonicalId("internet"))
        assertEquals("d872b8af-d28a-5b90-8822-839dfa097b23",SystemCategoryIdentity.canonicalId("loan_repayment"))
        val owner=UserId("11111111-1111-1111-1111-111111111111")
        assertEquals("b37f0c1b-b967-5f0a-ba59-0e795d0a4d75",SystemCategoryIdentity.cloudId("rent",owner))
        assertEquals("d1021d10-3990-54d4-bd3a-9cb7503758b9",SystemCategoryIdentity.cloudId("internet",owner))
        assertEquals("7fa4dc60-3397-57ba-890a-e926a5f1927e",SystemCategoryIdentity.familyId("d1021d10-3990-54d4-bd3a-9cb7503758b9",owner))
        assertNotEquals(SystemCategoryIdentity.cloudId("rent",owner),SystemCategoryIdentity.cloudId("rent",UserId("22222222-2222-2222-2222-222222222222")))
        val upper=UserId("AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")
        assertEquals(SystemCategoryIdentity.cloudId("rent",upper),SystemCategoryIdentity.cloudId("rent",UserId(upper.value.lowercase())))
        assertThrows(IllegalArgumentException::class.java) {SystemCategoryIdentity.cloudId("rent",UserId("1-1-1-1-1"))}
        assertThrows(IllegalArgumentException::class.java) {SystemCategoryIdentity.familyId("1-1-1-1-1",owner)}
    }
    @Test fun `malformed registry rows cannot silently seed a partial invalid hierarchy`() {
        assertThrows(IllegalArgumentException::class.java) {SystemCategoryCatalog.parse(source.replaceFirst("\"kind\" : \"expense\"","\"kind\" : \"invalid\""))}
        assertThrows(IllegalArgumentException::class.java) {SystemCategoryCatalog.parse(source.replaceFirst("\"id\" : \"parent_expense_food\"","\"id\" : \"grocery\""))}
    }
    @Test fun `every untouched active seed classifies with its owner and actual parent`() {
        val catalog=SystemCategoryCatalog.parse(source)
        val owner=UserId("11111111-1111-1111-1111-111111111111")
        val rows=catalog.activeDefinitions.associate {definition -> definition.key to definition.seedRecord(owner,
            definition.parentKey?.let {SystemCategoryIdentity.cloudId(it,owner)},"33333333-3333-3333-3333-333333333333","2026-10-13T00:00:00Z")}
        rows.values.forEach {row -> assertTrue(row.isUntouchedSystemCategorySeed(catalog,row.systemKey?.let {key -> catalog.definitions.single {it.key==key}.parentKey}?.let(rows::get)))}
        val rent=rows.getValue("rent")
        val parent=rows[rent.parentCategoryId?.let {id -> rows.values.single {it.id==id}.systemKey}]
        listOf(rent.copy(name="User edit"),rent.copy(isFavorite=true),rent.copy(syncVersion=1),rent.copy(isArchived=true),
            rent.copy(deletedAt=rent.updatedAt),rent.copy(updatedAt="2026-10-13T00:00:01Z"),rent.copy(nameEnglish="Custom")
        ).forEach {assertFalse(it.isUntouchedSystemCategorySeed(catalog,parent))}
    }
    @Test fun `seed classifier accepts legacy system parent identity but rejects unrelated parent`() {
        val catalog=SystemCategoryCatalog.parse(source)
        val owner=UserId("11111111-1111-1111-1111-111111111111")
        val definition=catalog.definitions.single {it.key=="rent"}
        val parent=catalog.definitions.single {it.key==definition.parentKey}.seedRecord(owner,null,"33333333-3333-3333-3333-333333333333","2026-10-13T00:00:00Z")
            .copy(id="44444444-4444-4444-4444-444444444444",name="Custom parent",syncVersion=9)
        val child=definition.seedRecord(owner,parent.id,"33333333-3333-3333-3333-333333333333","2026-10-13T00:00:00Z")
        assertTrue(child.isUntouchedSystemCategorySeed(catalog,parent))
        assertFalse(child.isUntouchedSystemCategorySeed(catalog,parent.copy(systemKey="other_parent")))
        assertFalse(child.isUntouchedSystemCategorySeed(catalog,parent.copy(ownerUserId="22222222-2222-2222-2222-222222222222")))
        assertFalse(child.isUntouchedSystemCategorySeed(catalog,null))
    }
}
