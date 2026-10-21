'use strict';
const assert=require('node:assert/strict');

function block(source,start,end) {
 const from=source.indexOf(start);assert.ok(from>=0,`Missing Swift registry section ${start}`);
 const to=source.indexOf(end,from+start.length);assert.ok(to>from,`Missing Swift registry boundary ${end}`);
 return source.slice(from+start.length,to);
}
function strings(body) {
 const values=[...body.matchAll(/"([^"\\]*)"/g)].map(match=>match[1]);
 assert.ok(body.replace(/"[^"\\]*"/g,'').replace(/[\s,]/g,'')==='','Unsupported Swift token list');
 return values;
}

/** Source descriptors match MistiaFinanceIconRegistry, including inactive historical categories. */
function readFinanceIconRegistry(swift,categories) {
 assert.equal(typeof swift,'string');assert.ok(Array.isArray(categories),'Category catalog must be an array');
 const explicitBody=block(swift,'private static let explicitDescriptors:','private static let fluentAssetNamesByToken:');
 const assignmentsBody=block(swift,'private static let fluentAssetNamesByToken:','private static func option(');
 const fallbackBody=block(swift,'private static func fluentAssetName(','static func assetUsesTemplate(');
 const templateBody=block(swift,'static func assetUsesTemplate(','private static func badge(');
 const suffixes=[...templateBody.matchAll(/hasSuffix\("([^"]+)"\)/g)].map(match=>match[1]);
 assert.deepEqual(suffixes,['_filled','_regular'],'Unsupported Swift template policy');
 const fallback=new Map([...fallbackBody.matchAll(/case\s+\.(\w+):\s*return\s+"([^"]+)"/g)].map(match=>[match[1],match[2]]));
 assert.ok(fallback.size>0,'Missing group fallback assets');
 const explicit=new Map();
 const pattern=/"([^"]+)":\s*descriptor\(token:\s*"([^"]+)",\s*fallbackSystemName:\s*"([^"]+)",\s*baseHex:\s*"([^"]+)",\s*group:\s*\.(\w+),\s*badgeSystemName:\s*(?:"[^"]+"|nil)\)/g;
 for(const match of explicitBody.matchAll(pattern)) {
  assert.equal(match[1],match[2],'Explicit descriptor identity mismatch');assert.ok(!explicit.has(match[1]),'Duplicate explicit token');
  explicit.set(match[1],{color:match[4],group:match[5]});
 }
 assert.ok(explicit.size>0,'No explicit finance descriptors');
 assert.equal([...explicitBody.matchAll(/descriptor\(/g)].length,explicit.size,'Unsupported explicit descriptor syntax');
 const assetByToken=new Map();
 const assignments=[...assignmentsBody.matchAll(/assign\("([^"]+)",\s*\[([\s\S]*?)\]\)/g)];
 assert.ok(assignments.length>0,'No source artwork assignments');
 assert.equal([...assignmentsBody.matchAll(/\bassign\("/g)].length,assignments.length,'Unsupported asset assignment syntax');
 for(const match of assignments) for(const token of strings(match[2])) assetByToken.set(token,match[1]);
 const registered=new Map(explicit);
 for(const parent of categories) {
  assert.ok(parent && typeof parent==='object' && !Array.isArray(parent),'Invalid category');
  assert.ok(parent.children===undefined || Array.isArray(parent.children),'Invalid category children');
  for(const row of [parent,...(parent.children??[])]) {
   assert.ok(row && typeof row.icon==='string' && row.icon.length>0,'Missing category icon');
   // Source registry gives category descriptors precedence over explicit descriptors.
   registered.set(row.icon,{color:row.color,group:row.group});
  }
 }
 const result=new Map();
 for(const [token,row] of [...registered].sort(([a],[b])=>a<b?-1:a>b?1:0)) {
  assert.match(row.color??'',/^#[0-9A-Fa-f]{6}$/,'Invalid descriptor primary color');
  assert.ok(fallback.has(row.group),`Unknown finance icon group ${row.group}`);
  const assetName=assetByToken.get(token)??fallback.get(row.group);
  assert.match(assetName,/^[a-z][a-z0-9_]*$/,'Invalid drawable asset name');
  result.set(token,{assetName,primaryHex:row.color,template:suffixes.some(suffix=>assetName.endsWith(suffix))});
 }
 return result;
}
module.exports={readFinanceIconRegistry};

const fs=require('node:fs/promises');
const path=require('node:path');
const crypto=require('node:crypto');
const SOURCE_REGISTRY='Mistia/Core/UI/MistiaFinanceIcons.swift';
const SOURCE_CATEGORIES='Mistia/Shared/CoreLogic/MistiaSystemCategories.json';
const DRAWABLES='android/core/designsystem/src/main/res/drawable-nodpi';
const CATALOG='android/core/designsystem/src/main/java/vn/com/quyln/mistia/core/designsystem/FinanceIconAssets.generated.kt';
const MANIFEST='docs/android/finance-icon-assets.generated.json';
const sha=data=>crypto.createHash('sha256').update(data).digest('hex');
function kotlinCatalog(registry) {
 return '// Generated from the shared Swift finance registry and source artwork. Do not edit.\n'+
  'package vn.com.quyln.mistia.core.designsystem\n\n'+
  'internal val generatedFinanceIconAssets:Map<String,FinanceIconAsset> = mapOf(\n'+
  [...registry].map(([token,row])=>`    ${JSON.stringify(token)} to FinanceIconAsset(${JSON.stringify(row.assetName)}, R.drawable.finance_art_${row.assetName}, ${JSON.stringify(row.primaryHex)}, ${row.template}),`).join('\n')+'\n)\n';
}
async function inputs(root) {
 const swift=await fs.readFile(path.join(root,SOURCE_REGISTRY));
 const categories=await fs.readFile(path.join(root,SOURCE_CATEGORIES));
 const registry=readFinanceIconRegistry(swift.toString(),JSON.parse(categories));
 assert.ok(registry.size>0,'No registered finance icons');
 const originals=[];
 for(const name of [...new Set([...registry.values()].map(row=>row.assetName))].sort()) {
  const folder=`Mistia/Assets.xcassets/${name}.imageset`;
  const contents=JSON.parse(await fs.readFile(path.join(root,folder,'Contents.json'),'utf8'));
  const files=[...new Set(contents.images?.map(row=>row.filename).filter(Boolean))];
  assert.equal(files.length,1,`Expected one original artwork for ${name}`);
  assert.ok(path.basename(files[0])===files[0] && files[0].endsWith('.svg'),`Unsupported original artwork ${files[0]}`);
  const sourcePath=`${folder}/${files[0]}`;
  const source=await fs.readFile(path.join(root,sourcePath));
  originals.push({assetName:name,sourcePath,sourceSHA256:sha(source),resourcePath:`${DRAWABLES}/finance_art_${name}.png`,source});
 }
 return {registry,originals,sourceHashes:{[SOURCE_REGISTRY]:sha(swift),[SOURCE_CATEGORIES]:sha(categories)}};
}
async function generate(root,check) {
 const {registry,originals,sourceHashes}=await inputs(root);
 const catalog=kotlinCatalog(registry);
 const descriptorRows=[...registry].map(([token,row])=>({token,...row}));
 if(check) {
  const manifest=JSON.parse(await fs.readFile(path.join(root,MANIFEST),'utf8'));
  assert.equal(manifest.formatVersion,1,'Unsupported generated manifest');
  assert.equal(manifest.pixelSize,256);assert.deepEqual(manifest.sources,sourceHashes,'Shared source changed; regenerate finance icons');
  assert.deepEqual(manifest.descriptors,descriptorRows,'Generated descriptor selection changed');
  assert.equal(await fs.readFile(path.join(root,CATALOG),'utf8'),catalog,'Generated Kotlin catalog changed');
  assert.equal(manifest.catalogSHA256,sha(catalog),'Generated catalog hash changed');
  assert.equal(manifest.assets.length,originals.length,'Partial generated artwork manifest');
  for(let i=0;i<originals.length;i++) {
   const {source,...original}=originals[i];const entry=manifest.assets[i];
   assert.deepEqual({...entry,pngSHA256:undefined},{...original,pngSHA256:undefined},'Original artwork changed; regenerate finance icons');
   const png=await fs.readFile(path.join(root,original.resourcePath));
   assert.equal(sha(png),entry.pngSHA256,`Packaged artwork changed: ${original.assetName}`);
   assert.equal(png.readUInt32BE(16),256);assert.equal(png.readUInt32BE(20),256);assert.equal(png[25],6,'Expected original transparent RGBA artwork');
  }
  const existing=(await fs.readdir(path.join(root,DRAWABLES))).filter(name=>name.startsWith('finance_art_')).sort();
  assert.deepEqual(existing,originals.map(row=>path.basename(row.resourcePath)).sort(),'Stale packaged artwork');
 } else {
  const sharp=require('sharp');
  // Validate every source before writing; keep existing artifacts intact on missing/unsupported inputs.
  const rendered=[];
  for(const original of originals) {
   const png=await sharp(original.source,{density:768}).resize(256,256,{fit:'contain',background:{r:0,g:0,b:0,alpha:0}})
    .ensureAlpha().png({compressionLevel:9,adaptiveFiltering:false}).toBuffer();
   const {source,...entry}=original;rendered.push({entry:{...entry,pngSHA256:sha(png)},png});
  }
  for(const row of rendered) {await fs.mkdir(path.dirname(path.join(root,row.entry.resourcePath)),{recursive:true});await fs.writeFile(path.join(root,row.entry.resourcePath),row.png);}
  const retained=new Set(originals.map(row=>path.basename(row.resourcePath)));
  for(const name of await fs.readdir(path.join(root,DRAWABLES))) if(name.startsWith('finance_art_') && !retained.has(name)) await fs.unlink(path.join(root,DRAWABLES,name));
  await fs.mkdir(path.dirname(path.join(root,CATALOG)),{recursive:true});await fs.writeFile(path.join(root,CATALOG),catalog);
  const manifest={formatVersion:1,pixelSize:256,sources:sourceHashes,catalogSHA256:sha(catalog),descriptors:descriptorRows,assets:rendered.map(row=>row.entry)};
  await fs.mkdir(path.dirname(path.join(root,MANIFEST)),{recursive:true});await fs.writeFile(path.join(root,MANIFEST),JSON.stringify(manifest,null,2)+'\n');
 }
 console.log(`Finance icon ${check?'check':'generation'} passed (${registry.size} registered tokens, ${originals.length} original artworks).`);
}
if(require.main===module) {
 const args=process.argv.slice(2);let root=path.resolve(__dirname,'..');let check=false;
 for(let i=0;i<args.length;i++) {
  if(args[i]==='--check') check=true;
  else if(args[i]==='--root' && args[i+1]) root=path.resolve(args[++i]);
  else throw new Error(`Unknown argument ${args[i]}`);
 }
 generate(root,check).catch(error=>{console.error(error.message);process.exitCode=1;});
}
