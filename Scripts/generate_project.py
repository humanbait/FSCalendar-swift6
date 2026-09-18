#!/usr/bin/env python3
"""Generate the checked-in development project using only Python's standard library."""
import hashlib
import json
from pathlib import Path
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'Example/CalendarShowcase.xcodeproj'
objects = {}

def oid(name):
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()

def obj(object_name, isa, **fields):
    key = oid(object_name)
    objects[key] = {'isa': isa, **fields}
    return key

def settings(name, values):
    return obj(name, 'XCBuildConfiguration', buildSettings=values, name=name.rsplit(':', 1)[-1])

def configs(name, common, debug=None):
    configs = []
    for mode in ['Debug', 'Release']:
        values = dict(common)
        values.update({'SWIFT_OPTIMIZATION_LEVEL': '-Onone' if mode == 'Debug' else '-O',
                       'GCC_PREPROCESSOR_DEFINITIONS': ['$(inherited)', 'DEBUG=1'] if mode == 'Debug' else ['$(inherited)']})
        if mode == 'Debug' and debug:
            values.update(debug)
        configs.append(settings(f'{name}:{mode}', values))
    return obj(name + ':configs', 'XCConfigurationList', buildConfigurations=configs,
               defaultConfigurationIsVisible=0, defaultConfigurationName='Release')

def ref(path, kind):
    return obj('file:' + path, 'PBXFileReference', lastKnownFileType=kind, path=path, sourceTree='SOURCE_ROOT')

def build(name, reference, **extra):
    return obj('build:' + name, 'PBXBuildFile', fileRef=reference, **extra)

file_refs = []
products = []
targets = []
target_products = {}
target_ids = {}

def target(name, product_type, paths, dependencies=(), frameworks=(), extra=None, platform="ios", package_products=()):
    tid = oid('target:' + name)
    target_ids[name] = tid
    is_framework = product_type.endswith('framework')
    is_app = product_type.endswith('application')
    extension = 'framework' if is_framework else ('app' if is_app else 'xctest')
    product = obj('product:' + name, 'PBXFileReference', explicitFileType='wrapper.framework' if is_framework else ('wrapper.application' if is_app else 'wrapper.cfbundle'),
                  includeInIndex=0, path=f'{name}.{extension}', sourceTree='BUILT_PRODUCTS_DIR')
    products.append(product)
    target_products[name] = product
    sources, headers = [], []
    for file in sorted(paths):
        rel = str(file.relative_to(ROOT / 'Example')) if file.is_relative_to(ROOT / 'Example') else '../' + str(file.relative_to(ROOT))
        kind = {'.swift': 'sourcecode.swift', '.m': 'sourcecode.c.objc', '.h': 'sourcecode.c.h'}[file.suffix]
        fid = ref(rel, kind)
        file_refs.append(fid)
        if file.suffix == '.h':
            headers.append(build(name + rel, fid, settings={'ATTRIBUTES': ['Public']}))
        else:
            sources.append(build(name + rel, fid))
    phases = [obj(name + ':sources', 'PBXSourcesBuildPhase', buildActionMask=2147483647, files=sources, runOnlyForDeploymentPostprocessing=0)]
    if headers:
        phases.append(obj(name + ':headers', 'PBXHeadersBuildPhase', buildActionMask=2147483647, files=headers, runOnlyForDeploymentPostprocessing=0))
    links = [build(name + ':link:' + dep, target_products[dep]) for dep in frameworks]
    package_refs = []
    for product_name in package_products:
        dependency = obj(name + ':package:' + product_name, 'XCSwiftPackageProductDependency', productName=product_name)
        package_refs.append(dependency)
        links.append(obj(name + ':package-build:' + product_name, 'PBXBuildFile', productRef=dependency))
    phases.append(obj(name + ':frameworks', 'PBXFrameworksBuildPhase', buildActionMask=2147483647, files=links, runOnlyForDeploymentPostprocessing=0))
    phases.append(obj(name + ':resources', 'PBXResourcesBuildPhase', buildActionMask=2147483647, files=[], runOnlyForDeploymentPostprocessing=0))
    deps = []
    for dep in dependencies:
        proxy = obj(name + ':proxy:' + dep, 'PBXContainerItemProxy', containerPortal=oid('project'), proxyType=1,
                    remoteGlobalIDString=target_ids[dep], remoteInfo=dep)
        deps.append(obj(name + ':dependency:' + dep, 'PBXTargetDependency', target=target_ids[dep], targetProxy=proxy))
    common = {
        'PRODUCT_NAME': '$(TARGET_NAME)', 'PRODUCT_BUNDLE_IDENTIFIER': 'com.spbgfs.fscalendar.' + name.lower(),
        'DEVELOPMENT_TEAM': 'MDPX5436J8', 'CODE_SIGN_STYLE': 'Automatic',
        'GENERATE_INFOPLIST_FILE': 'YES', 'SWIFT_VERSION': '6.0',
        'IPHONEOS_DEPLOYMENT_TARGET': '16.0', 'TARGETED_DEVICE_FAMILY': '1,2',
        'SDKROOT': 'iphoneos', 'SUPPORTED_PLATFORMS': 'iphoneos iphonesimulator',
        'CLANG_ENABLE_MODULES': 'YES', 'CLANG_ENABLE_OBJC_ARC': 'YES',
        'ENABLE_USER_SCRIPT_SANDBOXING': 'YES', 'SWIFT_STRICT_CONCURRENCY': 'complete',
        'SWIFT_EMIT_LOC_STRINGS': 'NO', 'ENABLE_TESTABILITY': 'YES',
        'LD_RUNPATH_SEARCH_PATHS': ['$(inherited)', '@executable_path/Frameworks', '@loader_path/Frameworks'],
    }
    if is_framework:
        common.update({'DEFINES_MODULE': 'YES', 'MACH_O_TYPE': 'staticlib', 'SKIP_INSTALL': 'YES', 'CODE_SIGNING_ALLOWED': 'NO'})
    if is_app:
        common.update({'INFOPLIST_KEY_CFBundleDisplayName': 'Calendar Lab', 'INFOPLIST_KEY_UILaunchScreen_Generation': 'YES',
                       'INFOPLIST_KEY_UISupportedInterfaceOrientations': 'UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight',
                       'INFOPLIST_KEY_UIRequiresFullScreen': 'YES', 'OTHER_LDFLAGS': ['$(inherited)', '-ObjC'],
                       'CURRENT_PROJECT_VERSION': '1', 'MARKETING_VERSION': '0.1.0'})
    if platform == "macos":
        for key in ['IPHONEOS_DEPLOYMENT_TARGET', 'TARGETED_DEVICE_FAMILY',
                    'INFOPLIST_KEY_UILaunchScreen_Generation', 'INFOPLIST_KEY_UISupportedInterfaceOrientations',
                    'INFOPLIST_KEY_UIRequiresFullScreen']:
            common.pop(key, None)
        common.update({'SDKROOT': 'macosx', 'SUPPORTED_PLATFORMS': 'macosx',
            'MACOSX_DEPLOYMENT_TARGET': '13.0', 'ONLY_ACTIVE_ARCH': 'YES', 'CODE_SIGN_IDENTITY': '-',
            'ENABLE_HARDENED_RUNTIME': 'NO', 'SWIFT_TREAT_WARNINGS_AS_ERRORS': 'YES',
            'LD_RUNPATH_SEARCH_PATHS': ['$(inherited)', '@executable_path/../Frameworks', '@loader_path/../Frameworks']})
        if is_app:
            common.update({'INFOPLIST_KEY_NSPrincipalClass': 'NSApplication',
                           'INFOPLIST_KEY_LSApplicationCategoryType': 'public.app-category.developer-tools'})
    if extra:
        common.update(extra)
    obj('target:' + name, 'PBXNativeTarget', buildConfigurationList=configs(name, common), buildPhases=phases,
        buildRules=[], dependencies=deps, packageProductDependencies=package_refs, name=name, productName=name, productReference=product, productType=product_type)
    targets.append(tid)

legacy = list((ROOT / 'Development/Legacy/FSCalendar').glob('*.[hm]'))
target('FSCalendarLegacy', 'com.apple.product-type.framework', legacy)
modern = (ROOT / 'Sources/FSCalendar/FSCalendar.swift').exists()
if modern:
    target('FSCalendarCore', 'com.apple.product-type.framework', (ROOT / 'Sources/FSCalendarCore').rglob('*.swift'))
    target('FSCalendar', 'com.apple.product-type.framework', (ROOT / 'Sources/FSCalendar').rglob('*.swift'),
           dependencies=['FSCalendarCore'], frameworks=['FSCalendarCore'])
target('CalendarDemoSupport', 'com.apple.product-type.framework', (ROOT / 'Development/DemoSupport').rglob('*.swift'), dependencies=['FSCalendarCore'], frameworks=['FSCalendarCore'])
libs = ['CalendarDemoSupport', 'FSCalendarLegacy'] + (['FSCalendarCore', 'FSCalendar'] if modern else [])
target('CalendarShowcase', 'com.apple.product-type.application', (ROOT / 'Example/CalendarShowcase').rglob('*.swift'), dependencies=libs, frameworks=libs)
unit_paths = list((ROOT / 'Example/CalendarShowcaseTests').rglob('*.swift')) + list((ROOT / 'Example/CalendarShowcaseTests').glob('*.m'))
if modern:
    unit_paths += list((ROOT / 'Tests/FSCalendarCoreTests').rglob('*.swift')) + list((ROOT / 'Tests/FSCalendarTests').rglob('*.swift'))
target('CalendarShowcaseTests', 'com.apple.product-type.bundle.unit-test', unit_paths,
       dependencies=['CalendarShowcase'], frameworks=libs,
       extra={'TEST_HOST': '$(BUILT_PRODUCTS_DIR)/CalendarShowcase.app/CalendarShowcase', 'BUNDLE_LOADER': '$(TEST_HOST)',
              'HEADER_SEARCH_PATHS': ['$(inherited)', '$(SRCROOT)/../Development/Legacy/FSCalendar']})
target('CalendarShowcaseUITests', 'com.apple.product-type.bundle.ui-testing', (ROOT / 'Example/CalendarShowcaseUITests').rglob('*.swift'),
       dependencies=['CalendarShowcase'], extra={'TEST_TARGET_NAME': 'CalendarShowcase'})
local_package = obj('local-package', 'XCLocalSwiftPackageReference', relativePath='..')
mac_libs = ['FSCalendarCore', 'FSCalendarAppKit']
target('CalendarDemoSupportMac', 'com.apple.product-type.framework', (ROOT / 'Development/DemoSupport').rglob('*.swift'), platform='macos')
target('CalendarShowcaseMac', 'com.apple.product-type.application', (ROOT / 'Example/CalendarShowcaseMac').rglob('*.swift'),
       platform='macos', package_products=mac_libs, dependencies=['CalendarDemoSupportMac'], frameworks=['CalendarDemoSupportMac'])
mac_test_paths = list((ROOT / 'Example/CalendarShowcaseMacTests').rglob('*.swift')) + list((ROOT / 'Tests/FSCalendarAppKitTests').rglob('*.swift'))
target('CalendarShowcaseMacTests', 'com.apple.product-type.bundle.unit-test', mac_test_paths,
       dependencies=['CalendarShowcaseMac'], platform='macos', package_products=mac_libs, frameworks=['CalendarDemoSupportMac'],
       extra={'TEST_HOST': '$(BUILT_PRODUCTS_DIR)/CalendarShowcaseMac.app/Contents/MacOS/CalendarShowcaseMac', 'BUNDLE_LOADER': '$(TEST_HOST)'})
target('CalendarShowcaseMacUITests', 'com.apple.product-type.bundle.ui-testing', (ROOT / 'Example/CalendarShowcaseMacUITests').rglob('*.swift'),
       dependencies=['CalendarShowcaseMac'], platform='macos', extra={'TEST_TARGET_NAME': 'CalendarShowcaseMac'})
product_group = obj('products', 'PBXGroup', children=products, name='Products', sourceTree='<group>')
file_refs.append(ref('CalendarShowcase.xctestplan', 'text'))
root_group = obj('root', 'PBXGroup', children=list(dict.fromkeys(file_refs)) + [product_group], sourceTree='<group>')
obj('project', 'PBXProject', attributes={'BuildIndependentTargetsInParallel': 'YES', 'LastUpgradeCheck': '2600',
    'TargetAttributes': {target_ids['CalendarShowcaseTests']: {'TestTargetID': target_ids['CalendarShowcase']},
                         target_ids['CalendarShowcaseUITests']: {'TestTargetID': target_ids['CalendarShowcase']}}},
    buildConfigurationList=configs('project', {'ALWAYS_SEARCH_USER_PATHS': 'NO', 'CLANG_ENABLE_MODULES': 'YES',
        'GCC_C_LANGUAGE_STANDARD': 'gnu17', 'CLANG_CXX_LANGUAGE_STANDARD': 'gnu++20', 'DEBUG_INFORMATION_FORMAT': 'dwarf-with-dsym'}),
    compatibilityVersion='Xcode 14.0', developmentRegion='en', hasScannedForEncodings=0,
    knownRegions=['en', 'Base'], mainGroup=root_group, productRefGroup=product_group,
    projectDirPath='', projectRoot='', targets=targets, packageReferences=[local_package])

def serialize(value, indent=0):
    if isinstance(value, dict):
        return '{\n' + ''.join('\t' * (indent + 1) + json.dumps(k) + ' = ' + serialize(v, indent + 1) + ';\n' for k, v in value.items()) + '\t' * indent + '}'
    if isinstance(value, list):
        return '(' + ', '.join(serialize(v, indent) for v in value) + ')'
    return json.dumps(value)

PROJECT.mkdir(parents=True, exist_ok=True)
(PROJECT / 'project.pbxproj').write_text('// !$*UTF8*$!\n' + serialize({'archiveVersion': 1, 'classes': {}, 'objectVersion': 56, 'objects': objects, 'rootObject': oid('project')}) + '\n')

def build_ref(name):
    extension = 'app' if name in ['CalendarShowcase', 'CalendarShowcaseMac'] else 'xctest'
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target_ids[name]}" BuildableName="{name}.{extension}" BlueprintName="{name}" ReferencedContainer="container:CalendarShowcase.xcodeproj"/>'

scheme_dir = PROJECT / 'xcshareddata/xcschemes'
scheme_dir.mkdir(parents=True, exist_ok=True)
scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
<BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{build_ref('CalendarShowcase')}</BuildActionEntry>
</BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES">
<TestPlans><TestPlanReference reference="container:CalendarShowcase.xctestplan" default="YES"/></TestPlans>
</TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{build_ref('CalendarShowcase')}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{build_ref('CalendarShowcase')}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>'''
(scheme_dir / 'CalendarShowcase.xcscheme').write_text(scheme)
test_configurations = [{'id': 'DC72825C-8F40-4676-AF7B-963D9213993C', 'name': 'Legacy baseline',
                        'options': {'environmentVariableEntries': [{'key': 'FSCALENDAR_IMPLEMENTATION', 'value': 'legacy'}]}}]
if modern:
    test_configurations.append({'id': 'C78C6D01-8479-4B6E-AB83-41FBA5CD4381', 'name': 'Swift rewrite',
                                'options': {'environmentVariableEntries': [{'key': 'FSCALENDAR_IMPLEMENTATION', 'value': 'swift'}]}})
test_plan = {
    'configurations': test_configurations,
    'defaultOptions': {'uiTestingScreenshotsLifetime': 'keepAlways', 'userAttachmentLifetime': 'keepAlways',
                       'testTimeoutsEnabled': True},
    'testTargets': [{'parallelizable': False, 'target': {
        'containerPath': 'container:CalendarShowcase.xcodeproj', 'identifier': target_ids[name], 'name': name
    }} for name in ['CalendarShowcaseTests', 'CalendarShowcaseUITests']],
    'version': 1,
}
(ROOT / 'Example/CalendarShowcase.xctestplan').write_text(json.dumps(test_plan, indent=2) + '\n')
print(PROJECT)

(scheme_dir / 'CalendarShowcaseMac.xcscheme').write_text(scheme.replace(build_ref('CalendarShowcase'), build_ref('CalendarShowcaseMac')).replace('container:CalendarShowcase.xctestplan', 'container:CalendarShowcaseMac.xctestplan'))
mac_plan = {'configurations': [{'id': '07291528-7803-4137-8147-74039C565809', 'name': 'Native AppKit', 'options': {}}],
    'defaultOptions': test_plan['defaultOptions'], 'version': 1,
    'testTargets': [{'parallelizable': False, 'target': {'containerPath': 'container:CalendarShowcase.xcodeproj',
        'identifier': target_ids[name], 'name': name}} for name in ['CalendarShowcaseMacTests', 'CalendarShowcaseMacUITests']]}
(ROOT / 'Example/CalendarShowcaseMac.xctestplan').write_text(json.dumps(mac_plan, indent=2) + '\n')
