#pragma once

// Snap visual effect: zone classification + glow/flash state machine.
//
// This header is PURE LOGIC — no Hyprland, no compositor, no I/O — so the
// standalone unit test (tests/test_snapfx.cpp) can exercise the exact state
// machine the decoration drives, without a session. The compositor glue
// (colour resolution, frame blending, IPC) lives in snapfx.cpp.
//
// The zone decision lives here in exactly one place: both the release-time
// snap (COhmTabsDeco::snapToZone) and the drag preview
// (COhmTabsDeco::updateSnapPreview) call decideZone(), so they can never
// disagree about where a pointer position would land.

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <string>

namespace SnapFx {

    // Trigger threshold in logical pixels, shared with snapToZone (was the
    // local `EDGE` constant there).
    constexpr double kEdge = 24.0;

    enum class Zone : int8_t {
        None = 0,
        Left,
        Right,
        Top,
        CornerTL,
        CornerTR,
        CornerBL,
        CornerBR,
    };

    // Stable zone names — the IPC contract for snap.status.
    inline const char* zoneName(Zone z) {
        switch (z) {
            case Zone::Left: return "left";
            case Zone::Right: return "right";
            case Zone::Top: return "top";
            case Zone::CornerTL: return "corner-tl";
            case Zone::CornerTR: return "corner-tr";
            case Zone::CornerBL: return "corner-bl";
            case Zone::CornerBR: return "corner-br";
            case Zone::None:
            default: return "none";
        }
    }

    struct Rect {
        double x = 0, y = 0, w = 0, h = 0;
    };

    struct ZoneResult {
        Zone zone     = Zone::None;
        Rect target;        // geometry the window would occupy (work-area coords)
        bool maximize = false; // top edge alone -> maximize, not a rect
    };

    // The title strip is drawn in a band reserved ABOVE the client — the deco
    // reports desiredExtents = {{0, HEIGHT}, {0, 0}} to the compositor — so a
    // zone whose target starts at the work area's top edge must push the client
    // down by that band, or the strip ends up hidden under the Omarchy bar. The
    // window border is drawn inside the client box, so only the top band needs
    // insetting; height is clamped to 1 px so a tiny work area still yields a
    // valid box.
    inline void applyTopInset(Rect& box, double inset) {
        if (inset <= 0.0 || box.h <= 1.0)
            return;
        const double dy = std::min(inset, box.h - 1.0);
        box.y += dy;
        box.h -= dy;
    }

    // Pure zone decision, identical to the release-time snap: corners first,
    // then left/right halves, then top -> maximize; bottom alone is "none".
    // `topInset` is the strip's reserved top band in logical pixels. The deco
    // passes the same value to the drag preview and to the release-time snap,
    // so the preview rectangle and the landing geometry can never disagree.
    inline ZoneResult decideZone(double px, double py, const Rect& frame, const Rect& area, double topInset = 0.0, double edge = kEdge) {
        ZoneResult r;

        const bool nearLeft   = px - frame.x <= edge;
        const bool nearRight  = (frame.x + frame.w) - px <= edge;
        const bool nearTop    = py - frame.y <= edge;
        const bool nearBottom = (frame.y + frame.h) - py <= edge;

        const bool cornerTL = nearTop && nearLeft;
        const bool cornerTR = nearTop && nearRight;
        const bool cornerBL = nearBottom && nearLeft;
        const bool cornerBR = nearBottom && nearRight;

        if (cornerTL || cornerTR || cornerBL || cornerBR) {
            Rect target = area;
            target.w /= 2.0;
            target.h /= 2.0;
            if (cornerTR || cornerBR)
                target.x += target.w;
            if (cornerBL || cornerBR)
                target.y += target.h;
            // Top corners start at the work area's top edge: pull them down by
            // the strip band so the strip clears the bar.
            if (cornerTL || cornerTR)
                applyTopInset(target, topInset);
            r.zone = cornerTL ? Zone::CornerTL : cornerTR ? Zone::CornerTR : cornerBL ? Zone::CornerBL : Zone::CornerBR;
            r.target = target;
            return r;
        }

        if (nearLeft) {
            Rect target = area;
            target.w /= 2.0;
            applyTopInset(target, topInset);
            r.zone   = Zone::Left;
            r.target = target;
            return r;
        }

        if (nearRight) {
            Rect target = area;
            target.x += target.w / 2.0;
            target.w /= 2.0;
            applyTopInset(target, topInset);
            r.zone   = Zone::Right;
            r.target = target;
            return r;
        }

        if (nearTop) {
            r.zone     = Zone::Top;
            r.maximize = true;
            r.target   = area;
            return r;
        }

        r.zone = Zone::None;
        return r;
    }

    // Glow + flash state machine. Owned by each decoration; the render path
    // drives tick() with wall-clock deltas and reads intensity() to blend the
    // accent into the frame edge. All timing is explicit, so the unit test
    // can step it deterministically.
    class State {
      public:
        bool glowEnabled    = true; // plugin:ohmtabs:snap_glow
        bool previewEnabled = true; // plugin:ohmtabs:snap_preview (reserved)

        // While dragging: called every time the pointer's zone changes.
        void setZone(const ZoneResult& r) {
            m_result = r;
            m_glowGoal = (glowEnabled && r.zone != Zone::None) ? 1.0 : 0.0;
            if (!glowEnabled)
                m_glow = 0.0;
        }

        // On a successful snap: a flash that decays over durationMs. A
        // non-positive duration means "no flash" (snap_glow_ms = 0).
        void flash(int durationMs) {
            if (!glowEnabled || durationMs <= 0) {
                m_flash         = 0.0;
                m_flashRemainMs  = 0.0;
                m_flashDurationMs = 1.0;
                return;
            }
            m_flash           = 1.0;
            m_flashRemainMs   = (double)durationMs;
            m_flashDurationMs = (double)durationMs;
        }

        // Drag ended (or cancelled) with no snap: clear preview and flash.
        void clear() {
            m_result         = ZoneResult{};
            m_glow           = 0.0;
            m_glowGoal       = 0.0;
            m_flash          = 0.0;
            m_flashRemainMs  = 0.0;
        }

        // Advance the animation by dtMs (>= 0).
        void tick(double dtMs) {
            if (dtMs < 0)
                dtMs = 0;

            if (m_glow < m_glowGoal) {
                const double step = m_glowUpMs > 0 ? dtMs / m_glowUpMs : 1.0;
                m_glow            = std::min(m_glowGoal, m_glow + step);
            } else if (m_glow > m_glowGoal) {
                const double step = m_glowDownMs > 0 ? dtMs / m_glowDownMs : 1.0;
                m_glow            = std::max(m_glowGoal, m_glow - step);
            }

            if (m_flashRemainMs > 0.0) {
                m_flashRemainMs = std::max(0.0, m_flashRemainMs - dtMs);
                m_flash         = m_flashDurationMs > 0.0 ? m_flashRemainMs / m_flashDurationMs : 0.0;
            }

            if (!glowEnabled) {
                m_glow          = 0.0;
                m_glowGoal      = 0.0;
                m_flash         = 0.0;
                m_flashRemainMs = 0.0;
            }
        }

        Zone zone() const { return glowEnabled ? m_result.zone : Zone::None; }
        double glow() const { return m_glow; }
        double flashIntensity() const { return m_flash; }
        double intensity() const { return std::max(m_glow, m_flash); }
        bool   glowing() const { return intensity() > 0.0005; }
        bool   animating() const { return m_flashRemainMs > 0.0 || m_glow != m_glowGoal; }
        const Rect& target() const { return m_result.target; }
        bool   maximize() const { return m_result.maximize; }

      private:
        ZoneResult m_result;
        double     m_glow            = 0.0;
        double     m_glowGoal        = 0.0;
        double     m_flash           = 0.0;
        double     m_flashRemainMs   = 0.0;
        double     m_flashDurationMs = 1.0;
        double     m_glowUpMs        = 90.0;  // fade-in
        double     m_glowDownMs      = 160.0; // fade-out
    };

} // namespace SnapFx
