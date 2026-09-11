#!/usr/bin/env python3
"""Generate the Xcode project with Python's standard library.

Object IDs come from stable names. Keep signing and packaging settings here;
the checked-in project is generated output.
"""

import hashlib
import json
from pathlib import Path
from xml.etree import ElementTree

ROOT = Path(__file__).resolve().parents[1]
CONFIGURATIONS = ("Debug", "Release", "LocalTest")
SOURCE_FOLDERS = ("App", "Shared", "Helper", "Tests")
FILE_TYPES = {
    ".m": "sourcecode.c.objc",
    ".h": "sourcecode.c.h",
    ".plist": "text.plist.xml",
    ".icns": "image.icns",
}
FRAMEWORKS = (
    "Cocoa", "Foundation", "SystemConfiguration", "IOKit", "Security",
    "ServiceManagement", "UniformTypeIdentifiers", "XCTest",
)
PRODUCTS = {
    "IPSelector": ("IP Selector.app", "wrapper.application"),
    "IPSelectorHelper": ("IPSelectorHelper", "compiled.mach-o.executable"),
    "IPSelectorTests": ("IPSelectorTests.xctest", "wrapper.cfbundle"),
}
BUNDLE_IDS = {
    "IPSelector": "org.ipselector.IPSelector",
    "IPSelectorHelper": "org.ipselector.IPSelector.Helper",
    "IPSelectorTests": "org.ipselector.IPSelector.Tests",
}
COMMON_SETTINGS = {
    "SDKROOT": "macosx",
    "MACOSX_DEPLOYMENT_TARGET": "14.0",
    "CLANG_ENABLE_OBJC_ARC": "YES",
    "CLANG_ENABLE_MODULES": "YES",
    "CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF": "YES",
    "CLANG_WARN_DOCUMENTATION_COMMENTS": "YES",
    "GCC_WARN_64_TO_32_BIT_CONVERSION": "YES",
    "GCC_WARN_UNDECLARED_SELECTOR": "YES",
    "GCC_WARN_UNUSED_VARIABLE": "YES",
    "GCC_C_LANGUAGE_STANDARD": "gnu17",
    "HEADER_SEARCH_PATHS": ["$(inherited)", "$(SRCROOT)/Shared", "$(SRCROOT)/App"],
    "CODE_SIGN_IDENTITY": "-",
    "CODE_SIGN_STYLE": "Manual",
    "ENABLE_HARDENED_RUNTIME": "YES",
    "ARCHS": "$(ARCHS_STANDARD)",
    "ONLY_ACTIVE_ARCH": "NO",
    "ENABLE_APP_SANDBOX": "NO",
}
LOCAL_APP_SETTINGS = {
    "PRODUCT_NAME": "IP Selector (Local Test)",
    "PRODUCT_BUNDLE_IDENTIFIER": "org.ipselector.IPSelector.LocalTest",
    "IP_DAEMON_PLIST_NAME": "org.ipselector.IPSelector.LocalTest.Helper.plist",
}
LOCAL_HELPER_SETTINGS = {
    "PRODUCT_BUNDLE_IDENTIFIER": "org.ipselector.IPSelector.LocalTest.Helper",
    "INFOPLIST_FILE": "Helper/LocalTest-Info.plist",
}
EMBED_DAEMON_SCRIPT = '''set -eu
mkdir -p "${TARGET_BUILD_DIR}/${CONTENTS_FOLDER_PATH}/Library/LaunchDaemons"
cp "${SRCROOT}/Helper/${IP_DAEMON_PLIST_NAME}" "${TARGET_BUILD_DIR}/${CONTENTS_FOLDER_PATH}/Library/LaunchDaemons/${IP_DAEMON_PLIST_NAME}"
'''

def uid(name):
    """Keep unchanged project objects stable across generation runs."""
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()

def configuration_settings(target, mode, settings):
    build = dict(settings)
    release = mode == "Release"
    build["GCC_OPTIMIZATION_LEVEL"] = "s" if release else "0"
    build["DEBUG_INFORMATION_FORMAT"] = "dwarf-with-dsym" if release else "dwarf"
    if release:
        # A distribution build must not receive the debug get-task-allow entitlement.
        build["CODE_SIGN_INJECT_BASE_ENTITLEMENTS"] = "NO"
    else:
        build["GCC_PREPROCESSOR_DEFINITIONS"] = ["DEBUG=1", "$(inherited)"]
    if mode == "LocalTest":
        build["GCC_PREPROCESSOR_DEFINITIONS"] = [
            "DEBUG=1", "IP_LOCAL_TEST=1", "$(inherited)"
        ]
        if target == "IPSelector":
            build.update(LOCAL_APP_SETTINGS)
        elif target == "IPSelectorHelper":
            build.update(LOCAL_HELPER_SETTINGS)
    return build

class ProjectBuilder:
    """Build the object table without global mutable state."""

    def __init__(self, root):
        self.root = root
        self.objects = {}
        self.files = {}
        self.frameworks = {}
        self.products = {}

    def add(self, object_key, **fields):
        identifier = uid(object_key)
        if identifier in self.objects:
            raise ValueError(f"Duplicate project object: {object_key}")
        self.objects[identifier] = fields
        return identifier

    def config_list(self, target, settings):
        configurations = [
            self.add(
                target + mode,
                isa="XCBuildConfiguration",
                name=mode,
                buildSettings=configuration_settings(target, mode, settings),
            )
            for mode in CONFIGURATIONS
        ]
        return self.add(
            target + "configs",
            isa="XCConfigurationList",
            buildConfigurations=configurations,
            defaultConfigurationIsVisible=0,
            defaultConfigurationName="Release",
        )

    def group(self, key, name, children):
        return self.add(
            key, isa="PBXGroup", name=name, children=children, sourceTree="<group>"
        )

    def create_file_references(self):
        source_groups = []
        for folder in SOURCE_FOLDERS:
            children = []
            for path in sorted((self.root / folder).iterdir()):
                if path.suffix not in FILE_TYPES:
                    continue
                relative = str(path.relative_to(self.root))
                reference = self.add(
                    relative,
                    isa="PBXFileReference",
                    lastKnownFileType=FILE_TYPES[path.suffix],
                    path=relative,
                    sourceTree="SOURCE_ROOT",
                )
                self.files[relative] = reference
                children.append(reference)
            source_groups.append(self.group(folder + "group", folder, children))
        return source_groups

    def create_framework_references(self):
        for name in FRAMEWORKS:
            path = f"System/Library/Frameworks/{name}.framework"
            tree = "SDKROOT"
            if name == "XCTest":
                path = "Platforms/MacOSX.platform/Developer/Library/Frameworks/XCTest.framework"
                tree = "DEVELOPER_DIR"
            self.frameworks[name] = self.add(
                name,
                isa="PBXFileReference",
                lastKnownFileType="wrapper.framework",
                name=name + ".framework",
                path=path,
                sourceTree=tree,
            )
        return self.group("frameworks", "Frameworks", list(self.frameworks.values()))

    def create_product_references(self):
        for name, (path, kind) in PRODUCTS.items():
            self.products[name] = self.add(
                name + "product",
                isa="PBXFileReference",
                explicitFileType=kind,
                path=path,
                sourceTree="BUILT_PRODUCTS_DIR",
            )
        return self.group("products", "Products", list(self.products.values()))

    def source_files(self, folder):
        return [
            path for path in self.files
            if path.startswith(folder + "/") and path.endswith(".m")
        ]

    def phase(self, key, kind, files, **fields):
        return self.add(
            key,
            isa=kind,
            buildActionMask=2147483647,
            files=files,
            runOnlyForDeploymentPostprocessing=0,
            **fields,
        )

    def build_files(self, target, names, references):
        return [
            self.add(target + name, isa="PBXBuildFile", fileRef=references[name])
            for name in names
        ]

    def app_phases(self):
        icon = self.add(
            "app icon resource", isa="PBXBuildFile", fileRef=self.files["App/AppIcon.icns"]
        )
        helper = self.add(
            "copy helper file",
            isa="PBXBuildFile",
            fileRef=self.products["IPSelectorHelper"],
            settings={"ATTRIBUTES": ["CodeSignOnCopy"]},
        )
        return [
            self.phase("app resources", "PBXResourcesBuildPhase", [icon]),
            self.phase(
                "Embed Helper", "PBXCopyFilesBuildPhase", [helper],
                dstPath="Contents/Library/HelperTools", dstSubfolderSpec=1,
                name="Embed Helper",
            ),
            self.phase(
                "Embed Daemon Plist", "PBXShellScriptBuildPhase", [],
                inputPaths=["$(SRCROOT)/Helper/$(IP_DAEMON_PLIST_NAME)"],
                outputPaths=[
                    "$(TARGET_BUILD_DIR)/$(CONTENTS_FOLDER_PATH)/Library/LaunchDaemons/$(IP_DAEMON_PLIST_NAME)"
                ],
                name="Embed Daemon Plist",
                shellPath="/bin/sh",
                shellScript=EMBED_DAEMON_SCRIPT,
            ),
        ]

    def helper_dependency(self):
        proxy = self.add(
            "helper proxy",
            isa="PBXContainerItemProxy",
            containerPortal=uid("project"),
            proxyType=1,
            remoteGlobalIDString=uid("IPSelectorHelpertarget"),
            remoteInfo="IPSelectorHelper",
        )
        return self.add(
            "helper dependency", isa="PBXTargetDependency",
            target=uid("IPSelectorHelpertarget"), targetProxy=proxy,
        )

    def target(self, name, kind, sources, frameworks, extra_settings):
        phases = [
            self.phase(
                name + "sources", "PBXSourcesBuildPhase",
                self.build_files(name, sources, self.files),
            ),
            self.phase(
                name + "frameworks", "PBXFrameworksBuildPhase",
                self.build_files(name, frameworks, self.frameworks),
            ),
        ]
        settings = {
            **COMMON_SETTINGS,
            "PRODUCT_NAME": "IP Selector" if name == "IPSelector" else name,
            "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_IDS[name],
            **extra_settings,
        }
        dependencies = []
        if name == "IPSelector":
            phases.extend(self.app_phases())
            dependencies.append(self.helper_dependency())
        return self.add(
            name + "target",
            isa="PBXNativeTarget",
            name=name,
            productName=settings["PRODUCT_NAME"],
            productReference=self.products[name],
            productType="com.apple.product-type." + kind,
            buildPhases=phases,
            buildRules=[],
            dependencies=dependencies,
            buildConfigurationList=self.config_list(name, settings),
        )

    def create_targets(self):
        shared = self.source_files("Shared")
        network_frameworks = ["SystemConfiguration", "IOKit", "Security"]
        return [
            self.target(
                "IPSelectorHelper", "tool", shared + ["Helper/main.m"],
                ["Foundation", *network_frameworks],
                {
                    "INFOPLIST_FILE": "Helper/Info.plist",
                    "CREATE_INFOPLIST_SECTION_IN_BINARY": "YES",
                    "SKIP_INSTALL": "YES",
                },
            ),
            self.target(
                "IPSelector", "application", shared + self.source_files("App"),
                ["Cocoa", *network_frameworks, "ServiceManagement", "UniformTypeIdentifiers"],
                {
                    "INFOPLIST_FILE": "App/Info.plist",
                    "IP_DAEMON_PLIST_NAME": "org.ipselector.IPSelector.Helper.plist",
                },
            ),
            self.target(
                "IPSelectorTests", "bundle.unit-test",
                shared + ["App/IPPresetStore.m", "App/IPHelperSetup.m"] + self.source_files("Tests"),
                ["Foundation", *network_frameworks, "ServiceManagement", "XCTest"],
                {
                    "GENERATE_INFOPLIST_FILE": "YES",
                    "ENABLE_HARDENED_RUNTIME": "NO",
                    "LD_RUNPATH_SEARCH_PATHS": [
                        "$(inherited)", "@loader_path/../Frameworks",
                        "$(PLATFORM_DIR)/Developer/Library/Frameworks",
                    ],
                    "SKIP_INSTALL": "YES",
                },
            ),
        ]

    def build(self):
        source_groups = self.create_file_references()
        framework_group = self.create_framework_references()
        product_group = self.create_product_references()
        main_group = self.add(
            "main", isa="PBXGroup", sourceTree="<group>",
            children=[*source_groups, framework_group, product_group],
        )
        targets = self.create_targets()
        project = self.add(
            "project",
            isa="PBXProject",
            attributes={"LastUpgradeCheck": "1600", "BuildIndependentTargetsInParallel": "YES"},
            buildConfigurationList=self.config_list("project", {}),
            compatibilityVersion="Xcode 14.0",
            developmentRegion="en",
            hasScannedForEncodings=0,
            knownRegions=["en", "Base"],
            mainGroup=main_group,
            productRefGroup=product_group,
            projectDirPath="",
            projectRoot="",
            targets=targets,
        )
        return {
            "archiveVersion": 1, "classes": {}, "objectVersion": 56,
            "objects": self.objects, "rootObject": project,
        }

def render(value, depth=0):
    """Write an indented OpenStep property list."""
    indent = "\t" * depth
    child_indent = indent + "\t"
    if isinstance(value, dict):
        if not value:
            return "{}"
        entries = [
            f"{child_indent}{json.dumps(str(key))} = {render(item, depth + 1)};"
            for key, item in value.items()
        ]
        return "{\n" + "\n".join(entries) + "\n" + indent + "}"
    if isinstance(value, list):
        if not value:
            return "()"
        entries = [f"{child_indent}{render(item, depth + 1)}," for item in value]
        return "(\n" + "\n".join(entries) + "\n" + indent + ")"
    return str(value) if isinstance(value, int) else json.dumps(value)

def reference(parent, target):
    ElementTree.SubElement(
        parent, "BuildableReference",
        BuildableIdentifier="primary",
        BlueprintIdentifier=uid(target + "target"),
        BuildableName=PRODUCTS[target][0],
        BlueprintName=target,
        ReferencedContainer="container:IPSelector.xcodeproj",
    )

def create_scheme():
    scheme = ElementTree.Element("Scheme", LastUpgradeVersion="1600", version="1.3")
    build = ElementTree.SubElement(
        scheme, "BuildAction", parallelizeBuildables="YES", buildImplicitDependencies="YES"
    )
    entries = ElementTree.SubElement(build, "BuildActionEntries")
    for target in ("IPSelector", "IPSelectorTests"):
        runnable = "YES" if target == "IPSelector" else "NO"
        entry = ElementTree.SubElement(
            entries, "BuildActionEntry", buildForTesting="YES", buildForRunning=runnable,
            buildForProfiling=runnable, buildForArchiving=runnable, buildForAnalyzing="YES",
        )
        reference(entry, target)
    debugger = {
        "selectedDebuggerIdentifier": "Xcode.DebuggerFoundation.Debugger.LLDB",
        "selectedLauncherIdentifier": "Xcode.IDEFoundation.Launcher.LLDB",
    }
    test = ElementTree.SubElement(
        scheme, "TestAction", buildConfiguration="Debug", **debugger,
        shouldUseLaunchSchemeArgsEnv="YES",
    )
    testables = ElementTree.SubElement(test, "Testables")
    reference(ElementTree.SubElement(testables, "TestableReference", skipped="NO"), "IPSelectorTests")
    launch = ElementTree.SubElement(
        scheme, "LaunchAction", buildConfiguration="Debug", **debugger, launchStyle="0",
        useCustomWorkingDirectory="NO", ignoresPersistentStateOnLaunch="NO",
        debugDocumentVersioning="YES", debugServiceExtension="internal", allowLocationSimulation="YES",
    )
    reference(ElementTree.SubElement(launch, "BuildableProductRunnable", runnableDebuggingMode="0"), "IPSelector")
    profile = ElementTree.SubElement(
        scheme, "ProfileAction", buildConfiguration="Release", shouldUseLaunchSchemeArgsEnv="YES",
        useCustomWorkingDirectory="NO", debugDocumentVersioning="YES",
    )
    reference(ElementTree.SubElement(profile, "BuildableProductRunnable", runnableDebuggingMode="0"), "IPSelector")
    ElementTree.SubElement(scheme, "AnalyzeAction", buildConfiguration="Debug")
    ElementTree.SubElement(scheme, "ArchiveAction", buildConfiguration="Release", revealArchiveInOrganizer="YES")
    ElementTree.indent(scheme, space="    ")
    return ElementTree.tostring(scheme, encoding="unicode", xml_declaration=True) + "\n"

def main():
    project_dir = ROOT / "IPSelector.xcodeproj"
    scheme_dir = project_dir / "xcshareddata/xcschemes"
    scheme_dir.mkdir(parents=True, exist_ok=True)
    document = ProjectBuilder(ROOT).build()
    (project_dir / "project.pbxproj").write_text("// !$*UTF8*$!\n" + render(document) + "\n")
    (scheme_dir / "IPSelector.xcscheme").write_text(create_scheme())
    print("Generated IPSelector.xcodeproj")

if __name__ == "__main__":
    main()
