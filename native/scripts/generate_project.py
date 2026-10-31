#!/usr/bin/env python3
"""Generate the Xcode project, pinned local Apple TV package and app icons."""
from pathlib import Path
import hashlib,json,plistlib,math
from PIL import Image,ImageDraw,ImageFilter
ROOT=Path(__file__).resolve().parents[1]
objects={}
def uid(name):return hashlib.sha1(name.encode()).hexdigest()[:24].upper()
def add(identifier,isa,**fields):
 key=uid(identifier);objects[key]={'isa':isa,**fields};return key
def config_list(name,settings):
 configs=[]
 for mode in ['Debug','Release']:
  specific={**settings,'SWIFT_OPTIMIZATION_LEVEL':'-Onone' if mode=='Debug' else '-O','DEBUG_INFORMATION_FORMAT':'dwarf' if mode=='Debug' else 'dwarf-with-dsym'}
  if mode=='Debug':
   specific['SWIFT_ACTIVE_COMPILATION_CONDITIONS']='DEBUG'
   specific['ONLY_ACTIVE_ARCH']='YES'
   if name in ['macOS','iOS']:
    specific['PRODUCT_BUNDLE_IDENTIFIER']=settings['PRODUCT_BUNDLE_IDENTIFIER']+'.debug'
    specific['APP_DISPLAY_NAME']='TV Glow Dev'
  if mode=='Release' and name=='macOS':specific['CODE_SIGN_INJECT_BASE_ENTITLEMENTS']='NO'
  configs.append(add(name+mode,'XCBuildConfiguration',name=mode,buildSettings=specific))
 return add(name+'configs','XCConfigurationList',buildConfigurations=configs,defaultConfigurationIsVisible=0,defaultConfigurationName='Release')
swifts=sorted((ROOT/'TVGlow').rglob('*.swift'))
refs={p:add(str(p.relative_to(ROOT)),'PBXFileReference',lastKnownFileType='sourcecode.swift',path=str(p.relative_to(ROOT/'TVGlow')),sourceTree='<group>') for p in swifts}
assets=add('assets','PBXFileReference',lastKnownFileType='folder.assetcatalog',path='Resources/Assets.xcassets',sourceTree='<group>')
resources=[]
for filename,kind in [('WebOSManifest.json','text.json'),('WebOS-LICENSE.txt','text')]:
 resources.append(add(filename,'PBXFileReference',lastKnownFileType=kind,path='Resources/'+filename,sourceTree='<group>'))
appgroup=add('appgroup','PBXGroup',path='TVGlow',sourceTree='<group>',children=list(refs.values())+[assets]+resources)
testrefs=[add('testfile'+p.name,'PBXFileReference',lastKnownFileType='sourcecode.swift',path=p.name,sourceTree='<group>') for p in sorted((ROOT/'TVGlowTests').glob('*.swift'))]
testgroup=add('testgroup','PBXGroup',path='TVGlowTests',sourceTree='<group>',children=testrefs)
products=[];targets=[]
atv_package=add('atv-package','XCLocalSwiftPackageReference',relativePath='Vendor/ItsytvCore')
base={'SWIFT_VERSION':'5.0','MACOSX_DEPLOYMENT_TARGET':'14.0','IPHONEOS_DEPLOYMENT_TARGET':'17.0','CLANG_ENABLE_MODULES':'YES','CLANG_ENABLE_OBJC_ARC':'YES','ENABLE_TESTABILITY':'YES','GENERATE_INFOPLIST_FILE':'NO','INFOPLIST_FILE':'TVGlow/Config/Info.plist','CURRENT_PROJECT_VERSION':'1','MARKETING_VERSION':'1.0','PRODUCT_NAME':'TV Glow','APP_DISPLAY_NAME':'TV Glow','PRODUCT_MODULE_NAME':'TVGlow','ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon','CODE_SIGN_STYLE':'Automatic','SWIFT_EMIT_LOC_STRINGS':'YES','LD_RUNPATH_SEARCH_PATHS':['$(inherited)','@executable_path/../Frameworks','@executable_path/Frameworks']}
for platform in ['macOS','iOS','Tests']:
 is_test=platform=='Tests';is_mac=platform!='iOS';name='TVGlowTests' if is_test else 'TV Glow '+platform
 product=add(platform+'product','PBXFileReference',explicitFileType='wrapper.cfbundle' if is_test else 'wrapper.application',includeInIndex=0,path='TVGlowTests.xctest' if is_test else 'TV Glow.app',sourceTree='BUILT_PRODUCTS_DIR');products.append(product)
 source_refs=[ref for p,ref in refs.items() if not is_test or '/Core/' in str(p)] + (testrefs if is_test else [])
 builds=[add(platform+ref,'PBXBuildFile',fileRef=ref) for ref in source_refs]
 sourcephase=add(platform+'sources','PBXSourcesBuildPhase',buildActionMask=2147483647,files=builds,runOnlyForDeploymentPostprocessing=0)
 resbuilds=[] if is_test else [add(platform+'res'+ref,'PBXBuildFile',fileRef=ref) for ref in [assets]+resources]
 resourcephase=add(platform+'resources','PBXResourcesBuildPhase',buildActionMask=2147483647,files=resbuilds,runOnlyForDeploymentPostprocessing=0)
 atv_product=add(platform+'atv-product','XCSwiftPackageProductDependency',package=atv_package,productName='ItsytvCore')
 atv_build=add(platform+'atv-build','PBXBuildFile',productRef=atv_product)
 frameworkphase=add(platform+'frameworks','PBXFrameworksBuildPhase',buildActionMask=2147483647,files=[atv_build],runOnlyForDeploymentPostprocessing=0)
 settings={**base,'SDKROOT':'macosx' if is_mac else 'iphoneos','SUPPORTED_PLATFORMS':'macosx' if is_mac else 'iphoneos iphonesimulator','PRODUCT_BUNDLE_IDENTIFIER':'com.anna.tvglow.'+('tests' if is_test else 'mac' if is_mac else 'ios')}
 if is_mac:settings.update({'CODE_SIGN_IDENTITY':'-','CODE_SIGN_ENTITLEMENTS':'TVGlow/Config/Mac.entitlements','ENABLE_HARDENED_RUNTIME':'YES'})
 else:settings.update({'TARGETED_DEVICE_FAMILY':'1,2','SUPPORTS_MACCATALYST':'NO'})
 if is_test:
  settings.update({'PRODUCT_NAME':'TVGlowTests','PRODUCT_MODULE_NAME':'TVGlowTests','GENERATE_INFOPLIST_FILE':'YES','CODE_SIGN_ENTITLEMENTS':''})
  settings.pop('INFOPLIST_FILE');settings.pop('ASSETCATALOG_COMPILER_APPICON_NAME')
 target=add(platform+'target','PBXNativeTarget',name=name,productName=settings['PRODUCT_NAME'],productReference=product,productType='com.apple.product-type.bundle.unit-test' if is_test else 'com.apple.product-type.application',buildConfigurationList=config_list(platform,settings),buildPhases=[sourcephase,frameworkphase,resourcephase],buildRules=[],dependencies=[],packageProductDependencies=[atv_product])
 targets.append(target)
productgroup=add('productgroup','PBXGroup',name='Products',sourceTree='<group>',children=products)
main=add('main','PBXGroup',sourceTree='<group>',children=[appgroup,testgroup,productgroup])
project=add('project','PBXProject',attributes={'BuildIndependentTargetsInParallel':'YES','LastUpgradeCheck':'2630'},buildConfigurationList=config_list('project',{'ALWAYS_SEARCH_USER_PATHS':'NO','CLANG_WARN_DOCUMENTATION_COMMENTS':'YES','GCC_C_LANGUAGE_STANDARD':'gnu17','SWIFT_VERSION':'5.0'}),compatibilityVersion='Xcode 14.0',developmentRegion='en',hasScannedForEncodings=0,knownRegions=['en','Base'],mainGroup=main,productRefGroup=productgroup,projectDirPath='',projectRoot='',targets=targets,packageReferences=[atv_package])
def fmt(value,indent=0):
 if isinstance(value,dict):return '{\n'+''.join('\t'*(indent+1)+json.dumps(str(k))+' = '+fmt(v,indent+1)+';\n' for k,v in value.items())+'\t'*indent+'}'
 if isinstance(value,list):return '(\n'+''.join('\t'*(indent+1)+fmt(v,indent+1)+',\n' for v in value)+'\t'*indent+')'
 if isinstance(value,int):return str(value)
 return json.dumps(value)
projectdir=ROOT/'TVGlow.xcodeproj';projectdir.mkdir(exist_ok=True)
(projectdir/'project.pbxproj').write_text('// !$*UTF8*$!\n'+fmt({'archiveVersion':1,'classes':{},'objectVersion':56,'objects':objects,'rootObject':project})+'\n')
schemedir=projectdir/'xcshareddata/xcschemes';schemedir.mkdir(parents=True,exist_ok=True)
for platform,target in zip(['macOS','iOS'],targets):
 name='TV Glow '+platform
 buildref=f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="TV Glow.app" BlueprintName="{name}" ReferencedContainer="container:TVGlow.xcodeproj"/>'
 testref=f'<Testables><TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{targets[2]}" BuildableName="TVGlowTests.xctest" BlueprintName="TVGlowTests" ReferencedContainer="container:TVGlow.xcodeproj"/></TestableReference></Testables>' if platform=='macOS' else '<Testables/>'
 xml=f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2630" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{buildref}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES">{testref}</TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{buildref}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{buildref}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>'''
 (schemedir/(name+'.xcscheme')).write_text(xml)
info={'CFBundleDevelopmentRegion':'en','CFBundleDisplayName':'$(APP_DISPLAY_NAME)','CFBundleExecutable':'$(EXECUTABLE_NAME)','CFBundleIdentifier':'$(PRODUCT_BUNDLE_IDENTIFIER)','CFBundleInfoDictionaryVersion':'6.0','CFBundleName':'$(APP_DISPLAY_NAME)','CFBundlePackageType':'APPL','CFBundleShortVersionString':'$(MARKETING_VERSION)','CFBundleVersion':'$(CURRENT_PROJECT_VERSION)','ITSAppUsesNonExemptEncryption':False,'LSApplicationCategoryType':'public.app-category.utilities','NSLocalNetworkUsageDescription':'TV Glow connects to your LG TV, Apple TV and Sonos soundbar for remote control, brightness and volume.','NSBonjourServices':['_companion-link._tcp','_airplay._tcp','_mediaremotetv._tcp'],'NSAppTransportSecurity':{'NSAllowsLocalNetworking':True},'NSHighResolutionCapable':True,'UILaunchScreen':{},'UISupportedInterfaceOrientations':['UIInterfaceOrientationPortrait','UIInterfaceOrientationLandscapeLeft','UIInterfaceOrientationLandscapeRight']}
info['NSLocalNetworkUsageDescription']='TV Glow connects to your LG TV, Apple TV and Sonos soundbar for remote control, brightness and volume.'
info['NSBonjourServices']=['_companion-link._tcp','_airplay._tcp','_mediaremotetv._tcp']
(ROOT/'TVGlow/Config/Info.plist').write_bytes(plistlib.dumps(info))
(ROOT/'TVGlow/Config/Mac.entitlements').write_bytes(plistlib.dumps({'com.apple.security.app-sandbox':True,'com.apple.security.network.client':True}))
# Shared simple vector-style sun mark, rasterized locally at each required size.
assetsdir=ROOT/'TVGlow/Resources/Assets.xcassets';assetsdir.mkdir(exist_ok=True)
(assetsdir/'Contents.json').write_text(json.dumps({'info':{'author':'xcode','version':1}}))
iconset=assetsdir/'AppIcon.appiconset';iconset.mkdir(exist_ok=True)
size=1024;im=Image.new('RGB',(size,size),'#101714');d=ImageDraw.Draw(im)
for a in range(0,180,45):
 r=math.radians(a);x,y=math.cos(r)*270,math.sin(r)*270
 d.line((512-x,512-y,512+x,512+y),fill='#d7ed9f',width=52)
 for cx,cy in [(512-x,512-y),(512+x,512+y)]:d.ellipse((cx-26,cy-26,cx+26,cy+26),fill='#d7ed9f')
d.ellipse((410,410,614,614),fill='#101714')
entries=[]
for points in [16,32,128,256,512]:
 for scale in [1,2]:
  pixels=points*scale;filename=f'mac-{points}@{scale}x.png';im.resize((pixels,pixels),Image.Resampling.LANCZOS).save(iconset/filename)
  entries.append({'filename':filename,'idiom':'mac','scale':f'{scale}x','size':f'{points}x{points}'})
im.save(iconset/'ios-1024.png');entries.append({'filename':'ios-1024.png','idiom':'universal','platform':'ios','size':'1024x1024'})
(iconset/'Contents.json').write_text(json.dumps({'images':entries,'info':{'author':'xcode','version':1}},indent=2))
print('Generated TVGlow.xcodeproj (macOS, iOS, macOS tests) and icons.')
