"""Structural checks only: this does NOT compile Swift or test UWB hardware."""
from pathlib import Path
import json
import plistlib
import re
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]


class OpenStep:
    def __init__(self, text):
        text = re.sub(r"//[^\n]*", "", text)
        self.tokens = re.findall(r'"(?:\\.|[^"\\])*"|[{}()=;,]|[^\s{}()=;,]+', text)
        self.index = 0

    def take(self):
        result = self.tokens[self.index]
        self.index += 1
        return result

    def expect(self, wanted):
        got = self.take()
        assert got == wanted, (wanted, got)

    def value(self):
        token = self.take()
        if token == "{":
            result = {}
            while self.tokens[self.index] != "}":
                key = self.value()
                assert key not in result, f"Duplicate key: {key}"
                self.expect("=")
                result[key] = self.value()
                self.expect(";")
            self.expect("}")
            return result
        if token == "(":
            result = []
            while self.tokens[self.index] != ")":
                result.append(self.value())
                self.expect(",")
            self.expect(")")
            return result
        return json.loads(token) if token.startswith('"') else token


def main():
    project = ROOT / "UWBMeetDemo.xcodeproj"
    parser = OpenStep((project / "project.pbxproj").read_text(encoding="utf-8"))
    doc = parser.value()
    assert parser.index == len(parser.tokens), "Trailing project tokens"
    objects = doc["objects"]
    assert objects[doc["rootObject"]]["isa"] == "PBXProject"
    refs = {k: v for k, v in objects.items() if v["isa"] == "PBXFileReference"}
    for ref in refs.values():
        if ref["sourceTree"] == "<group>":
            assert (ROOT / ref["path"]).is_file(), ref["path"]
    expected = {p.relative_to(ROOT).as_posix() for folder in ("App", "Core") for p in (ROOT / folder).glob("*.swift")}
    phases = [v for v in objects.values() if v["isa"] == "PBXSourcesBuildPhase"]
    built = [refs[objects[ref]["fileRef"]]["path"] for phase in phases for ref in phase["files"]]
    assert len(built) == len(set(built)) and set(built) == expected, (built, expected)
    reference_keys = {"fileRef", "buildConfigurationList", "mainGroup", "productRefGroup", "productReference"}
    list_keys = {"children", "files", "buildPhases", "buildConfigurations", "targets"}
    for obj in objects.values():
        for key, value in obj.items():
            if key in reference_keys:
                assert value in objects, (key, value)
            if key in list_keys:
                assert all(ref in objects for ref in value), (key, value)
    info = plistlib.loads((ROOT / "Info.plist").read_bytes())
    assert info["NSNearbyInteractionUsageDescription"] and info["NSLocalNetworkUsageDescription"]
    assert info["NSBonjourServices"] == ["_uwbmeet._tcp"]
    assert 'static let serviceType = "_uwbmeet._tcp"' in (ROOT / "App/PeerTransport.swift").read_text(encoding="utf-8")
    scheme = ET.parse(project / "xcshareddata/xcschemes/UWBMeetDemo.xcscheme")
    for ref in scheme.findall(".//BuildableReference"):
        assert objects[ref.attrib["BlueprintIdentifier"]]["isa"] == "PBXNativeTarget"
    assert (ROOT / "Package.swift").is_file()
    test_count = len(re.findall(r"func test\w+\(", (ROOT / "Tests/MeetCoreTests.swift").read_text(encoding="utf-8")))
    assert test_count >= 8
    for path in ROOT.rglob("*"):
        if path.suffix in {".swift", ".py", ".md", ".plist", ".pbxproj", ".xcscheme"}:
            for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
                assert line == line.rstrip(), f"Trailing whitespace: {path}:{number}"
    print(f"PASS: project syntax/references, {len(expected)} Swift source entries, privacy plist, Bonjour service, shared scheme, whitespace.")
    print(f"FOUND: {test_count} Swift test methods (NOT executed; requires Swift).")
    print("NOT VERIFIED: Swift compilation, Apple API compatibility, signing, UI rendering, networking, UWB ranging, two-device exchange.")


if __name__ == "__main__":
    main()
