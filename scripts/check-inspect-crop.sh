#!/bin/sh
# Inspect mode: does the watch draw a cropped frame as the viewport it already is, and
# can a side tap actually cross the screen?
#
# Both failures shipped, and neither is visible to a build. The daemon captured exactly
# the region asked for, at native pixels — and the view then applied the same zoom and
# pan a SECOND time to a picture that already had both baked in, so at 6x the user was
# shown a thirty-sixth of the crop backed by ~100 real source pixels. Zooming in made
# text worse. Meanwhile the sideways step was a hardcoded ±0.5 of the whole display
# while clampedPan's slack is only (1 - 1/zoom)/2, so every side tap slammed into an
# edge and exactly three horizontal positions existed at any zoom.
#
# So this does not assert that a string appears somewhere. It reads the header NAME and
# VALUE FORMAT out of the daemon's own source, requires the client to name and parse
# that same thing, and then runs the shipped geometry: the render decision and the pan
# step are executed, not described.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TS="$ROOT/install/payload/meshd/input.ts"
CLIENT="$ROOT/Shared/MeshClient.swift"
VIEW="$ROOT/Watch/RemoteView.swift"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0

note() { echo "check-inspect-crop: $1"; }
bad() { echo "FAIL: $1"; fail=1; }

for f in "$TS" "$CLIENT" "$VIEW"; do
  [ -f "$f" ] || { echo "FAIL: missing $f"; exit 1; }
done

# ---- 1. what the daemon actually stamps on a cropped frame ----
# The line reads:  if (cropped) headers["x-mesh-rect"] = `${rect.x},${rect.y},...`;
line=$(grep -n 'headers\[.*\] *= *`\${rect\.x}' "$TS" | head -1)
[ -n "$line" ] || { echo "FAIL: input.ts no longer announces the served rect at all — the client can never tell a crop from a full frame"; exit 1; }

name=$(printf '%s' "$line" | sed -E 's/.*headers\[[`"]([^`"]+)[`"]\].*/\1/')
tmpl=$(printf '%s' "$line" | sed -E 's/.*= *`([^`]*)`.*/\1/')
case "$name" in *rect*) : ;; *) echo "FAIL: extracted header name '$name' from input.ts — this check's parser broke, fix it"; exit 1 ;; esac
case "$tmpl" in *'${rect.x}'*'${rect.h}'*) : ;; *) echo "FAIL: extracted value template '$tmpl' from input.ts — this check's parser broke, fix it"; exit 1 ;; esac

# Build the header value the way the daemon builds it, from a rect with four different
# components — a separator change or a reordering both survive equal numbers.
value=$(printf '%s' "$tmpl" \
  | sed -e 's/\${rect\.x}/0.25/' -e 's/\${rect\.y}/0.5/' -e 's/\${rect\.w}/0.125/' -e 's/\${rect\.h}/0.375/')
note "daemon announces '$name: $value'"

# It must stay conditional on having really cropped. A daemon that stamped the header on
# a full frame would make the watch draw the whole display at 1x and call it a zoom.
printf '%s' "$line" | grep -q 'if (cropped)' \
  || bad "the served-rect header is no longer guarded by \`if (cropped)\` — a full frame announced as a crop is drawn unzoomed"

# The client must actually read it off the response, not just define a constant.
grep -q 'value(forHTTPHeaderField: MeshClient.screenRectHeader)' "$CLIENT" \
  || bad "screenFrame does not read the response header — the rect it returns can only be nil, and Inspect silently falls back to the double-zoom path forever"

# Three call sites in files this lane does not own pass through screenImage; its shape
# may not move.
grep -q 'func screenImage(display: Int? = nil, width: Int? = nil,' "$CLIENT" \
  || bad "screenImage's signature changed — iOS/RemoteScreenView.swift, iOS/MeshStore.swift and Watch/WatchMeshStore.swift call it as-is"

# ---- 2. run the shipped geometry ----
cat > "$TMP/check.swift" <<'SWIFT'
import Foundation
import CoreGraphics

@main
struct CheckInspectCrop {
    // A 45mm watch showing a 16:10 Mac display: the exact shape the bug was reported on.
    static let container = 184.0 / 224.0
    static let display = 1.6

    static func main() {
        let args = CommandLine.arguments
        guard args.count == 3 else { fatalError("usage: check <header-name> <header-value>") }
        checkHeader(name: args[1], value: args[2])
        checkRenderDecision()
        checkPanStep()
        print("check-inspect-crop: geometry OK")
    }

    /// The client must name and parse the daemon's header, not one of its own.
    static func checkHeader(name: String, value: String) {
        assert(MeshClient.screenRectHeader == name,
               "the client reads '\(MeshClient.screenRectHeader)' but meshd sends '\(name)' — every frame reads as a full display and Inspect zooms the crop a second time")
        assert(MeshClient.servedRect(header: value) == CGRect(x: 0.25, y: 0.5, width: 0.125, height: 0.375),
               "the client cannot parse the value meshd actually sends ('\(value)')")

        // Anything that is not four sane numbers means "no crop". Never a guess: a
        // frame drawn as a crop when it is not lands the picture — and every
        // tap-to-place-cursor on it — somewhere other than under the finger.
        assert(MeshClient.servedRect(header: nil) == nil, "no header must mean no crop")
        assert(MeshClient.servedRect(header: "") == nil)
        assert(MeshClient.servedRect(header: "0.1,0.2,0.5") == nil, "three numbers is not a rect")
        assert(MeshClient.servedRect(header: "0.1,0.2,0,0.5") == nil, "a zero-width crop is not a crop")
        assert(MeshClient.servedRect(header: "full") == nil)
    }

    /// THE bug. A served crop is already the viewport; drawing it with the zoom and pan
    /// that produced it applies both twice.
    static func checkRenderDecision() {
        let zoom: CGFloat = 6
        let pan = CGPoint(x: 0.3, y: -0.2)
        let crop = CGRect(x: 0.4, y: 0.1, width: 1.0 / 6, height: 0.9)

        let served = frameTransform(servedRect: crop, zoom: zoom, pan: pan)
        assert(served.zoom == 1,
               "a crop the daemon already cut must be drawn at 1x; \(served.zoom)x shows 1/\(Int(served.zoom * served.zoom)) of it, which is the unreadable-when-zoomed bug")
        assert(served.pan == .zero,
               "a crop is centred by definition — offsetting it slides the region you asked for off the watch")

        let full = frameTransform(servedRect: nil, zoom: zoom, pan: pan)
        assert(full.zoom == zoom && full.pan == pan,
               "with no served rect the frame is the whole display and client-side zoom is the only magnification there is — an old daemon must behave exactly as it does today")

        // The old path's actual cost, stated as a number: at 6x the double transform
        // showed 1/36th of a crop that was itself 1/6th of the screen.
        assert(Double(zoom * zoom) == 36)
    }

    /// One side tap = one viewport. Consecutive taps must tile the display: no gap
    /// (a strip you can never see) and no standing still (a tap that does nothing).
    static func checkPanStep() {
        let zoom: CGFloat = 6
        let centre = CGPoint(x: 0, y: 0)
        let view = visibleRect(zoom: zoom, pan: centre, containerAspect: container, imageAspect: display)
        let step = panStep(zoom: zoom, pan: centre, containerAspect: container, imageAspect: display)
        assert(step == Double(view.width), "the step is one viewport width, by definition")
        assert(abs(step - 1.0 / 6) < 1e-9, "at 6x on a 16:10 display a viewport is a sixth of the width, got \(step)")

        // The slack clampedPan allows, and the reason ±0.5 could never work.
        let slack = (1 - Double(view.width)) / 2
        assert(abs(slack - 0.4166666) < 1e-4)
        let old = clampedPan(CGPoint(x: 0.5, y: 0), zoom: zoom,
                             containerAspect: container, imageAspect: display)
        assert(abs(Double(old.x) - slack) < 1e-9,
               "the old hardcoded ±0.5 saturated against the edge in a single tap — that was 'I cannot move from one corner to another'")

        let one = clampedPan(CGPoint(x: step, y: 0), zoom: zoom,
                             containerAspect: container, imageAspect: display)
        assert(Double(one.x) < slack - 1e-9,
               "one tap from the centre must land somewhere in between, not on the far edge")

        // Walk the whole display from the left edge and require every tap to hand over
        // exactly where the last one stopped.
        var pan = clampedPan(CGPoint(x: -1, y: 0), zoom: zoom,
                             containerAspect: container, imageAspect: display)
        var stops = 1
        var covered = visibleRect(zoom: zoom, pan: pan, containerAspect: container, imageAspect: display)
        assert(abs(covered.minX) < 1e-9, "the walk must start at the left edge of the screen")
        while stops < 50 {
            let here = visibleRect(zoom: zoom, pan: pan, containerAspect: container, imageAspect: display)
            let next = clampedPan(CGPoint(x: Double(pan.x) + panStep(zoom: zoom, pan: pan,
                                                                    containerAspect: container,
                                                                    imageAspect: display), y: 0),
                                  zoom: zoom, containerAspect: container, imageAspect: display)
            // Tolerance, not equality: the last step lands on the clamp a ulp short of
            // it, so `next != pan` is still true when the view has stopped moving.
            if Double(next.x) <= Double(pan.x) + 1e-12 { break }
            let there = visibleRect(zoom: zoom, pan: next, containerAspect: container, imageAspect: display)
            assert(there.minX > here.minX + 1e-9, "a side tap that does not move on is not a pan")
            assert(there.minX <= here.maxX + 1e-9,
                   "a side tap skipped from \(here.maxX) to \(there.minX) — that strip of the Mac's screen is unreachable")
            pan = next
            covered = there
            stops += 1
        }
        assert(abs(covered.maxX - 1) < 1e-9, "side taps must eventually reach the right edge, stopped at \(covered.maxX)")
        assert(stops >= 6,
               "at 6x the display should take several taps to cross; \(stops) stops means the step is still too big (the ±0.5 version had exactly 3 reachable columns at every zoom)")
    }
}
SWIFT

# MeshClient.swift and its four transitive dependencies — not check-all.sh's whole DEPS
# line, because this is a seventeenth swiftc invocation in a suite that already spawns a
# throwaway daemon, and the smallest compile that still links the real shipped code is
# the polite one.
if /usr/bin/swiftc -Onone -o "$TMP/check-inspect-crop" "$TMP/check.swift" \
     "$ROOT/Shared/Models.swift" "$ROOT/Shared/RiskClassifier.swift" \
     "$ROOT/Shared/APNsEnvironment.swift" "$ROOT/Shared/ScreenZoom.swift" \
     "$ROOT/Shared/MeshClient.swift" 2>"$TMP/build.err"; then
  # -Onone deliberately: `assert` compiles away under -O, so an optimised build of this
  # would pass with the fix reverted.
  "$TMP/check-inspect-crop" "$name" "$value" || bad "the shipped Inspect geometry is wrong (see the assertion above)"
else
  bad "the check does not compile against Shared/"; tail -5 "$TMP/build.err"
fi

# ---- 3. the watch view has to actually route through it ----
# Both fixes are one modifier away from being dead while everything still builds.
grep -q 'frameTransform(servedRect: servedRect' "$VIEW" \
  || bad "the inspector no longer asks frameTransform how to draw the frame — the crop is being zoomed twice again"
grep -q 'panStep(zoom: remote.previewZoom' "$VIEW" \
  || bad "the side taps no longer step by one viewport"
grep -q 'scaleEffect(draw.zoom)' "$VIEW" \
  || bad "the inspector's image is not drawn with the decided zoom"

zooms=$(grep -c 'scaleEffect(remote.previewZoom)' "$VIEW" || true)
[ "$zooms" = "1" ] \
  || bad "$zooms views apply .scaleEffect(remote.previewZoom) directly; exactly one may (the small preview, which never asks for a crop). The inspector must go through frameTransform"

# The shape fed to the region maths must be the DISPLAY's, never the arrived crop's.
# `aspect` is the picture in hand — in Inspect that IS the crop — and may only be used
# to lay the picture out and to map taps onto it. Feed it to visibleRect/clampedPan/
# panStep and the next region is computed from the crop's shape instead of the screen's,
# so the view creeps sideways as you scroll and the pan clamp stops in the wrong place.
# Counted rather than named: every use of `aspect` must belong to a layout call.
total=$(grep -c 'imageAspect: aspect' "$VIEW" || true)
layout=$(tr '\n' ' ' < "$VIEW" \
  | grep -oE '(normalizedPoint|zoomedOffset|pointerScreenPosition|panOffset)\([^)]*imageAspect: aspect' \
  | wc -l | tr -d ' ')
[ "$layout" -ge 4 ] || bad "found only $layout layout uses of the image's own aspect — this check's extraction broke, fix it"
[ "$total" = "$layout" ] \
  || bad "'imageAspect: aspect' is used $total times but only $layout of those lay out the picture; the rest are feeding the arrived crop's shape into the region maths, which must be given regionAspect"
grep -q 'panOffset(pan: draw.pan, zoom: draw.zoom,' "$VIEW" \
  || bad "panOffset is no longer given the decided pan — a served crop would be offset off-screen"

if [ "$fail" = "0" ]; then
  echo "check-inspect-crop: OK"
else
  echo "check-inspect-crop: FAILED"
  exit 1
fi
