#include "bar.hpp"
#include "snapfx.hpp"

#include <hyprland/src/Compositor.hpp>
#include <hyprland/src/desktop/state/FocusState.hpp>
#include <hyprland/src/desktop/state/WindowState.hpp>
#include <hyprland/src/desktop/state/LayerState.hpp>
#include <hyprland/src/desktop/state/ViewHitTester.hpp>
#include <hyprland/src/desktop/view/Window.hpp>
#include <hyprland/src/desktop/view/LayerSurface.hpp>
#include <hyprland/src/helpers/MiscFunctions.hpp>
#include <hyprland/src/managers/SeatManager.hpp>
#include <hyprland/src/managers/KeybindManager.hpp>
#include <hyprland/src/managers/input/InputManager.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/config/ConfigManager.hpp>
#include <hyprland/src/config/ConfigValue.hpp>
#include <hyprland/src/config/shared/animation/AnimationTree.hpp>
#include <hyprland/src/config/shared/parserUtils/ParserUtils.hpp>
#include <hyprland/src/config/shared/actions/ConfigActions.hpp>
#include <hyprland/src/animation/AnimationManager.hpp>
#include <hyprland/src/protocols/LayerShell.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/layout/LayoutManager.hpp>
#include <hyprland/src/render/OpenGL.hpp>
#include <hyprland/src/state/MonitorState.hpp>
#include <hyprland/src/debug/log/Logger.hpp>

#include "backend.hpp"
#include "pass.hpp"

#include <cairo/cairo.h>

#include <climits>
#include <cmath>
#include <format>

using namespace Render::GL;

static CHyprColor configColor(Config::INTEGER color) {
    return CHyprColor{static_cast<uint64_t>(color)};
}

// Appearance values: what the shell pushed (Omarchy theme / Settings) wins
// over the plugin:ohmtabs:* config values.
namespace {
    CHyprColor colorOf(const std::optional<uint64_t>& pushed, const SP<Config::Values::CColorValue>& cfg) {
        return pushed ? CHyprColor{*pushed} : configColor(cfg->value());
    }
    int barHeightValue() {
        const auto& S = g_pGlobalState->shell;
        return std::clamp<int>(S.barHeight.value_or(g_pGlobalState->config.barHeight->value()), 0, 200);
    }
    int buttonSizeValue() {
        const auto& S = g_pGlobalState->shell;
        return std::clamp<int>(S.buttonSize.value_or(g_pGlobalState->config.buttonSize->value()), 24, 64);
    }
    bool buttonsLeftValue() {
        const auto& S = g_pGlobalState->shell;
        return S.buttonsLeft.value_or(g_pGlobalState->config.buttonsLeft->value());
    }
    std::string textFontValue() {
        const auto& S = g_pGlobalState->shell;
        return S.textFont.value_or(g_pGlobalState->config.textFont->value());
    }
    bool tabsValue() {
        return g_pGlobalState->config.tabs->value();
    }
    int tabMinWidthValue() {
        return std::clamp<int>(g_pGlobalState->config.tabMinWidth->value(), 48, 640);
    }
}

// Control glyphs are drawn as paths (spec §3.3): no icon font is needed and
// they stay crisp at every output scale. `px` is the glyph box in buffer
// pixels; strokes are ~1/8 of it with round caps.
static SP<Render::ITexture> drawGlyph(eOhmTabsButton b, bool maximized, int px, const CHyprColor& color) {
    px = std::max(px, 4);
    auto* surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, px, px);
    auto* cr      = cairo_create(surface);
    cairo_set_operator(cr, CAIRO_OPERATOR_CLEAR);
    cairo_paint(cr);
    cairo_set_operator(cr, CAIRO_OPERATOR_OVER);
    cairo_set_source_rgba(cr, color.r, color.g, color.b, color.a);
    const double S = px;
    const double W = std::max(1.0, std::round(S / 8.0));
    cairo_set_line_width(cr, W);
    cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND);
    cairo_set_line_join(cr, CAIRO_LINE_JOIN_ROUND);
    const double m = std::round(S * 0.18) + 0.5; // margin
    const double e = S - m;                       // far edge
    switch (b) {
        case BTN_MENU:
            cairo_set_line_width(cr, std::max(1.0, std::round(S / 10.0)));
            for (double y : {S * 0.24, S * 0.5, S * 0.76}) {
                cairo_move_to(cr, m, std::round(y) + 0.5);
                cairo_line_to(cr, e, std::round(y) + 0.5);
            }
            cairo_stroke(cr);
            break;
        case BTN_MINIMIZE:
            cairo_move_to(cr, m, std::round(S * 0.58) + 0.5);
            cairo_line_to(cr, e, std::round(S * 0.58) + 0.5);
            cairo_stroke(cr);
            break;
        case BTN_MAXIMIZE:
            if (!maximized) {
                cairo_rectangle(cr, m, m, e - m, e - m);
                cairo_stroke(cr);
            } else {
                // Restore size: two offset squares, the front one complete.
                const double off = std::round(S * 0.16);
                cairo_rectangle(cr, m, m + off, e - m - off, e - m - off);
                cairo_stroke(cr);
                cairo_move_to(cr, m + off, m + off);
                cairo_line_to(cr, m + off, m);
                cairo_line_to(cr, e, m);
                cairo_line_to(cr, e, e - off);
                cairo_line_to(cr, e - off, e - off);
                cairo_stroke(cr);
            }
            break;
        case BTN_CLOSE:
            cairo_move_to(cr, m, m);
            cairo_line_to(cr, e, e);
            cairo_move_to(cr, e, m);
            cairo_line_to(cr, m, e);
            cairo_stroke(cr);
            break;
        default: break;
    }
    cairo_surface_flush(surface);
    auto tex = g_pHyprRenderer->createTexture(surface);
    cairo_destroy(cr);
    cairo_surface_destroy(surface);
    return tex;
}

COhmTabsDeco::COhmTabsDeco(PHLWINDOW pWindow) : IHyprWindowDecoration(pWindow) {
    m_window = pWindow;

    if (const auto PMONITOR = pWindow->m_monitor.lock(); PMONITOR)
        PMONITOR->m_scheduledRecalc = true;

    m_mouseButtonCallback = Event::bus()->m_events.input.mouse.button.listen([this](IPointer::SButtonEvent e, Event::SCallbackInfo& info) { onMouseButton(info, e); });
    m_mouseMoveCallback   = Event::bus()->m_events.input.mouse.move.listen([this](Vector2D c, Event::SCallbackInfo& info) { onMouseMove(c); });

    Animation::mgr()->createAnimation(colorOf(g_pGlobalState->shell.barColor, g_pGlobalState->config.barColor), m_realBarColor,
                                      Config::animationTree()->getAnimationPropertyConfig("border"), pWindow, AVARDAMAGE_NONE);
    m_realBarColor->setUpdateCallback([this](auto) { damageEntire(); });
}

COhmTabsDeco::~COhmTabsDeco() {
    std::erase(g_pGlobalState->bars, m_self);
}

bool COhmTabsDeco::effectiveEnabled() {
    if (!g_pGlobalState->config.enabled->value() || m_hidden || !g_pBackend || g_pBackend->suspended() || g_pBackend->paused())
        return false;
    // In "show on hover" mode the strip stays logically enabled (so it can
    // receive input and reveal itself) even while it is visually hidden.
    if (m_showOnHover && g_pGlobalState->shell.showOnHover && !g_pGlobalState->config.showOnHover->value())
        return false;
    // A `nodecoration` window rule means no strip and no reserved space.
    const auto PWINDOW = m_window.lock();
    if (PWINDOW && !PWINDOW->m_ruleApplicator->decorate().valueOrDefault())
        return false;
    return true;
}

SDecorationPositioningInfo COhmTabsDeco::getPositioningInfo() {
    const auto                 HEIGHT  = barHeightValue();
    const bool                 ENABLED = effectiveEnabled();

    SDecorationPositioningInfo info;
    info.policy         = ENABLED ? DECORATION_POSITION_STICKY : DECORATION_POSITION_ABSOLUTE;
    info.edges          = DECORATION_EDGE_TOP;
    info.priority       = 5000;
    info.reserved       = true;
    info.desiredExtents = {{0, ENABLED ? HEIGHT : 0}, {0, 0}};
    return info;
}

void COhmTabsDeco::onPositioningReply(const SDecorationPositioningReply& reply) {
    if (reply.assignedGeometry.size() != m_assignedBox.size())
        m_windowSizeChanged = true;

    m_assignedBox = reply.assignedGeometry;
}

std::string COhmTabsDeco::getDisplayName() {
    return "OhmTabs";
}

// ----------------------------------------------------------------- layout

std::vector<SButtonSlot> COhmTabsDeco::layoutButtons(double barW, double barH) {
    const int  SIZE = buttonSizeValue();
    const int  PAD  = std::clamp<int>(g_pGlobalState->config.padding->value(), 0, 32);
    const bool LEFT = buttonsLeftValue();
    const double y  = std::floor((barH - SIZE) / 2.0);

    std::vector<SButtonSlot> slots;

    // Narrow window: keep only the window-menu target (spec §3.3).
    const bool NARROW = barW < PAD * 2 + SIZE * 4 + 24;

    if (!LEFT) {
        if (!NARROW) {
            double x = barW - PAD - SIZE * 3;
            for (auto b : {BTN_MINIMIZE, BTN_MAXIMIZE, BTN_CLOSE}) {
                slots.push_back({b, CBox{x, y, (double)SIZE, (double)SIZE}});
                x += SIZE;
            }
        }
        slots.push_back({BTN_MENU, CBox{(double)PAD, y, (double)SIZE, (double)SIZE}});
    } else {
        if (!NARROW) {
            double x = PAD;
            for (auto b : {BTN_CLOSE, BTN_MINIMIZE, BTN_MAXIMIZE}) {
                slots.push_back({b, CBox{x, y, (double)SIZE, (double)SIZE}});
                x += SIZE;
            }
        }
        slots.push_back({BTN_MENU, CBox{barW - PAD - SIZE, y, (double)SIZE, (double)SIZE}});
    }

    if (NARROW && barW < PAD * 2 + SIZE)
        slots.clear();

    return slots;
}

eOhmTabsButton COhmTabsDeco::buttonAt(const Vector2D& rel) {
    const auto BOX = assignedBoxGlobal();
    for (const auto& s : layoutButtons(BOX.w, BOX.h)) {
        if (s.box.containsPoint(rel))
            return s.id;
    }
    return BTN_NONE;
}

// -------------------------------------------------------------- window tabs

std::vector<STabBox> COhmTabsDeco::layoutTabs(double barW, double barH) {
    m_tabBoxes.clear();
    if (!tabsValue())
        return m_tabBoxes;

    const auto PWINDOW = m_window.lock();
    if (!validMapped(PWINDOW))
        return m_tabBoxes;

    const auto TOKEN = g_pBackend->tokenFor(PWINDOW);
    const auto G     = g_pBackend->tabs().hostGroup(TOKEN);
    if (!G || G->tabs.size() < 2)
        return m_tabBoxes;

    const int  SIZE = buttonSizeValue();
    const int  PAD  = std::clamp<int>(g_pGlobalState->config.padding->value(), 0, 32);
    const bool LEFT = buttonsLeftValue();
    const double y  = std::floor((barH - SIZE) / 2.0);

    // Free area between the menu target and the min/max/close cluster — the
    // same bounds the centered title uses, so tabs never overlap the buttons
    // or the narrow-window fallback in layoutButtons.
    double occupiedLeft = 0, occupiedRight = 0;
    for (const auto& s : layoutButtons(barW, barH)) {
        if (s.id == BTN_MENU && !LEFT)
            occupiedLeft = std::max(occupiedLeft, s.box.x + s.box.w);
        else if (s.id == BTN_MENU)
            occupiedRight = std::max(occupiedRight, barW - s.box.x);
        else if (LEFT)
            occupiedLeft = std::max(occupiedLeft, s.box.x + s.box.w);
        else
            occupiedRight = std::max(occupiedRight, barW - s.box.x);
    }

    const double leftEdge  = occupiedLeft + PAD;
    const double rightEdge = barW - occupiedRight - PAD;
    const double avail     = rightEdge - leftEdge;
    const double minW      = (double)tabMinWidthValue();
    if (avail < minW)
        return m_tabBoxes; // too narrow for tabs: fall back to the plain title

    // Every tab gets at least minW, expanding evenly while space allows.
    const size_t n    = G->tabs.size();
    double       segW = std::max(minW, avail / (double)n);
    double       total = segW * (double)n;
    double       x     = leftEdge + std::max(0.0, (avail - total) / 2.0);

    for (size_t i = 0; i < n; ++i) {
        STabBox tb;
        tb.index  = (int)i;
        tb.active = (i == (size_t)G->active);
        tb.token  = G->tabs[i];
        tb.box    = CBox{x, y, segW, (double)SIZE};
        const double CS = std::max(12.0, SIZE * 0.5);
        tb.closeBox     = CBox{x + segW - CS - 6, y + (SIZE - CS) / 2.0, CS, CS};
        m_tabBoxes.push_back(tb);
        x += segW;
    }
    return m_tabBoxes;
}

int COhmTabsDeco::tabAt(const Vector2D& rel) {
    const auto BOX = assignedBoxGlobal();
    layoutTabs(BOX.w, BOX.h);
    for (const auto& tb : m_tabBoxes)
        if (tb.box.containsPoint(rel))
            return tb.index;
    return -1;
}

bool COhmTabsDeco::tryJoinDrop() {
    const auto PWINDOW = m_window.lock();
    if (!validMapped(PWINDOW))
        return false;

    const auto MOUSE = g_pInputManager->getMouseCoordsInternal();
    Desktop::CViewHitTester hitTester{*Desktop::viewState()};

    // The dragged window follows the pointer, so skip it to find the window
    // underneath: that is the drop target this window joins as a tab of.
    auto target = hitTester.windowAt(MOUSE, Desktop::View::RESERVED_EXTENTS | Desktop::View::INPUT_EXTENTS | Desktop::View::ALLOW_FLOATING, PWINDOW);
    if (!target || target == PWINDOW)
        return false;

    const auto TARGETTOKEN = g_pBackend->tokenFor(target);
    if (TARGETTOKEN.empty() || TARGETTOKEN == m_pressToken)
        return false;

    std::string err;
    const auto  st = g_pBackend->joinTabs(m_pressToken, TARGETTOKEN, err);
    if (st != ACTION_OK)
        Log::logger->log(Log::DEBUG, "[ohmtabs] drop-join {} -> {} refused: {}", m_pressToken, TARGETTOKEN, err);
    return st == ACTION_OK;
}

void COhmTabsDeco::startTabTearOff(const std::string& token) {
    std::string err;
    if (g_pBackend->detachTab(token, err) != ACTION_OK) {
        Log::logger->log(Log::WARN, "[ohmtabs] tab tear-off failed: {}", err);
        m_tabTearOff = false;
        m_tearToken.clear();
        return;
    }

    // The detached tab is now a floating, focused window; grab it for a move.
    auto w = g_pBackend->resolve(token);
    if (!w || !validMapped(w)) {
        m_tabTearOff = false;
        m_tearToken.clear();
        return;
    }
    if (!w->m_isFloating)
        (void)Config::Actions::floatWindow(Config::Actions::TOGGLE_ACTION_ENABLE, w);
    if (Desktop::focusState()->window() != w)
        Desktop::focusState()->fullWindowFocus(w, Desktop::FOCUS_REASON_CLICK);
    Desktop::windowState()->raise(w);

    g_pKeybindManager->changeMouseBindMode(MBIND_MOVE);
    m_dragging = true;
    Log::logger->log(Log::DEBUG, "[ohmtabs] tab tear-off drag on {}", token);
}

// ------------------------------------------------------------------ input

bool COhmTabsDeco::inputIsValid() {
    if (!effectiveEnabled())
        return false;

    const auto PWINDOW = m_window.lock();
    if (!validMapped(PWINDOW))
        return false;

    if (g_pSeatManager->m_seatGrab && !g_pSeatManager->m_seatGrab->accepts(PWINDOW->wlSurface()->resource()))
        return false;

    const auto MOUSE    = g_pInputManager->getMouseCoordsInternal();
    auto       PMONITOR = Desktop::focusState()->monitor();

    if (!PMONITOR)
        return false;

    Desktop::CViewHitTester hitTester{*Desktop::viewState()};

    const auto WINDOWATCURSOR = hitTester.windowAt(MOUSE, Desktop::View::RESERVED_EXTENTS | Desktop::View::INPUT_EXTENTS | Desktop::View::ALLOW_FLOATING);

    if (WINDOWATCURSOR != PWINDOW && PWINDOW != Desktop::focusState()->window())
        return false;

    PHLLS    foundSurface = nullptr;
    Vector2D surfaceCoords;

    hitTester.layerSurfaceAt(MOUSE, &PMONITOR->m_layerSurfaceLayers[ZWLR_LAYER_SHELL_V1_LAYER_TOP], &surfaceCoords, &foundSurface);
    if (foundSurface)
        return false;

    hitTester.layerSurfaceAt(MOUSE, &PMONITOR->m_layerSurfaceLayers[ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY], &surfaceCoords, &foundSurface);
    if (foundSurface)
        return false;

    return true;
}

void COhmTabsDeco::onMouseButton(Event::SCallbackInfo& info, IPointer::SButtonEvent e) {
    if (e.button != BTN_LEFT) {
        // A drag in progress ends on any release so a stray button cannot
        // leave the window glued to the pointer.
        if (e.state != WL_POINTER_BUTTON_STATE_PRESSED && m_dragging)
            endDrag();
        // Secondary click anywhere on the strip opens the window menu: the
        // same text actions as the menu button (spec §3.4).
        if (e.button == BTN_RIGHT && e.state == WL_POINTER_BUTTON_STATE_PRESSED && !m_dragging && !m_dragPending && inputIsValid()) {
            const auto BOX    = assignedBoxGlobal();
            const auto COORDS = cursorRelativeToBar();
            if (VECINRECT(COORDS, 0, 0, BOX.w, BOX.h - 1)) {
                const auto PWINDOW = m_window.lock();
                if (Desktop::focusState()->window() != PWINDOW)
                    Desktop::focusState()->fullWindowFocus(PWINDOW, Desktop::FOCUS_REASON_CLICK);
                info.cancelled = true;
                g_pBackend->menuRequest(g_pBackend->tokenFor(PWINDOW), g_pInputManager->getMouseCoordsInternal());
            }
        }
        return;
    }

    if (e.state != WL_POINTER_BUTTON_STATE_PRESSED) {
        // Release is handled even when the pointer left the strip: that is
        // exactly how "press Close, drag away, release" cancels.
        if (m_pressedButton != BTN_NONE || m_dragPending || m_dragging || m_cancelledDown)
            handleUpEvent(info);
        return;
    }

    if (!inputIsValid())
        return;

    handleDownEvent(info);
}

void COhmTabsDeco::handleDownEvent(Event::SCallbackInfo& info) {
    const auto PWINDOW = m_window.lock();
    if (!validMapped(PWINDOW))
        return;

    const auto BOX    = assignedBoxGlobal();
    const auto COORDS = cursorRelativeToBar();

    if (!VECINRECT(COORDS, 0, 0, BOX.w, BOX.h - 1)) {
        if (m_dragging)
            endDrag();
        m_dragPending   = false;
        m_pressedButton = BTN_NONE;
        return;
    }

    if (Desktop::focusState()->window() != PWINDOW)
        Desktop::focusState()->fullWindowFocus(PWINDOW, Desktop::FOCUS_REASON_CLICK);

    if (PWINDOW->m_isFloating)
        Desktop::windowState()->raise(PWINDOW);

    info.cancelled  = true;
    m_cancelledDown = true;

    const auto TOKEN = g_pBackend->tokenFor(PWINDOW);
    const auto BTN   = buttonAt(COORDS);

    if (BTN != BTN_NONE) {
        m_pressedButton     = BTN;
        m_pressToken        = TOKEN;
        m_lastPressWasTitle = false;
        m_dragPending       = false;
        damageEntire();
        return;
    }

    // Tab segment: a click activates the tab, its close affordance closes just
    // that window, and dragging a non-active segment tears it out of the group.
    if (const int TAB = tabAt(COORDS); TAB >= 0) {
        const auto& TB      = m_tabBoxes[TAB];
        m_pressedTab        = TAB;
        m_pressedTabClose   = TB.closeBox.containsPoint(COORDS);
        m_pressToken        = TB.token;
        m_lastPressWasTitle = false;
        m_tabTearOff        = !TB.active && !m_pressedTabClose;
        m_tearToken         = m_tabTearOff ? TB.token : "";
        m_dragPending       = !m_pressedTabClose;
        m_pressPos          = g_pInputManager->getMouseCoordsInternal();
        m_pressOffset       = COORDS;
        damageEntire();
        return;
    }

    // Title region: double-click toggles Maximize / Restore size, otherwise a
    // drag may start once the pointer travels past the threshold.
    const auto NOW = Time::steadyNow();
    const bool DOUBLE =
        m_lastPressWasTitle && std::chrono::duration_cast<std::chrono::milliseconds>(NOW - m_lastTitlePress).count() < 400;

    m_lastTitlePress    = NOW;
    m_lastPressWasTitle = true;
    m_pressedButton     = BTN_NONE;
    m_pressToken        = TOKEN;

    if (DOUBLE) {
        m_lastPressWasTitle = false;
        m_dragPending       = false;
        std::string err;
        g_pBackend->setMaximized(TOKEN, std::nullopt, err);
        return;
    }

    m_pressPos    = g_pInputManager->getMouseCoordsInternal();
    m_pressOffset = COORDS;
    m_dragPending = true;
}

void COhmTabsDeco::handleUpEvent(Event::SCallbackInfo& info) {
    if (m_cancelledDown)
        info.cancelled = true;
    m_cancelledDown = false;

    if (m_pressedButton != BTN_NONE) {
        const auto BTN   = m_pressedButton;
        const auto TOKEN = m_pressToken;
        m_pressedButton  = BTN_NONE;
        m_pressToken.clear();
        damageEntire();

        // Act only when released inside the same target on the same window.
        if (buttonAt(cursorRelativeToBar()) == BTN && inputIsValid()) {
            if (g_pBackend->resolve(TOKEN))
                activate(BTN, TOKEN);
            else
                Log::logger->log(Log::DEBUG, "[ohmtabs] release ignored: stale target {}", TOKEN);
        } else
            Log::logger->log(Log::DEBUG, "[ohmtabs] release outside target: cancelled");
    }

    // Tab release: activate, or close just that tab, only when released on the
    // same segment (a tab press consumed by a drag clears m_pressedTab).
    if (m_pressedTab >= 0) {
        const bool        CLOSE = m_pressedTabClose;
        const std::string TOKEN = m_pressToken;
        m_pressedTab      = -1;
        m_pressedTabClose = false;
        m_tabTearOff      = false;
        m_tearToken.clear();
        damageEntire();
        if (inputIsValid()) {
            const int REL = tabAt(cursorRelativeToBar());
            if (REL >= 0 && m_tabBoxes[REL].token == TOKEN) {
                std::string err;
                if (CLOSE)
                    g_pBackend->closeWindow(TOKEN, err);
                else
                    g_pBackend->activateTabByToken(TOKEN, err);
            }
        }
    }

    if (m_dragging) {
        endDrag();
        // Glow comes from config, same as the preview.
        m_snapFx.glowEnabled = g_pGlobalState->config.snapGlow->value();

        // A drop onto another window wins over the snap; a tear-off drag
        // commits nothing here.
        if (m_tabTearOff) {
            m_tabTearOff = false;
            m_tearToken.clear();
            // Tear-off drag: the detached tab is dropped where the pointer is.
        } else if (tabsValue() && tryJoinDrop()) {
            // Dropped onto another window: it just became a tab group (no snap).
        } else if (snapToZone()) {
            m_snapFx.flash(std::clamp<int>(g_pGlobalState->config.snapGlowMs->value(), 0, 5000));
        }

        m_snapFx.setZone(SnapFx::ZoneResult{}); // clear the drag preview glow
        m_snapFxLastTick = Time::steadyNow();
        damageEntire();
    }

    m_dragPending = false;
}

void COhmTabsDeco::onMouseMove(Vector2D coords) {
    if (!validMapped(m_window))
        return;

    // Hover feedback, only when this strip is what the pointer is really over
    // (an overlapping floating window or a layer surface must not light it up).
    auto HB = effectiveEnabled() ? buttonAt(cursorRelativeToBar()) : BTN_NONE;
    if (HB != BTN_NONE && !inputIsValid())
        HB = BTN_NONE;
    if (HB != m_hoverButton) {
        m_hoverButton = HB;
        damageEntire();
    }

    if (m_dragging) {
        updateSnapPreview();
        return;
    }

    if (!m_dragPending)
        return;

    static auto PDRAGTHRESHOLD = CConfigValue<Config::INTEGER>("binds:drag_threshold");
    const double THRESHOLD     = *PDRAGTHRESHOLD > 0 ? (double)*PDRAGTHRESHOLD : 6.0;

    const auto MOUSE = g_pInputManager->getMouseCoordsInternal();
    if ((MOUSE - m_pressPos).size() < THRESHOLD)
        return;

    m_dragPending = false;
    if (m_tabTearOff)
        startTabTearOff(m_tearToken);
    else
        startDrag();
}

void COhmTabsDeco::startDrag() {
    const auto PWINDOW = m_window.lock();
    if (!validMapped(PWINDOW))
        return;

    if (!g_pBackend->resolve(m_pressToken))
        return;

    std::string err;
    const auto  OLDSIZE   = PWINDOW->size(Desktop::View::IGeometric::GEOMETRIC_GOAL);
    bool        reposition = false;

    // Dragging a maximized window first gives it a usable size (spec §4.4).
    if (g_pBackend->isMaximized(PWINDOW)) {
        g_pBackend->setMaximized(m_pressToken, false, err);
        reposition = PWINDOW->m_isFloating;
    }

    // Dragging a tiled window detaches it into floating mode, then follows
    // the pointer (spec §4.4).
    if (!PWINDOW->m_isFloating) {
        (void)Config::Actions::floatWindow(Config::Actions::TOGGLE_ACTION_ENABLE, PWINDOW);
        reposition = true;
    }

    if (reposition) {
        // Keep the strip under the pointer so the native move grabs this
        // window and not whatever the layout put there, keep the pointer over
        // the same proportional point of the strip, and keep the strip inside
        // the work area.
        const auto MOUSE = g_pInputManager->getMouseCoordsInternal();
        auto       size  = PWINDOW->size(Desktop::View::IGeometric::GEOMETRIC_GOAL);
        CBox       area  = {0, 0, 0, 0};
        if (const auto MON = PWINDOW->m_monitor.lock(); MON) {
            area = MON->logicalBoxMinusReserved();
            if (area.w <= 0 || area.h <= 0)
                area = MON->logicalBox();
        }

        // A window that filled its layout slot gets a usable floating size.
        if (area.w > 0 && area.h > 0 && (size.x > area.w * 0.8 || size.y > area.h * 0.8)) {
            size = Vector2D{std::round(area.w * 0.6), std::round(area.h * 0.6)};
            (void)Config::Actions::resize(size, false, PWINDOW);
        }

        const double ratio  = OLDSIZE.x > 0 ? std::clamp(m_pressOffset.x / OLDSIZE.x, 0.0, 1.0) : 0.5;
        Vector2D     target = {MOUSE.x - ratio * size.x, MOUSE.y - m_pressOffset.y};
        if (area.w > 0 && area.h > 0) {
            target.x = std::clamp(target.x, area.x, std::max(area.x, area.x + area.w - size.x));
            target.y = std::clamp(target.y, area.y, std::max(area.y, area.y + area.h - 40.0));
        }
        (void)Config::Actions::move(target, false, PWINDOW);
    }

    g_pKeybindManager->changeMouseBindMode(MBIND_MOVE);
    m_dragging = true;
    m_pressedTab      = -1; // a tab press consumed by the drag is no longer a click
    m_pressedTabClose = false;
    Log::logger->log(Log::DEBUG, "[ohmtabs] drag started on {}", m_pressToken);
}

void COhmTabsDeco::endDrag() {
    g_pKeybindManager->changeMouseBindMode(MBIND_INVALID);
    m_dragging = false;
    Log::logger->log(Log::DEBUG, "[ohmtabs] drag ended");
}

// ------------------------------------------------------------- snap lock

// Windows-style snap-lock on drag release. The zone is decided exactly once,
// here at release, from the pointer's position, so the compositor sees at
// most one resize+move (or one maximize) per drag. Nothing is issued per
// mouse-movement event while the pointer travels, which is why there is no
// throttle loop to tune: the release-time decision is inherently rate-limited
// to one transaction per drag.
//
// Edges are detected against the monitor's full frame (the "frame" the user
// drags toward), but the snapped geometry is sized from the work area so a
// maximized window keeps panels' reserved space, matching setMaximized. A
// snapped window is ordinary floating geometry, so the next drag is a plain
// move again: releasing away from an edge leaves the window where it was
// dropped, which is how a snap is undone.
bool COhmTabsDeco::snapToZone() {
    if (!g_pGlobalState->config.snapLock->value())
        return false;

    const auto PWINDOW = m_window.lock();
    if (!validMapped(PWINDOW) || !PWINDOW->m_isFloating)
        return false;

    // A tiled window was detached when the drag started (startDrag), so by
    // the time a drag ends it is floating; if it is not, the drag never
    // really moved and there is nothing to snap.
    auto MON = PWINDOW->m_monitor.lock();
    if (!MON)
        MON = Desktop::focusState()->monitor();
    if (!MON)
        return false;

    const CBox FRAME = MON->logicalBox();
    CBox       AREA  = MON->logicalBoxMinusReserved();
    if (AREA.w <= 0 || AREA.h <= 0)
        AREA = FRAME;

    const auto P = g_pInputManager->getMouseCoordsInternal();

    // The strip's reserved top band, in logical pixels — the same value
    // getPositioningInfo reports to the compositor (0 when the strip is
    // disabled or hidden, so those windows snap flush like before). Handed to
    // decideZone so the drag preview and the release-time snap agree.
    const double topReserve = effectiveEnabled() ? (double)barHeightValue() : 0.0;

    // Zone decision shared with the drag preview (updateSnapPreview) so the
    // preview and the release-time snap can never disagree about where the
    // pointer would land.
    const auto R = SnapFx::decideZone(P.x, P.y, {FRAME.x, FRAME.y, FRAME.w, FRAME.h}, {AREA.x, AREA.y, AREA.w, AREA.h}, topReserve);

    switch (R.zone) {
        case SnapFx::Zone::CornerTL:
        case SnapFx::Zone::CornerTR:
        case SnapFx::Zone::CornerBL:
        case SnapFx::Zone::CornerBR: {
            const CBox target = {R.target.x, R.target.y, R.target.w, R.target.h};
            (void)Config::Actions::resize(target.size(), false, PWINDOW);
            (void)Config::Actions::move(target.pos(), false, PWINDOW);
            return true;
        }
        case SnapFx::Zone::Left:
        case SnapFx::Zone::Right: {
            const CBox target = {R.target.x, R.target.y, R.target.w, R.target.h};
            (void)Config::Actions::resize(target.size(), false, PWINDOW);
            (void)Config::Actions::move(target.pos(), false, PWINDOW);
            return true;
        }
        case SnapFx::Zone::Top: {
            // Top edge means maximize: same typed call as the Maximize button and
            // the title double-click, so it shares their validation and reporting.
            std::string err;
            g_pBackend->setMaximized(m_pressToken, true, err);
            return true;
        }
        default:
            // A bottom edge alone does nothing: the window stays where it was dropped.
            return false;
    }
}

// While a drag is in progress, track the snap zone under the pointer and drive
// the frame-edge glow. Uses the same decideZone() as snapToZone(), so the
// preview and the release-time snap can never disagree.
void COhmTabsDeco::updateSnapPreview() {
    m_snapFx.glowEnabled    = g_pGlobalState->config.snapGlow->value();
    m_snapFx.previewEnabled = g_pGlobalState->config.snapPreview->value();

    const auto PWINDOW = m_window.lock();
    if (!validMapped(PWINDOW) || !PWINDOW->m_isFloating)
        return;

    auto MON = PWINDOW->m_monitor.lock();
    if (!MON)
        MON = Desktop::focusState()->monitor();
    if (!MON)
        return;

    const CBox FRAME = MON->logicalBox();
    CBox       AREA  = MON->logicalBoxMinusReserved();
    if (AREA.w <= 0 || AREA.h <= 0)
        AREA = FRAME;

    // The strip's reserved top band, in logical pixels — the same value
    // getPositioningInfo reports to the compositor (0 when the strip is
    // disabled or hidden, so those windows snap flush like before). Handed to
    // decideZone so the drag preview and the release-time snap agree.
    const double topReserve = effectiveEnabled() ? (double)barHeightValue() : 0.0;

    const auto P = g_pInputManager->getMouseCoordsInternal();
    const auto R = SnapFx::decideZone(P.x, P.y, {FRAME.x, FRAME.y, FRAME.w, FRAME.h}, {AREA.x, AREA.y, AREA.w, AREA.h}, topReserve);

    if (R.zone != m_snapFx.zone()) {
        m_snapFx.setZone(R);
        m_snapFxLastTick = Time::steadyNow();
        damageEntire();
    }
}

// Advance the glow/flash animation from wall-clock elapsed time. Driven from
// renderPass; the render loop keeps running while the state is animating.
void COhmTabsDeco::snapFxTick() {
    const auto   NOW = Time::steadyNow();
    const double DT  = std::clamp(std::chrono::duration<double, std::milli>(NOW - m_snapFxLastTick).count(), 0.0, 100.0);
    m_snapFxLastTick = NOW;
    m_snapFx.tick(DT);
}

// `token` was captured at press and re-validated at release: the action
// targets that window even if focus moved meanwhile (spec §4.1, test F02).
void COhmTabsDeco::activate(eOhmTabsButton b, const std::string& token) {
    std::string err;
    eActionStatus st = ACTION_OK;
    switch (b) {
        case BTN_MINIMIZE: g_pBackend->requestMinimize(token, "bar"); break;
        case BTN_MAXIMIZE: st = g_pBackend->setMaximized(token, std::nullopt, err); break;
        case BTN_CLOSE: st = g_pBackend->closeWindow(token, err); break;
        case BTN_MENU: g_pBackend->menuRequest(token, g_pInputManager->getMouseCoordsInternal()); break;
        default: break;
    }
    if (st != ACTION_OK)
        Log::logger->log(Log::WARN, "[ohmtabs] action {} failed: {} ({})", (int)b, err, (int)st);
}

// -------------------------------------------------------------- rendering

SP<Render::ITexture> COhmTabsDeco::glyph(eOhmTabsButton b, bool maximized, int size, const CHyprColor& color) {
    const auto KEY  = std::format("{}:{}:{}:{:x}", (int)b, maximized ? 1 : 0, size, color.getAsHex());
    auto&      slot = g_pGlobalState->glyphCache[KEY];
    if (!slot || slot->m_texID == 0)
        slot = drawGlyph(b, maximized, size, color);
    return slot;
}

void COhmTabsDeco::renderTitle(const Vector2D& bufferSize, const float scale, int maxWidth) {
    const auto COLOR = colorOf(g_pGlobalState->shell.textColor, g_pGlobalState->config.textColor);
    const auto SIZE  = std::clamp<int>(g_pGlobalState->config.textSize->value(), 6, 40);
    const auto FONT  = textFontValue();

    if (m_lastTitle.empty() || maxWidth < 8) {
        m_textTex = nullptr;
        return;
    }

    m_textTex = g_pHyprRenderer->renderText(m_lastTitle, COLOR, std::round(SIZE * scale), false, FONT, maxWidth);
}

void COhmTabsDeco::renderTabs(float a, const CBox& titleBarBox, float SCALE, int PAD, const CHyprColor& textColor, bool focused) {
    const auto SIZE = std::clamp<int>(g_pGlobalState->config.textSize->value(), 6, 40);
    const auto FONT = textFontValue();
    const auto HC   = colorOf(g_pGlobalState->shell.hoverColor, g_pGlobalState->config.hoverColor);

    for (const auto& tb : m_tabBoxes) {
        CBox b = tb.box;
        b.translate(Vector2D{titleBarBox.x / SCALE, titleBarBox.y / SCALE}).scale(SCALE).round();

        // Segment background: the active tab reads as the "selected" strip.
        if (tb.active) {
            auto bg = HC;
            bg.a *= a * 0.55;
            g_pHyprOpenGL->renderRect(b, bg, {.round = (int)std::round(6 * SCALE), .roundingPower = 2.F});
        }

        auto xc = textColor;
        if (!focused)
            xc.a *= 0.75;

        // Close affordance: a small x on the right edge of the segment.
        CBox cb = tb.closeBox;
        cb.translate(Vector2D{titleBarBox.x / SCALE, titleBarBox.y / SCALE}).scale(SCALE).round();
        auto xtex = g_pHyprRenderer->renderText("×", xc, std::round(12 * SCALE), false, FONT, (int)std::round(tb.closeBox.w * SCALE));
        if (xtex && xtex->m_texID != 0) {
            CBox pos = {cb.x + (cb.w - xtex->m_size.x) / 2.0, cb.y + (cb.h - xtex->m_size.y) / 2.0, (double)xtex->m_size.x, (double)xtex->m_size.y};
            pos.round();
            g_pHyprOpenGL->renderTexture(xtex, pos, {.a = a});
        }

        // Tab title, truncated to the segment minus the close affordance.
        auto              w     = g_pBackend->resolve(tb.token);
        const std::string title = w ? w->m_title : tb.token;
        const int         maxW  = std::max<int>(8, (int)std::round((tb.closeBox.x - tb.box.x - PAD) * SCALE));
        auto              ttex  = g_pHyprRenderer->renderText(title, xc, std::round(SIZE * SCALE), false, FONT, maxW);
        if (ttex && ttex->m_texID != 0) {
            CBox pos = {b.x + PAD * SCALE, b.y + (b.h - ttex->m_size.y) / 2.0, (double)ttex->m_size.x, (double)ttex->m_size.y};
            pos.round();
            g_pHyprOpenGL->renderTexture(ttex, pos, {.a = a});
        }
    }
}

void COhmTabsDeco::draw(PHLMONITOR pMonitor, const float& a) {
    const bool ENABLED = effectiveEnabled();

    if (m_lastEffectiveEnabled != ENABLED) {
        m_lastEffectiveEnabled = ENABLED;
        g_pDecorationPositioner->repositionDeco(this);
    }

    if (!ENABLED || !validMapped(m_window))
        return;

    // "Top bar on hover" mode: hidden until the pointer enters the top zone.
    bool show = true;
    if (m_showOnHover && g_pGlobalState->shell.showOnHover) {
        auto MOUSE = g_pInputManager->getMouseCoordsInternal();
        auto BOX   = assignedBoxGlobal();
        show = MOUSE.y >= BOX.y - 24 && MOUSE.y <= BOX.y + 16;
        m_showOnHover = show;
    }

    if (!show)
        return;

    auto data = COhmTabsPassElement::SBarData{this, a};
    g_pHyprRenderer->m_renderPass.add(makeUnique<COhmTabsPassElement>(data));
}

void COhmTabsDeco::renderPass(PHLMONITOR pMonitor, const float& a) {
    const auto PWINDOW = m_window.lock();
    if (!PWINDOW)
        return;

    const auto HEIGHT = barHeightValue();

    const bool FOCUSED = PWINDOW == Desktop::focusState()->window();
    m_windowHasFocus   = FOCUSED;

    const CHyprColor DEST_COLOR = FOCUSED ? colorOf(g_pGlobalState->shell.barColor, g_pGlobalState->config.barColor) :
                                            colorOf(g_pGlobalState->shell.inactiveBarColor, g_pGlobalState->config.inactiveBarColor);
    if (DEST_COLOR != m_realBarColor->goal())
        *m_realBarColor = DEST_COLOR;

    CHyprColor color = m_realBarColor->value();
    color.a *= a;

    // Snap effect: light the frame edge up in the theme accent while a drag is
    // in a snap zone, and flash+decay on a successful snap. Blended here so the
    // glow shares the strip's rounding/clipping and can never leak the frame.
    m_snapFx.glowEnabled = g_pGlobalState->config.snapGlow->value();
    snapFxTick();
    if (const double k = m_snapFx.intensity(); k > 0.0) {
        color = SnapFx::blendFrameColor(color, SnapFx::glowColor(PWINDOW), k);
        if (m_snapFx.animating())
            damageEntire();
    }

    if (HEIGHT < 1) {
        m_lastHeight = HEIGHT;
        return;
    }

    const auto PWORKSPACE      = PWINDOW->m_workspace;
    const auto WORKSPACEOFFSET = PWORKSPACE && !PWINDOW->m_pinned ? PWORKSPACE->m_renderOffset->value() : Vector2D();

    const auto ROUNDING       = PWINDOW->rounding() + PWINDOW->getRealBorderSize();
    const auto scaledRounding = ROUNDING > 0 ? ROUNDING * pMonitor->m_scale - 2 : 0;

    const auto DECOBOX = assignedBoxGlobal();
    const auto BARBUF  = DECOBOX.size() * pMonitor->m_scale;

    CBox titleBarBox = {DECOBOX.x - pMonitor->m_position.x, DECOBOX.y - pMonitor->m_position.y, DECOBOX.w, DECOBOX.h + ROUNDING * 3};
    titleBarBox.translate(PWINDOW->m_floatingOffset).scale(pMonitor->m_scale).round();

    if (titleBarBox.w < 1 || titleBarBox.h < 1)
        return;

    g_pHyprOpenGL->scissor(titleBarBox);

    if (ROUNDING) {
        CBox windowBox = {PWINDOW->position(Desktop::View::IGeometric::GEOMETRIC_CURRENT).x + PWINDOW->m_floatingOffset.x - pMonitor->m_position.x + 1,
                          PWINDOW->position(Desktop::View::IGeometric::GEOMETRIC_CURRENT).y + PWINDOW->m_floatingOffset.y - pMonitor->m_position.y + 1,
                          PWINDOW->size(Desktop::View::IGeometric::GEOMETRIC_CURRENT).x - 2, PWINDOW->size(Desktop::View::IGeometric::GEOMETRIC_CURRENT).y - 2};

        if (windowBox.w < 1 || windowBox.h < 1)
            return;

        glClearStencil(0);
        glClear(GL_STENCIL_BUFFER_BIT);
        g_pHyprOpenGL->setCapStatus(GL_STENCIL_TEST, true);
        glStencilFunc(GL_ALWAYS, 1, -1);
        glStencilOp(GL_KEEP, GL_KEEP, GL_REPLACE);
        glColorMask(GL_FALSE, GL_FALSE, GL_FALSE, GL_FALSE);

        windowBox.translate(WORKSPACEOFFSET).scale(pMonitor->m_scale).round();
        g_pHyprOpenGL->renderRect(windowBox, CHyprColor(0, 0, 0, 0), {.round = (int)scaledRounding, .roundingPower = PWINDOW->roundingPower()});
        glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);

        glStencilFunc(GL_NOTEQUAL, 1, -1);
        glStencilOp(GL_KEEP, GL_KEEP, GL_REPLACE);
    }

    g_pHyprOpenGL->renderRect(titleBarBox, color, {.round = (int)scaledRounding, .roundingPower = PWINDOW->roundingPower()});

    if (ROUNDING) {
        glClearStencil(0);
        glClear(GL_STENCIL_BUFFER_BIT);
        g_pHyprOpenGL->setCapStatus(GL_STENCIL_TEST, false);
        glStencilMask(-1);
        glStencilFunc(GL_ALWAYS, 1, 0xFF);
    }

    // buttons (logical layout, scaled at draw time)
    const auto  SLOTS      = layoutButtons(DECOBOX.w, DECOBOX.h);
    const float SCALE      = pMonitor->m_scale;
    const bool  MAXIMIZED  = g_pBackend->isMaximized(PWINDOW);
    const bool  MINENABLED = g_pBackend->minimizeEnabled();
    const auto  TEXTCOL    = colorOf(g_pGlobalState->shell.textColor, g_pGlobalState->config.textColor);
    const bool  LEFT       = buttonsLeftValue();
    // Main glyph about 14–16 px at standard size, 18–20 px at large (spec §3.3).
    const int   GLYPHSIZE  = std::round(std::clamp<int>(std::lround(buttonSizeValue() * 0.44), 12, 24) * SCALE);

    double occupiedLeft = 0, occupiedRight = 0;

    for (const auto& s : SLOTS) {
        CBox b = s.box;
        b.translate(Vector2D{titleBarBox.x / SCALE, titleBarBox.y / SCALE}).scale(SCALE).round();

        if (s.id == BTN_MENU && !LEFT)
            occupiedLeft = std::max(occupiedLeft, s.box.x + s.box.w);
        else if (s.id == BTN_MENU)
            occupiedRight = std::max(occupiedRight, DECOBOX.w - s.box.x);
        else if (LEFT)
            occupiedLeft = std::max(occupiedLeft, s.box.x + s.box.w);
        else
            occupiedRight = std::max(occupiedRight, DECOBOX.w - s.box.x);

        const bool HOVER   = m_hoverButton == s.id && m_pressedButton == BTN_NONE;
        const bool PRESSED = m_pressedButton == s.id && m_hoverButton == s.id;

        if (HOVER || PRESSED) {
            auto hc = s.id == BTN_CLOSE ? colorOf(g_pGlobalState->shell.closeHoverColor, g_pGlobalState->config.closeHoverColor) :
                                          colorOf(g_pGlobalState->shell.hoverColor, g_pGlobalState->config.hoverColor);
            hc.a *= a * (PRESSED ? 1.0 : 0.8);
            CBox inset = b;
            inset.expand(-2 * SCALE);
            g_pHyprOpenGL->renderRect(inset, hc, {.round = (int)std::round(6 * SCALE), .roundingPower = 2.F});
        }

        auto glyphColor = TEXTCOL;
        if (s.id == BTN_MINIMIZE && !MINENABLED)
            glyphColor.a *= 0.35;
        if (!FOCUSED)
            glyphColor.a *= 0.75;

        // Close keeps full contrast on its own hover treatment.
        if (s.id == BTN_CLOSE && (HOVER || PRESSED))
            glyphColor = CHyprColor{1.0F, 1.0F, 1.0F, static_cast<float>(TEXTCOL.a)};
        const auto TEX = glyph(s.id, MAXIMIZED, GLYPHSIZE, glyphColor);
        if (TEX && TEX->m_texID != 0) {
            CBox pos = {b.x + (b.w - TEX->m_size.x) / 2.0, b.y + (b.h - TEX->m_size.y) / 2.0, (double)TEX->m_size.x, (double)TEX->m_size.y};
            pos.round();
            g_pHyprOpenGL->renderTexture(TEX, pos, {.a = a});
        }
    }

    // Tabs (host of a tab group) replace the centered title when there is room
    // for a strip; otherwise the plain title is drawn exactly as before.
    const int PAD      = g_pGlobalState->config.padding->value();

    layoutTabs(DECOBOX.w, DECOBOX.h);
    if (!m_tabBoxes.empty()) {
        renderTabs(a, titleBarBox, SCALE, PAD, TEXTCOL, FOCUSED);
    } else {
        const int maxWidth = std::max<int>(0, std::round((DECOBOX.w - occupiedLeft - occupiedRight - PAD * 2) * SCALE));

        if (m_lastTitle != PWINDOW->m_title || m_windowSizeChanged || !m_textTex || m_textTex->m_texID == 0 || m_lastTitleWidth != maxWidth) {
            m_lastTitle      = PWINDOW->m_title;
            m_lastTitleWidth = maxWidth;
            renderTitle(BARBUF, SCALE, maxWidth);
        }

        if (m_textTex && m_textTex->m_texID != 0 && maxWidth > 8) {
            const double areaX = titleBarBox.x + occupiedLeft * SCALE + PAD * SCALE;
            const double areaW = maxWidth;
            const double x     = std::round(areaX + (areaW - m_textTex->m_size.x) / 2.0);
            const double y     = std::round(titleBarBox.y + (BARBUF.y - m_textTex->m_size.y) / 2.0);
            CBox         titleBox = {x, y, (double)m_textTex->m_size.x, (double)m_textTex->m_size.y};
            auto         ta       = a;
            if (!FOCUSED)
                ta *= 0.75;
            g_pHyprOpenGL->renderTexture(m_textTex, titleBox, {.a = ta});
        }
    }

    g_pHyprOpenGL->scissor(nullptr);

    m_windowSizeChanged = false;

    if (m_lastHeight != HEIGHT) {
        PWINDOW->layoutTarget()->recalc();
        m_lastHeight = HEIGHT;
    }
}

eDecorationType COhmTabsDeco::getDecorationType() {
    return DECORATION_CUSTOM;
}

void COhmTabsDeco::updateWindow(PHLWINDOW pWindow) {
    damageEntire();
}

void COhmTabsDeco::onConfigReloaded() {
    m_textTex = nullptr;
    m_showOnHover = g_pGlobalState->shell.showOnHover && g_pGlobalState->config.showOnHover && g_pGlobalState->config.showOnHover->value();
    g_pDecorationPositioner->repositionDeco(this);
    damageEntire();
}

void COhmTabsDeco::onBackendStateChanged() {
    g_pDecorationPositioner->repositionDeco(this);
    if (const auto PWINDOW = m_window.lock(); validMapped(PWINDOW)) {
        if (const auto PMONITOR = PWINDOW->m_monitor.lock(); PMONITOR)
            PMONITOR->m_scheduledRecalc = true;
    }
    damageEntire();
}

void COhmTabsDeco::damageEntire() {
    g_pHyprRenderer->damageBox(assignedBoxGlobal());
}

Vector2D COhmTabsDeco::cursorRelativeToBar() {
    return g_pInputManager->getMouseCoordsInternal() - assignedBoxGlobal().pos();
}

eDecorationLayer COhmTabsDeco::getDecorationLayer() {
    return DECORATION_LAYER_UNDER;
}

uint64_t COhmTabsDeco::getDecorationFlags() {
    return DECORATION_ALLOWS_MOUSE_INPUT | DECORATION_PART_OF_MAIN_WINDOW;
}

CBox COhmTabsDeco::assignedBoxGlobal() {
    if (!validMapped(m_window))
        return {};

    CBox box = m_assignedBox;
    box.translate(g_pDecorationPositioner->getEdgeDefinedPoint(DECORATION_EDGE_TOP, m_window.lock()));

    const auto PWORKSPACE      = m_window->m_workspace;
    const auto WORKSPACEOFFSET = PWORKSPACE && !m_window->m_pinned ? PWORKSPACE->m_renderOffset->value() : Vector2D();

    return box.translate(WORKSPACEOFFSET);
}

PHLWINDOW COhmTabsDeco::getOwner() {
    return m_window.lock();
}

void COhmTabsDeco::updateRules() {
    const auto PWINDOW    = m_window.lock();
    const auto prevHidden = m_hidden;

    m_hidden = false;

    if (!PWINDOW)
        return;

    if (PWINDOW->m_ruleApplicator->m_otherProps.props.contains(g_pGlobalState->nobarRuleIdx))
        m_hidden = truthy(PWINDOW->m_ruleApplicator->m_otherProps.props.at(g_pGlobalState->nobarRuleIdx)->effect);

    // Settings → Excluded applications: matched on the window class (never
    // on the title, spec §3.4).
    for (const auto& cls : g_pGlobalState->shell.excludedClasses) {
        if (cls == PWINDOW->m_class || cls == PWINDOW->m_initialClass) {
            m_hidden = true;
            break;
        }
    }

    if (prevHidden != m_hidden)
        g_pDecorationPositioner->repositionDeco(this);
}
