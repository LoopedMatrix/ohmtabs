#include "snapfx.hpp"

// Compositor glue for the snap effect: theme-aware accent colour resolution,
// frame-edge blending, and the snap.status IPC snapshot. Everything that
// needs a live window, the theme or the GL types lives here; the pure logic
// stays in snapfx.hpp so the unit test has no Hyprland dependency.

#include "bar.hpp"
#include "globals.hpp"

#include <hyprland/src/desktop/view/Window.hpp>
#include <hyprland/src/helpers/Color.hpp>

#include <format>

namespace SnapFx {

    CHyprColor glowColor(PHLWINDOW w) {
        // 1. Shell-pushed theme accent wins (same precedence as every other
        //    colour the strip uses).
        if (g_pGlobalState->shell.snapGlowColor)
            return CHyprColor{*g_pGlobalState->shell.snapGlowColor};

        // 2. plugin:grabbar:snap_glow_color when the user set it explicitly
        //    (0 is the "use the active border colour" default).
        if (const auto C = g_pGlobalState->config.snapGlowColor; C && C->value() != 0)
            return CHyprColor{static_cast<uint64_t>(C->value())};

        // 3. The user's active border colour — the theme accent. The gradient
        //    border's first stop is the flat-colour accent.
        if (w && !w->m_realBorderColor.m_colors.empty())
            return w->m_realBorderColor.m_colors.front();

        // 4. Last resort: bright white still reads as a "light up".
        return CHyprColor{1.0F, 1.0F, 1.0F, 1.0F};
    }

    CHyprColor blendFrameColor(const CHyprColor& base, const CHyprColor& accent, double intensity) {
        const double k = std::clamp(intensity, 0.0, 1.0);
        CHyprColor   out = base;
        out.r            = (float)(base.r + (accent.r - base.r) * k);
        out.g            = (float)(base.g + (accent.g - base.g) * k);
        out.b            = (float)(base.b + (accent.b - base.b) * k);
        // Keep the frame's own alpha (it already carries the window fade) so
        // the glow can never leak outside the frame's rounding/clipping.
        return out;
    }

    std::string statusJson() {
        bool        dragging = false;
        std::string zone     = "none";
        bool        glow     = false;

        // NOTE: decos are owned by a CUniquePointer (HyprlandAPI::addWindowDecoration),
        // so lock() would abort here - hyprutils asserts weak-over-unique.
        // get() is the non-owning, assert-free accessor (same as the other bars loops).
        for (const auto& wp : g_pGlobalState->bars) {
            auto* b = wp.get();
            if (!b || !b->isDragging())
                continue;
            dragging = true;
            zone     = zoneName(b->snapFx().zone());
            glow     = b->snapFx().glowing();
            break;
        }

        return std::format("{{\"dragging\":{},\"zone\":\"{}\",\"glow\":{}}}", dragging ? "true" : "false", zone, glow ? "true" : "false");
    }

} // namespace SnapFx
