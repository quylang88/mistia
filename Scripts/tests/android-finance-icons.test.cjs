'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {readFinanceIconRegistry}=require('../generate-android-finance-icons.cjs');
// These literals independently model the source registry contract, not the implementation's helpers.
const source=`
private static let explicitDescriptors: [String: MistiaFinanceIconDescriptor] = [
 "mistia.plan.loan": descriptor(token: "mistia.plan.loan", fallbackSystemName: "building.columns.fill", baseHex: "#5B7BFF", group: .planning, badgeSystemName: "percent"),
 "category.wifi": descriptor(token: "category.wifi", fallbackSystemName: "wrong", baseHex: "#FFFFFF", group: .planning, badgeSystemName: nil)
]
private static let fluentAssetNamesByToken: [String: String] = {
 var mapping: [String: String] = [:]
 assign("first_art", ["category.wifi", "mistia.plan.loan"])
 assign("wifi_color", ["category.wifi"])
 assign("baby_filled", ["category.baby"])
 return mapping
}()
private static func option(token: String) {}
private static func fluentAssetName(for token: String, group: MistiaFinanceIconGroup) -> String? {
 if let assetName = fluentAssetNamesByToken[token] { return assetName }
 switch group {
 case .home: return "home_color"
 case .family: return "family_color"
 case .planning: return "calendar_color"
 }
}
static func assetUsesTemplate(_ assetName: String) -> Bool {
 assetName.hasSuffix("_filled") || assetName.hasSuffix("_regular")
}
private static func badge(for group: MistiaFinanceIconGroup) {}
`;
const categories=[{id:'home',icon:'category.wifi',color:'#123456',group:'home',fallbackIcon:'wifi',active:true,
 children:[{id:'old',icon:'category.old',color:'#345678',group:'home',fallbackIcon:'house.fill',active:false},
 {id:'baby',icon:'category.baby',color:'#FF6D8A',group:'family',fallbackIcon:'fork.knife',active:true}]}];
test('registered category uses final ordered asset assignment and category descriptor precedence',()=>{
 const row=readFinanceIconRegistry(source,categories).get('category.wifi');
 assert.deepEqual(row,{assetName:'wifi_color',primaryHex:'#123456',template:false});
});
test('inactive legacy category remains registered through its source group fallback',()=>{
 assert.deepEqual(readFinanceIconRegistry(source,categories).get('category.old'),{assetName:'home_color',primaryHex:'#345678',template:false});
});
test('explicit planning token resolves its own artwork without registering unknown tokens',()=>{
 const rows=readFinanceIconRegistry(source,categories);
 assert.deepEqual(rows.get('mistia.plan.loan'),{assetName:'first_art',primaryHex:'#5B7BFF',template:false});
 assert.equal(rows.get('future.unknown'),undefined);assert.equal(rows.size,4);
});
test('template artwork keeps the descriptor color and template designation',()=>{
 assert.deepEqual(readFinanceIconRegistry(source,categories).get('category.baby'),{assetName:'baby_filled',primaryHex:'#FF6D8A',template:true});
});
test('unreadable source structures and unknown group cannot silently produce a partial registry',()=>{
 assert.throws(()=>readFinanceIconRegistry('',categories));
 assert.throws(()=>readFinanceIconRegistry(source,[{...categories[0],group:'future'}]));
 assert.throws(()=>readFinanceIconRegistry(source,[{...categories[0],color:'not-hex'}]));
 assert.throws(()=>readFinanceIconRegistry(source,{}));
});
test('source template policy drift fails explicitly rather than silently recoloring the wrong artwork',()=>{
 assert.throws(()=>readFinanceIconRegistry(source.replace('hasSuffix("_regular")','hasSuffix("_newStyle")'),categories));
});

const fs=require('node:fs');const os=require('node:os');const path=require('node:path');const {spawnSync}=require('node:child_process');
const script=path.resolve(__dirname,'../generate-android-finance-icons.cjs');
function fixture() {
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'mistia-icons-'));
 for(const name of ['Mistia/Core/UI','Mistia/Shared/CoreLogic','Mistia/Assets.xcassets']) fs.mkdirSync(path.join(root,name),{recursive:true});
 fs.writeFileSync(path.join(root,'Mistia/Core/UI/MistiaFinanceIcons.swift'),source);
 fs.writeFileSync(path.join(root,'Mistia/Shared/CoreLogic/MistiaSystemCategories.json'),JSON.stringify(categories));
 for(const name of ['first_art','wifi_color','baby_filled','home_color']) {
  const dir=path.join(root,'Mistia/Assets.xcassets',`${name}.imageset`);fs.mkdirSync(dir);
  fs.writeFileSync(path.join(dir,'Contents.json'),JSON.stringify({images:[{filename:`${name}.svg`,idiom:'universal'}]}));
  fs.writeFileSync(path.join(dir,`${name}.svg`),'<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><circle cx="12" cy="12" r="8" fill="#ff0000"/></svg>');
 }
 return root;
}
function cli(root,...args) {return spawnSync(process.execPath,[script,'--root',root,...args],{encoding:'utf8'});}
const output=(root,name)=>path.join(root,'android/core/designsystem/src/main/res/drawable-nodpi',`finance_art_${name}.png`);
test('generation packages original transparent artwork and a catalog that actually resolves each source token',async()=>{
 const root=fixture();try {
  const generated=cli(root);assert.equal(generated.status,0,generated.stderr);
  assert.ok(fs.existsSync(output(root,'wifi_color')),'Registered original artwork must be generated');
  const sharp=require('sharp');const {data,info}=await sharp(output(root,'wifi_color')).raw().toBuffer({resolveWithObject:true});
  assert.equal(info.width,256);assert.equal(info.height,256);assert.equal(info.channels,4);
  assert.equal(data[3],0,'Outside original shape must stay transparent');
  const center=(128*256+128)*4;assert.deepEqual([...data.subarray(center,center+4)],[255,0,0,255]);
  const catalog=fs.readFileSync(path.join(root,'android/core/designsystem/src/main/java/vn/com/quyln/mistia/core/designsystem/FinanceIconAssets.generated.kt'),'utf8');
  assert.ok(catalog.includes('"category.wifi" to FinanceIconAsset("wifi_color", R.drawable.finance_art_wifi_color, "#123456", false)'));
  assert.equal(cli(root,'--check').status,0);
 } finally {fs.rmSync(root,{recursive:true,force:true});}
});
test('missing original artwork fails before replacing existing outputs',()=>{
 const root=fixture();try {
  const target=output(root,'old');fs.mkdirSync(path.dirname(target),{recursive:true});fs.writeFileSync(target,'keep');
  fs.rmSync(path.join(root,'Mistia/Assets.xcassets/wifi_color.imageset'),{recursive:true});
  assert.notEqual(cli(root).status,0,'Missing original source cannot silently generate a partial registry');
  assert.equal(fs.readFileSync(target,'utf8'),'keep');
 } finally {fs.rmSync(root,{recursive:true,force:true});}
});
test('check catches source artwork drift and missing packaged PNG without mutating generated files',()=>{
 const root=fixture();try {
  assert.equal(cli(root).status,0);
  const original=output(root,'wifi_color');assert.ok(fs.existsSync(original),'Generated resource missing');
  const before=fs.readFileSync(original);
  const svg=path.join(root,'Mistia/Assets.xcassets/wifi_color.imageset/wifi_color.svg');fs.appendFileSync(svg,'\n<!-- source update -->');
  assert.notEqual(cli(root,'--check').status,0);assert.deepEqual(fs.readFileSync(original),before);
  assert.equal(cli(root).status,0);fs.unlinkSync(original);
  assert.notEqual(cli(root,'--check').status,0);assert.equal(fs.existsSync(original),false);
 } finally {fs.rmSync(root,{recursive:true,force:true});}
});
