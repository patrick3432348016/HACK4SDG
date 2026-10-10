"""Generate the checked-in Xcode project with Python stdlib; no XcodeGen dependency."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]
objects = {}


def uid(name):
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()


def add(identifier, isa, **fields):
    key = uid(identifier)
    objects[key] = dict(isa=isa, **fields)
    return key


def render(value, depth=0):
    indent = "\t" * depth
    if isinstance(value, dict):
        return "{\n" + "".join(
            f'{indent}\t{json.dumps(str(k))} = {render(v, depth + 1)};\n'
            for k, v in value.items()) + indent + "}"
    if isinstance(value, list):
        return "(\n" + "".join(f"{indent}\t{render(v, depth + 1)},\n" for v in value) + indent + ")"
    return json.dumps(str(value))


def main():
    source_refs, builds = [], []
    for folder in ("App", "Core"):
        for path in sorted((ROOT / folder).glob("*.swift")):
            rel = path.relative_to(ROOT).as_posix()
            ref = add(rel, "PBXFileReference", lastKnownFileType="sourcecode.swift", path=rel, sourceTree="<group>")
            source_refs.append(ref)
            builds.append(add("build:" + rel, "PBXBuildFile", fileRef=ref))
    info = add("info", "PBXFileReference", lastKnownFileType="text.plist.xml", path="Info.plist", sourceTree="<group>")
    product = add("product", "PBXFileReference", explicitFileType="wrapper.application", includeInIndex=0,
                  path="UWBMeetDemo.app", sourceTree="BUILT_PRODUCTS_DIR")
    products = add("products", "PBXGroup", children=[product], name="Products", sourceTree="<group>")
    group = add("root", "PBXGroup", children=source_refs + [info, products], sourceTree="<group>")
    sources = add("sources", "PBXSourcesBuildPhase", buildActionMask=2147483647, files=builds, runOnlyForDeploymentPostprocessing=0)
    frameworks = add("frameworks", "PBXFrameworksBuildPhase", buildActionMask=2147483647, files=[], runOnlyForDeploymentPostprocessing=0)
    resources = add("resources", "PBXResourcesBuildPhase", buildActionMask=2147483647, files=[], runOnlyForDeploymentPostprocessing=0)
    project_configs, target_configs = [], []
    for config in ("Debug", "Release"):
        project_configs.append(add("project:" + config, "XCBuildConfiguration", name=config, buildSettings={
            "CLANG_ENABLE_MODULES": "YES", "SDKROOT": "iphoneos", "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
            "SWIFT_VERSION": "5.0", "SWIFT_STRICT_CONCURRENCY": "targeted",
            "SWIFT_OPTIMIZATION_LEVEL": "-Onone" if config == "Debug" else "-O",
            "DEBUG_INFORMATION_FORMAT": "dwarf" if config == "Debug" else "dwarf-with-dsym",
            "ENABLE_TESTABILITY": "YES" if config == "Debug" else "NO",
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG" if config == "Debug" else "",
        }))
        target_configs.append(add("target:" + config, "XCBuildConfiguration", name=config, buildSettings={
            "PRODUCT_BUNDLE_IDENTIFIER": "org.hack4sdg.uwbmeetdemo", "PRODUCT_NAME": "$(TARGET_NAME)",
            "INFOPLIST_FILE": "Info.plist", "GENERATE_INFOPLIST_FILE": "NO", "CODE_SIGN_STYLE": "Automatic",
            "TARGETED_DEVICE_FAMILY": "1", "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
            "SUPPORTS_MACCATALYST": "NO", "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"],
        }))
    def configs(name, items):
        return add(name, "XCConfigurationList", buildConfigurations=items, defaultConfigurationIsVisible=0, defaultConfigurationName="Release")
    target = add("target", "PBXNativeTarget", buildConfigurationList=configs("target-configs", target_configs),
                 buildPhases=[sources, frameworks, resources], buildRules=[], dependencies=[], name="UWBMeetDemo",
                 productName="UWBMeetDemo", productReference=product, productType="com.apple.product-type.application")
    project = add("project", "PBXProject", attributes={"LastUpgradeCheck": "1500", "BuildIndependentTargetsInParallel": "YES"},
                  buildConfigurationList=configs("project-configs", project_configs), compatibilityVersion="Xcode 14.0",
                  developmentRegion="zh-Hans", knownRegions=["zh-Hans", "en", "Base"], mainGroup=group,
                  productRefGroup=products, projectDirPath="", projectRoot="", targets=[target])
    document = dict(archiveVersion=1, classes={}, objectVersion=56, objects=objects, rootObject=project)
    out = ROOT / "UWBMeetDemo.xcodeproj"
    out.mkdir(exist_ok=True)
    (out / "project.pbxproj").write_text("// !$*UTF8*$!\n" + render(document) + "\n", encoding="utf-8")
    schemes = out / "xcshareddata" / "xcschemes"
    schemes.mkdir(parents=True, exist_ok=True)
    ref = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="UWBMeetDemo.app" BlueprintName="UWBMeetDemo" ReferencedContainer="container:UWBMeetDemo.xcodeproj"/>'
    (schemes / "UWBMeetDemo.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1500" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables/></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/>
<ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''', encoding="utf-8")
    print(f"Generated {len(builds)} Swift source references and shared app scheme.")


if __name__ == "__main__":
    main()
