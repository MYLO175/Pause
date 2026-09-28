#!/usr/bin/env python3
"""Deterministic Xcode project generation without external dependencies."""
from pathlib import Path
import hashlib
ROOT = Path(__file__).resolve().parents[1]
objects = {}
def uid(name): return hashlib.sha1(name.encode()).hexdigest()[:24].upper()
def add(name, content):
    key = uid(name); objects[key] = content; return key
def q(value): return '"' + str(value).replace('\\','\\\\').replace('"','\\"') + '"'
def arr(items): return '(' + ', '.join(items) + (',' if items else '') + ')'
def obj(**fields): return '{ ' + ' '.join(k + ' = ' + str(v) + ';' for k,v in fields.items()) + ' }'
files = {}
for path in sorted(list((ROOT/'Pause').rglob('*.swift')) + list((ROOT/'Tests').rglob('*.swift')) + list((ROOT/'PauseUITests').rglob('*.swift')) + list((ROOT/'Pause/Resources/Audio').glob('*.wav')) + [ROOT/'Pause/Resources/Assets.xcassets', ROOT/'Pause/Info.plist']):
    rel = str(path.relative_to(ROOT)); typ = 'sourcecode.swift' if path.suffix == '.swift' else 'folder.assetcatalog' if path.suffix == '.xcassets' else 'audio.wav' if path.suffix == '.wav' else 'text.plist.xml'
    files[rel] = add('file:'+rel, obj(isa='PBXFileReference', lastKnownFileType=typ, path=q(rel), sourceTree=q('<group>')))
products = {}
for target in ['Pause','PauseTests','PauseUITests']:
    ext = '.app' if target == 'Pause' else '.xctest'
    products[target] = add('product:'+target, obj(isa='PBXFileReference', explicitFileType='wrapper.application' if target == 'Pause' else 'wrapper.cfbundle', path=q(target+ext), sourceTree='BUILT_PRODUCTS_DIR'))
product_group = add('products', obj(isa='PBXGroup', children=arr(list(products.values())), name='Products', sourceTree=q('<group>')))
main_group = add('main', obj(isa='PBXGroup', children=arr(list(files.values())+[product_group]), sourceTree=q('<group>')))
def config_list(name, settings):
    configs=[]
    for kind in ['Debug','Release']:
        vals=dict(settings)
        vals.update({'SWIFT_OPTIMIZATION_LEVEL': q('-Onone' if kind == 'Debug' else '-O'), 'DEBUG_INFORMATION_FORMAT': q('dwarf' if kind == 'Debug' else 'dwarf-with-dsym')})
        if kind == 'Debug': vals['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = q('DEBUG $(inherited)'); vals['ENABLE_TESTABILITY'] = 'YES'
        configs.append(add(name+kind, obj(isa='XCBuildConfiguration', buildSettings=obj(**vals), name=kind)))
    return add(name+'configs', obj(isa='XCConfigurationList', buildConfigurations=arr(configs), defaultConfigurationIsVisible=0, defaultConfigurationName='Release'))
project_configs=config_list('project', {'SDKROOT':'iphoneos','IPHONEOS_DEPLOYMENT_TARGET':'17.0','SWIFT_VERSION':'5.0','CLANG_ENABLE_MODULES':'YES','CLANG_ENABLE_OBJC_ARC':'YES','SWIFT_STRICT_CONCURRENCY':'targeted','ENABLE_USER_SCRIPT_SANDBOXING':'YES'})
for target in ['Pause','PauseTests','PauseUITests']:
    prefix = 'Pause/' if target == 'Pause' else 'Tests/' if target == 'PauseTests' else 'PauseUITests/'
    sources=[]; resources=[]
    for path, ref in files.items():
        if path.startswith(prefix) and (path.endswith('.swift') or (target == 'Pause' and (path.endswith('.wav') or path.endswith('.xcassets')))):
            build=add(target+':build:'+path, obj(isa='PBXBuildFile', fileRef=ref))
            (sources if path.endswith('.swift') else resources).append(build)
    phases=[]
    for kind, items in [('Sources',sources),('Frameworks',[]),('Resources',resources)]:
        phases.append(add(target+kind, obj(isa='PBX'+kind+'BuildPhase', buildActionMask=2147483647, files=arr(items), runOnlyForDeploymentPostprocessing=0)))
    settings={'PRODUCT_NAME':q('$(TARGET_NAME)'), 'PRODUCT_BUNDLE_IDENTIFIER':q('com.mylomichael.pause'+('' if target=='Pause' else '.'+target)), 'TARGETED_DEVICE_FAMILY':q('1'), 'CODE_SIGN_STYLE':'Automatic','SUPPORTED_PLATFORMS':q('iphoneos iphonesimulator'),'SUPPORTS_MACCATALYST':'NO','GENERATE_INFOPLIST_FILE':'YES','MARKETING_VERSION':'1.0','CURRENT_PROJECT_VERSION':'1'}
    deps=[]
    if target == 'Pause': settings.update({'INFOPLIST_FILE':q('Pause/Info.plist'),'GENERATE_INFOPLIST_FILE':'NO','ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon','LD_RUNPATH_SEARCH_PATHS':q('$(inherited) @executable_path/Frameworks')})
    else:
        proxy=add(target+'proxy',obj(isa='PBXContainerItemProxy',containerPortal=uid('project'),proxyType=1,remoteGlobalIDString=uid('target:Pause'),remoteInfo='Pause'))
        deps=[add(target+'dep',obj(isa='PBXTargetDependency',target=uid('target:Pause'),targetProxy=proxy))]
        if target=='PauseTests': settings.update({'TEST_HOST':q('$(BUILT_PRODUCTS_DIR)/Pause.app/Pause'),'BUNDLE_LOADER':q('$(TEST_HOST)')})
        else: settings['TEST_TARGET_NAME']='Pause'
    add('target:'+target,obj(isa='PBXNativeTarget', buildConfigurationList=config_list(target,settings), buildPhases=arr(phases),buildRules='()',dependencies=arr(deps),name=target,productName=target,productReference=products[target],productType=q('com.apple.product-type.application' if target=='Pause' else 'com.apple.product-type.bundle.unit-test' if target=='PauseTests' else 'com.apple.product-type.bundle.ui-testing')))
add('project', obj(isa='PBXProject', attributes='{ BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 2700; }',buildConfigurationList=project_configs,compatibilityVersion=q('Xcode 14.0'),developmentRegion='en',hasScannedForEncodings=0,knownRegions='(en, Base)',mainGroup=main_group,productRefGroup=product_group,projectDirPath=q(''),projectRoot=q(''),targets=arr([uid('target:'+t) for t in ['Pause','PauseTests','PauseUITests']])))
project=ROOT/'Pause.xcodeproj'; project.mkdir(exist_ok=True)
(project/'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+ '\n'.join(k+' = '+v+';' for k,v in objects.items()) + '\n}; rootObject = '+uid('project')+'; }\n')
schemes=project/'xcshareddata/xcschemes'; schemes.mkdir(parents=True,exist_ok=True)
def ref(t): return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid("target:"+t)}" BuildableName="{t}{".app" if t=="Pause" else ".xctest"}" BlueprintName="{t}" ReferencedContainer="container:Pause.xcodeproj"/>'
(schemes/'Pause.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref('Pause')}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{ref('PauseTests')}</TestableReference><TestableReference skipped="NO">{ref('PauseUITests')}</TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref('Pause')}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref('Pause')}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
print('Generated', project)
