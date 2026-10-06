#!/usr/bin/env python3
"""Regenerate the checked-in Xcode project with no third-party dependencies.

Source files stay shared with SwiftPM. Run after adding/removing Swift files.
"""
from pathlib import Path
import hashlib
import json
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
objects = {}


def identifier(name):
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()


def obj(identity, isa, **values):
    key = identifier(identity)
    objects[key] = dict(isa=isa, **values)
    return key


def encode(value, level=0):
    if isinstance(value, dict):
        return "{\n" + "".join("\t" * (level + 1) + f"{k} = {encode(v, level + 1)};\n" for k, v in value.items()) + "\t" * level + "}"
    if isinstance(value, list):
        return "(" + ", ".join(encode(v, level) for v in value) + ("," if value else "") + ")"
    if isinstance(value, int):
        return str(value)
    return json.dumps(value)


def file(path, kind="sourcecode.swift", source_tree="SOURCE_ROOT"):
    return obj("file:" + path, "PBXFileReference", lastKnownFileType=kind, path=path, sourceTree=source_tree)


def phase(target, name, isa, refs):
    builds = [obj(f"build:{target}:{name}:{ref}", "PBXBuildFile", fileRef=ref) for ref in refs]
    return obj(f"phase:{target}:{name}", isa, buildActionMask=2147483647, files=builds, runOnlyForDeploymentPostprocessing=0)


def configurations(name, settings, base=None):
    configs = []
    for config in ["Debug", "Release"]:
        flags = dict(settings)
        flags.update(SWIFT_OPTIMIZATION_LEVEL="-Onone" if config == "Debug" else "-O",
                     DEBUG_INFORMATION_FORMAT="dwarf" if config == "Debug" else "dwarf-with-dsym",
                     ENABLE_TESTABILITY="YES")
        if config == "Debug":
            flags["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = "DEBUG"
        values = dict(buildSettings=flags, name=config)
        if base:
            values["baseConfigurationReference"] = base
        configs.append(obj(f"config:{name}:{config}", "XCBuildConfiguration", **values))
    return obj("configs:" + name, "XCConfigurationList", buildConfigurations=configs,
               defaultConfigurationIsVisible=0, defaultConfigurationName="Release")


def dependency(target):
    proxy = obj("proxy:" + target, "PBXContainerItemProxy", containerPortal=identifier("project"),
                proxyType=1, remoteGlobalIDString=identifier("target:" + target), remoteInfo=target)
    return obj("dependency:" + target, "PBXTargetDependency", target=identifier("target:" + target), targetProxy=proxy)


def main():
    version = file("Config/Version.xcconfig", "text.xcconfig")
    info = file("Packaging/Info.plist", "text.plist.xml")
    icon = file("Resources/AppIcon.icns", "image.icns")
    products = {}
    targets = []
    groups = []
    definitions = [
        ("StereoCore", "Sources/StereoCore", "libStereoCore.a", "archive.ar", "com.apple.product-type.library.static", []),
        ("SteFi", "Sources/StereoCleanup", "SteFi.app", "wrapper.application", "com.apple.product-type.application", ["StereoCore"]),
        ("StereoCoreTests", "Tests/StereoCoreTests", "StereoCoreTests.xctest", "wrapper.cfbundle", "com.apple.product-type.bundle.unit-test", ["StereoCore"]),
        ("SteFiTests", "Tests/SteFiTests", "SteFiTests.xctest", "wrapper.cfbundle", "com.apple.product-type.bundle.unit-test", ["SteFi", "StereoCore"]),
    ]
    for name, _, product, kind, _, _ in definitions:
        products[name] = obj("product:" + name, "PBXFileReference", explicitFileType=kind,
                             includeInIndex=0, path=product, sourceTree="BUILT_PRODUCTS_DIR")
    for name, source, product, _, product_type, deps in definitions:
        sources = [file(str(p.relative_to(ROOT))) for p in sorted((ROOT / source).glob("*.swift"))]
        groups.append(obj("group:" + name, "PBXGroup", children=sources, name=name, sourceTree="<group>"))
        settings = dict(PRODUCT_NAME=name, PRODUCT_MODULE_NAME=name, SKIP_INSTALL="YES",
                        GENERATE_INFOPLIST_FILE="YES", CODE_SIGN_IDENTITY="-",
                        CODE_SIGN_STYLE="Manual", ENABLE_APP_SANDBOX="NO",
                        ENABLE_HARDENED_RUNTIME="NO", SWIFT_EMIT_LOC_STRINGS="NO")
        resources = []
        linked = [products[d] for d in deps if d == "StereoCore"]
        if name == "StereoCore":
            settings.update(DEFINES_MODULE="YES", SWIFT_INSTALL_OBJC_HEADER="NO")
        elif name == "SteFi":
            settings.update(PRODUCT_BUNDLE_IDENTIFIER="ee.music.SteFi", INFOPLIST_FILE="Packaging/Info.plist",
                            GENERATE_INFOPLIST_FILE="NO", SKIP_INSTALL="NO",
                            OTHER_SWIFT_FLAGS=["$(inherited)", "-parse-as-library"])
            resources = [icon]
        else:
            settings.update(PRODUCT_BUNDLE_IDENTIFIER="ee.music." + name,
                            LD_RUNPATH_SEARCH_PATHS=["$(inherited)", "@executable_path/../Frameworks", "@loader_path/../Frameworks"])
            if name == "SteFiTests":
                settings.update(TEST_HOST="$(BUILT_PRODUCTS_DIR)/SteFi.app/Contents/MacOS/SteFi",
                                BUNDLE_LOADER="$(TEST_HOST)", TEST_TARGET_NAME="SteFi")
        phases = [phase(name, "Sources", "PBXSourcesBuildPhase", sources),
                  phase(name, "Frameworks", "PBXFrameworksBuildPhase", linked),
                  phase(name, "Resources", "PBXResourcesBuildPhase", resources)]
        targets.append(obj("target:" + name, "PBXNativeTarget", name=name, productName=name,
                           productReference=products[name], productType=product_type,
                           buildConfigurationList=configurations(name, settings, version),
                           buildPhases=phases, buildRules=[], dependencies=[dependency(d) for d in deps]))
    groups += [obj("group:Resources", "PBXGroup", children=[icon], name="Resources", sourceTree="<group>"),
               obj("group:Config", "PBXGroup", children=[version, info], name="Configuration", sourceTree="<group>"),
               obj("group:Products", "PBXGroup", children=list(products.values()), name="Products", sourceTree="<group>")]
    main_group = obj("group:main", "PBXGroup", children=groups, sourceTree="<group>")
    settings = dict(SDKROOT="macosx", MACOSX_DEPLOYMENT_TARGET="14.0", SWIFT_VERSION="5.0",
                    CLANG_ENABLE_MODULES="YES", CLANG_ENABLE_OBJC_ARC="YES", ARCHS="arm64",
                    ONLY_ACTIVE_ARCH="YES", SWIFT_STRICT_CONCURRENCY="targeted")
    project = obj("project", "PBXProject", attributes=dict(LastUpgradeCheck="1600", BuildIndependentTargetsInParallel="YES"),
                  buildConfigurationList=configurations("project", settings), compatibilityVersion="Xcode 14.0",
                  developmentRegion="en", hasScannedForEncodings=0, knownRegions=["en", "Base"],
                  mainGroup=main_group, productRefGroup=identifier("group:Products"), projectDirPath="",
                  projectRoot="", targets=targets)
    folder = ROOT / "SteFi.xcodeproj"
    folder.mkdir(exist_ok=True)
    document = dict(archiveVersion=1, classes={}, objectVersion=56, objects=objects, rootObject=project)
    (folder / "project.pbxproj").write_text("// !$*UTF8*$!\n" + encode(document) + "\n")
    schemes = folder / "xcshareddata" / "xcschemes"
    schemes.mkdir(parents=True, exist_ok=True)
    scheme = ET.Element("Scheme", LastUpgradeVersion="1600", version="1.3")

    def reference(parent, name):
        product = next(d[2] for d in definitions if d[0] == name)
        ET.SubElement(parent, "BuildableReference", BuildableIdentifier="primary",
                      BlueprintIdentifier=identifier("target:" + name), BuildableName=product,
                      BlueprintName=name, ReferencedContainer="container:SteFi.xcodeproj")

    build = ET.SubElement(scheme, "BuildAction", parallelizeBuildables="YES", buildImplicitDependencies="YES")
    entries = ET.SubElement(build, "BuildActionEntries")
    for name in ["SteFi", "StereoCoreTests", "SteFiTests"]:
        app = name == "SteFi"
        entry = ET.SubElement(entries, "BuildActionEntry", buildForTesting="YES", buildForRunning="YES" if app else "NO",
                              buildForProfiling="YES" if app else "NO", buildForArchiving="YES" if app else "NO",
                              buildForAnalyzing="YES")
        reference(entry, name)
    test = ET.SubElement(scheme, "TestAction", buildConfiguration="Debug", selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB",
                         selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB", shouldUseLaunchSchemeArgsEnv="YES")
    testables = ET.SubElement(test, "Testables")
    for name in ["StereoCoreTests", "SteFiTests"]:
        reference(ET.SubElement(testables, "TestableReference", skipped="NO", parallelizable="NO"), name)
    launch = ET.SubElement(scheme, "LaunchAction", buildConfiguration="Debug", selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB",
                           selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB", launchStyle="0", useCustomWorkingDirectory="NO",
                           ignoresPersistentStateOnLaunch="NO", debugDocumentVersioning="YES", allowLocationSimulation="YES")
    reference(ET.SubElement(launch, "BuildableProductRunnable", runnableDebuggingMode="0"), "SteFi")
    profile = ET.SubElement(scheme, "ProfileAction", buildConfiguration="Release", shouldUseLaunchSchemeArgsEnv="YES", useCustomWorkingDirectory="NO", debugDocumentVersioning="YES")
    reference(ET.SubElement(profile, "BuildableProductRunnable", runnableDebuggingMode="0"), "SteFi")
    ET.SubElement(scheme, "AnalyzeAction", buildConfiguration="Debug")
    ET.SubElement(scheme, "ArchiveAction", buildConfiguration="Release", revealArchiveInOrganizer="YES")
    ET.indent(scheme)
    ET.ElementTree(scheme).write(schemes / "SteFi.xcscheme", encoding="UTF-8", xml_declaration=True)
    print(folder)


if __name__ == "__main__":
    main()
