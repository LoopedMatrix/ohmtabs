// Standalone unit test for the snap glow/flash state machine and the shared
// zone decision (pure logic — no Hyprland, no compositor, no session).
//
// Build:  g++ -std=c++20 -I.. tests/test_snapfx.cpp -o tests/test_snapfx
// Run:    tests/test_snapfx   (exit 0 on all-pass, non-zero otherwise)

#include "snapfx.hpp"

#include <cmath>
#include <cstdio>

static int g_failures = 0;

static void check(const char* name, bool ok) {
    std::printf("%s: %s\n", ok ? "PASS" : "FAIL", name);
    if (!ok)
        ++g_failures;
}

static bool near(double a, double b, double eps = 1e-6) {
    return std::fabs(a - b) <= eps;
}

int main() {
    using namespace SnapFx;

    const Rect FRAME{0.0, 0.0, 1920.0, 1080.0};
    const Rect AREA{0.0, 0.0, 1920.0, 1080.0};

    // --- zone classification must agree with snapToZone (corner/edge/none) ---
    const auto tl = decideZone(5, 5, FRAME, AREA);
    check("corner-TL zone", tl.zone == Zone::CornerTL);
    check("corner-TL target", near(tl.target.x, 0) && near(tl.target.y, 0) && near(tl.target.w, 960) && near(tl.target.h, 540));

    const auto tr = decideZone(1915, 5, FRAME, AREA);
    check("corner-TR zone", tr.zone == Zone::CornerTR);
    check("corner-TR target", near(tr.target.x, 960) && near(tr.target.y, 0) && near(tr.target.w, 960) && near(tr.target.h, 540));

    const auto bl = decideZone(5, 1075, FRAME, AREA);
    check("corner-BL zone", bl.zone == Zone::CornerBL);
    check("corner-BL target", near(bl.target.x, 0) && near(bl.target.y, 540) && near(bl.target.w, 960) && near(bl.target.h, 540));

    const auto br = decideZone(1915, 1075, FRAME, AREA);
    check("corner-BR zone", br.zone == Zone::CornerBR);
    check("corner-BR target", near(br.target.x, 960) && near(br.target.y, 540) && near(br.target.w, 960) && near(br.target.h, 540));

    const auto left = decideZone(5, 500, FRAME, AREA);
    check("left edge zone", left.zone == Zone::Left);
    check("left target is half width", near(left.target.x, 0) && near(left.target.y, 0) && near(left.target.w, 960) && near(left.target.h, 1080));

    const auto right = decideZone(1915, 500, FRAME, AREA);
    check("right edge zone", right.zone == Zone::Right);
    check("right target is right half", near(right.target.x, 960) && near(right.target.w, 960));

    const auto top = decideZone(500, 5, FRAME, AREA);
    check("top edge zone", top.zone == Zone::Top);
    check("top edge maximizes", top.maximize);

    const auto bottom = decideZone(960, 1075, FRAME, AREA);
    check("bottom edge alone is none", bottom.zone == Zone::None);

    const auto interior = decideZone(960, 540, FRAME, AREA);
    check("interior is none", interior.zone == Zone::None);

    // Edge threshold: inside the 24px band triggers, one px past does not.
    const auto edgeIn  = decideZone(24, 500, FRAME, AREA);
    const auto edgeOut = decideZone(25, 500, FRAME, AREA);
    check("edge threshold inclusive", edgeIn.zone == Zone::Left && edgeOut.zone == Zone::None);

    // Non-zero frame origin must be respected.
    const Rect FRAME2{100.0, 100.0, 1920.0, 1080.0};
    const Rect AREA2{100.0, 100.0, 1920.0, 1080.0};
    const auto off = decideZone(100, 500, FRAME2, AREA2);
    check("origin offset left zone", off.zone == Zone::Left);
    check("origin offset target x", near(off.target.x, 100));

    // --- strip reserve: top-touching zones must clear the title strip ---
    // The strip is drawn in a band reserved ABOVE the client, so a snap whose
    // target starts at the work area's top edge has to be inset by that band —
    // for the drag preview and the release-time snap alike, which share this
    // one call. Without this the strip lands under the Omarchy bar.
    const double RESERVE = 34.0;
    const auto   rTL     = decideZone(5, 5, FRAME, AREA, RESERVE);
    check("reserve: TL still the top-left corner", rTL.zone == Zone::CornerTL);
    check("reserve: TL pushed down by the band", near(rTL.target.y, 34.0));
    check("reserve: TL height loses the band", near(rTL.target.h, 540.0 - 34.0));
    check("reserve: TL keeps half width", near(rTL.target.w, 960.0));
    check("reserve: TL x not inset (band is top-only)", near(rTL.target.x, 0.0));

    const auto rTR = decideZone(1915, 5, FRAME, AREA, RESERVE);
    check("reserve: TR pushed down by the band", near(rTR.target.y, 34.0));
    check("reserve: TR stays flush right", near(rTR.target.x, 960.0));

    const auto rLeft = decideZone(5, 500, FRAME, AREA, RESERVE);
    check("reserve: left half pushed down", near(rLeft.target.y, 34.0));
    check("reserve: left half height loses the band", near(rLeft.target.h, 1080.0 - 34.0));
    check("reserve: left half flush left", near(rLeft.target.x, 0.0));

    const auto rRight = decideZone(1915, 500, FRAME, AREA, RESERVE);
    check("reserve: right half pushed down", near(rRight.target.y, 34.0));
    check("reserve: halves stay flush at the seam", near(rLeft.target.x + rLeft.target.w, rRight.target.x));

    // Bottom corners must NOT be inset: a bottom tile already clears the bar.
    const auto rBL = decideZone(5, 1075, FRAME, AREA, RESERVE);
    check("reserve: bottom-left not inset", near(rBL.target.y, 540.0) && near(rBL.target.h, 540.0));

    // No reserve (strip disabled or hidden) reproduces the old flush behaviour.
    const auto flush = decideZone(5, 500, FRAME, AREA);
    check("reserve 0 -> flush", near(flush.target.y, 0.0) && near(flush.target.h, 1080.0));

    // A reserve taller than the target is clamped to a valid, non-negative box.
    const auto tiny = decideZone(5, 500, FRAME, AREA, 5000.0);
    check("reserve clamped to a valid box", tiny.target.h >= 1.0 && tiny.target.y > 0.0);

    // Top edge still means maximize, reserve or not (no rect is applied).
    const auto topReserved = decideZone(500, 5, FRAME, AREA, RESERVE);
    check("reserve: top edge still maximizes", topReserved.zone == Zone::Top && topReserved.maximize);

    // The preview and the release pass the same reserve: identical geometry.
    const auto preview = decideZone(1915, 500, FRAME, AREA, RESERVE);
    const auto release = decideZone(1915, 500, FRAME, AREA, RESERVE);
    check("preview geometry == release geometry",
          near(preview.target.x, release.target.x) && near(preview.target.y, release.target.y) && near(preview.target.w, release.target.w) && near(preview.target.h, release.target.h));

    // --- glow state machine ---
    State s;

    // Entering a zone starts the glow and it ramps up smoothly.
    s.setZone(tl);
    check("enter zone -> goal set", near(s.glow(), 0.0)); // not yet ticked
    s.tick(45.0);
    check("glow ramps up partway", near(s.glow(), 0.5));
    check("glowing while ramping", s.glowing());
    check("zone() reports active zone", s.zone() == Zone::CornerTL);
    s.tick(45.0);
    check("glow reaches full", near(s.glow(), 1.0));

    // Leaving the zone clears it and the glow fades back down.
    s.setZone(ZoneResult{});
    check("leave zone -> zone none immediately", s.zone() == Zone::None);
    s.tick(80.0);
    check("glow ramps down partway", near(s.glow(), 0.5));
    s.tick(80.0);
    check("glow returns to zero", near(s.glow(), 0.0));
    check("not glowing after clear", !s.glowing());
    check("not animating after settle", !s.animating());

    // A snap flash decays over the configured duration.
    s.flash(260);
    check("flash starts full", near(s.intensity(), 1.0) && near(s.flashIntensity(), 1.0));
    s.tick(65.0);
    check("flash decays (1/4 gone)", near(s.flashIntensity(), 0.75));
    s.tick(130.0);
    check("flash decays (3/4 gone)", near(s.flashIntensity(), 0.25));
    s.tick(65.0);
    check("flash fully decayed", near(s.flashIntensity(), 0.0));
    check("flash done -> not animating", !s.animating());

    // A zero/negative duration still clears cleanly.
    s.flash(0);
    check("zero-duration flash is safe", near(s.intensity(), 0.0));

    // snap_glow=false disables everything.
    State disabled;
    disabled.glowEnabled = false;
    disabled.setZone(tl);
    disabled.tick(100.0);
    check("disabled: no glow", near(disabled.glow(), 0.0));
    check("disabled: not glowing", !disabled.glowing());
    check("disabled: zone reports none", disabled.zone() == Zone::None);
    disabled.flash(260);
    check("disabled: flash suppressed", near(disabled.intensity(), 0.0));

    // The enabled glow must win over a disabled flash in intensity().
    State mixed;
    mixed.glowEnabled = true;
    mixed.setZone(tl);
    mixed.tick(90.0); // full glow
    mixed.flash(260); // flash starts at 1.0, glow at 1.0 -> intensity 1.0
    check("intensity = max(glow, flash)", near(mixed.intensity(), 1.0));

    std::printf("\n%d case(s) failed\n", g_failures);
    return g_failures == 0 ? 0 : 1;
}
