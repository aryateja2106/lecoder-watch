#!/bin/sh
# Self-check for the mobile output compressors in install/payload/agent/mobile.ts.
#
# These are the only defence between a 30KB simulator artifact and a model whose prefill
# runs at roughly 110 tokens/second. If a digest silently stops extracting failures, the
# agent starts "reading" test logs it cannot actually see, so this check asserts on the
# extracted CONTENT, not just on the compression ratio.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/xcode.log" <<'LOG'
Build settings from command line:
    PLATFORM_NAME = iphonesimulator
note: Using new build system
CompileSwift normal arm64 /Users/x/App/Sources/Login.swift
    cd /Users/x/App
    export DEVELOPER_DIR\=/Applications/Xcode.app/Contents/Developer
LOG
i=0
while [ "$i" -lt 120 ]; do
  echo "CompileSwift normal arm64 /Users/x/App/Sources/Generated/Model$i.swift (in target 'App' from project 'App')" >> "$TMP/xcode.log"
  echo "    cd /Users/x/App && /Applications/Xcode.app/Contents/Developer/usr/bin/swift-frontend -frontend -c -primary-file Model$i.swift -target arm64-apple-ios17.0-simulator" >> "$TMP/xcode.log"
  i=$((i+1))
done
cat >> "$TMP/xcode.log" <<'LOG'
Test Suite 'All tests' started at 2026-09-01 04:00:00.000
Test Suite 'LoginTests' started at 2026-09-01 04:00:00.100
Test Case '-[LoginTests testSignInDisabledWhenEmpty]' started.
/Users/x/App/Tests/LoginTests.swift:42: error: -[LoginTests testSignInDisabledWhenEmpty] : XCTAssertFalse failed - button was enabled with empty credentials
Test Case '-[LoginTests testSignInDisabledWhenEmpty]' failed (0.031 seconds).
Test Case '-[LoginTests testTokenRefresh]' started.
/Users/x/App/Tests/LoginTests.swift:88: error: -[LoginTests testTokenRefresh] : XCTAssertEqual failed: ("nil") is not equal to ("token")
Test Case '-[LoginTests testTokenRefresh]' failed (0.012 seconds).
Test Suite 'LoginTests' failed at 2026-09-01 04:00:01.000
Executed 24 tests, with 2 failures (0 unexpected) in 1.204 seconds
** TEST FAILED **
LOG

cat > "$TMP/gradle.log" <<'LOG'
> Task :app:compileDebugKotlin
> Task :app:testDebugUnitTest
com.example.LoginTest > signInDisabledWhenEmpty FAILED
    java.lang.AssertionError: expected button disabled
        at com.example.LoginTest.signInDisabledWhenEmpty(LoginTest.kt:42)
com.example.TokenTest > refreshesExpiredToken FAILED
    org.junit.ComparisonFailure: expected:<token> but was:<null>
        at com.example.TokenTest.refreshesExpiredToken(TokenTest.kt:88)
18 tests completed, 2 failed
> Task :app:testDebugUnitTest FAILED
LOG

# A hierarchy with real layout scaffolding, which is most of a real dump.
{
  echo '<?xml version="1.0" encoding="UTF-8"?>'
  echo '<hierarchy rotation="0">'
  i=0
  while [ "$i" -lt 60 ]; do
    echo "  <node index=\"$i\" text=\"\" resource-id=\"\" class=\"android.widget.LinearLayout\" content-desc=\"\" clickable=\"false\" bounds=\"[0,$i][1080,100]\" />"
    i=$((i+1))
  done
  echo '  <node index="60" text="Email" resource-id="com.example:id/email_label" class="android.widget.TextView" content-desc="" clickable="false" bounds="[40,300][300,340]" />'
  echo '  <node index="61" text="" resource-id="com.example:id/email_field" class="android.widget.EditText" content-desc="Email address" clickable="true" bounds="[40,350][1040,420]" />'
  echo '  <node index="62" text="Sign in" resource-id="com.example:id/submit" class="android.widget.Button" content-desc="" clickable="true" bounds="[40,500][1040,580]" />'
  echo '</hierarchy>'
} > "$TMP/ui.xml"

cat > "$TMP/driver.ts" <<'TS'
import { digestTestLog, outlineUiHierarchy, compressIfRecognized } from "AGENT/mobile";
import { readFileSync } from "node:fs";

let failed = 0;
const check = (name: string, cond: boolean, detail = "") => {
  if (!cond) { console.log(`  FAIL ${name} ${detail}`); failed++; }
  else console.log(`  ok   ${name} ${detail}`);
};

const xcode = readFileSync(process.argv[2] + "/xcode.log", "utf8");
const d = digestTestLog(xcode);
check("xcode kind", d.kind === "xcodebuild", d.kind);
check("xcode failure count", d.failures.length === 2, String(d.failures.length));
check("xcode counts", d.failed === 2 && d.passed === 22, `failed=${d.failed} passed=${d.passed}`);
check("xcode file+line", d.failures[0].file === "/Users/x/App/Tests/LoginTests.swift" && d.failures[0].line === 42,
  `${d.failures[0].file}:${d.failures[0].line}`);
check("xcode names test", d.failures[0].suite === "LoginTests" && d.failures[0].test === "testSignInDisabledWhenEmpty");
check("xcode keeps message", d.failures[0].message.includes("button was enabled"));
check("xcode shrinks hard", d.text.length * 20 < xcode.length, `${xcode.length} -> ${d.text.length}`);

const gradle = readFileSync(process.argv[2] + "/gradle.log", "utf8");
const g = digestTestLog(gradle);
check("gradle kind", g.kind === "gradle", g.kind);
check("gradle failure count", g.failures.length === 2, String(g.failures.length));
check("gradle counts", g.failed === 2 && g.passed === 16, `failed=${g.failed} passed=${g.passed}`);
check("gradle names test", g.failures[0].suite === "com.example.LoginTest" && g.failures[0].test === "signInDisabledWhenEmpty");
check("gradle message stops at the failure", g.failures[0].message === "java.lang.AssertionError: expected button disabled", g.failures[0].message);
check("gradle finds file+line from the frame", g.failures[0].file === "LoginTest.kt" && g.failures[0].line === 42, `${g.failures[0].file}:${g.failures[0].line}`);

const xml = readFileSync(process.argv[2] + "/ui.xml", "utf8");
const { elements, text } = outlineUiHierarchy(xml);
check("ui drops scaffolding", elements.length === 3, `${elements.length} of 63 nodes kept`);
check("ui marks tappable", elements.filter(e => e.clickable).length === 2);
check("ui uses label or content-desc", elements[1].label === "Email address", elements[1].label);
check("ui computes centre", elements[2].bounds.x === 540 && elements[2].bounds.y === 540,
  `${elements[2].bounds.x},${elements[2].bounds.y}`);
check("ui shrinks hard", text.length * 10 < xml.length, `${xml.length} -> ${text.length}`);

const c1 = compressIfRecognized(xml);
check("recognises a hierarchy", c1 !== null && c1.text.includes("Sign in"));
const c2 = compressIfRecognized(xcode);
check("recognises a test log", c2 !== null && c2.text.includes("testTokenRefresh"));
const c3 = compressIfRecognized("hello world\n".repeat(200));
check("leaves ordinary output alone", c3 === null);

if (failed) { console.log(`\n${failed} assertion(s) failed`); process.exit(1); }
console.log("check-mobile-digest: all assertions passed");
TS

sed -i "s#AGENT#$ROOT/install/payload/agent#" "$TMP/driver.ts"
bun run "$TMP/driver.ts" "$TMP"
