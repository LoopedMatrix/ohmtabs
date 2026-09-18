#pragma once

// The OhmTabs title strip: a reserved top decoration with a window-menu
// target, an ellipsized title, and Minimize / Maximize-Restore / Close.
//
// Derived from Hyprbars' CHyprBar (BSD-3-Clause, Hypr Development). OhmTabs
// changes: buttons act on release inside the same target with the window
// identity captured at press; actions go through typed backend calls instead
// of `exec`; dragging respects the drag threshold and detaches tiled windows;
// the strip is suspended while no shell service is connected.

#define WLR_USE_UNSTABLE

#include <hyprland/src/render/decorations/IHyprWindowDecoration.hpp>
#include <hyprland/src/render/OpenGL.hpp>
#include <hyprland/src/render/gl/GLTexture.hpp>
#include <hyprland/src/devices/IPointer.hpp>
#include <hyprland/src/desktop/rule/windowRule/WindowRule.hpp>
#include <hyprland/src/helpers/AnimatedVariable.hpp>
#include <hyprland/src/helpers/time/Time.hpp>
#include <hyprland/src/helpers/signal/Signal.hpp>

#include "globals.hpp"
#include "snapfx.hpp"

#define private public
#include <hyprland/src/managers/input/InputManager.hpp>
#undef private

namespace Event {
    struct SCallbackInfo;
}

enum eOhmTabsButton : int8_t {
    BTN_NONE = -1,
    BTN_MENU = 0,
    BTN_MINIMIZE,
    BTN_MAXIMIZE,
    BTN_CLOSE,
};

struct SButtonSlot {
    eOhmTabsButton id = BTN_NONE;
    CBox           box; // logical pixels, relative to the strip's top-left
};

// One tab segment in the native tab strip (window tabs, browser-style).
struct STabBox {
    int         index      = -1; // index into the host group's tab list
    CBox        box;             // segment bounds (logical px, strip-relative)
    CBox        closeBox;        // close affordance within the segment
    bool        active     = false;
    std::string token;
};

class COhmTabsDeco : public IHyprWindowDecoration {
  public:
    COhmTabsDeco(PHLWINDOW);
    virtual ~COhmTabsDeco();

    virtual SDecorationPositioningInfo getPositioningInfo();
    virtual void                       onPositioningReply(const SDecorationPositioningReply& reply);
    virtual void                       draw(PHLMONITOR, float const& a);
    virtual eDecorationType            getDecorationType();
    virtual void                       updateWindow(PHLWINDOW);
    virtual void                       damageEntire();
    virtual eDecorationLayer           getDecorationLayer();
    virtual uint64_t                   getDecorationFlags();
    virtual std::string                getDisplayName();

    PHLWINDOW                          getOwner();
    void                               updateRules();
    void                               onConfigReloaded();
    void                               onBackendStateChanged();
    void                               renderPass(PHLMONITOR, float const& a);
    CBox                               assignedBoxGlobal();

    bool                               isDragging() const { return m_dragging; }
    SnapFx::State&                     snapFx() { return m_snapFx; }
    const SnapFx::State&               snapFx() const { return m_snapFx; }

    WP<COhmTabsDeco>                   m_self;

  private:
    PHLWINDOWREF               m_window;
    CBox                       m_assignedBox;
    SP<Render::ITexture>       m_textTex;
    std::string                m_lastTitle;
    int                        m_lastTitleWidth = -1;
    bool                       m_windowSizeChanged = false;
    bool                       m_hidden            = false; // rule ohmtabs:no_bar
    bool                       m_lastEffectiveEnabled = false;
    bool                       m_windowHasFocus       = false;
    int                        m_lastHeight           = 0;
    bool                       m_showOnHover          = false; // reveal only when pointer is in the top zone

    // input state
    eOhmTabsButton             m_pressedButton = BTN_NONE;
    eOhmTabsButton             m_hoverButton   = BTN_NONE;
    std::string                m_pressToken;
    Vector2D                   m_pressPos;      // global coords at press
    Vector2D                   m_pressOffset;   // press position relative to the strip
    Time::steady_tp            m_lastTitlePress = Time::steadyNow();
    bool                       m_lastPressWasTitle = false;
    bool                       m_dragPending  = false;
    bool                       m_dragging     = false;
    bool                       m_cancelledDown = false;

    // --- snap glow / flash (feat/snap-glow) ---
    SnapFx::State              m_snapFx;            // glow/flash state machine
    Time::steady_tp            m_snapFxLastTick = Time::steadyNow();
    // --- window tabs (feat/tabs-native) ---
    std::vector<STabBox>       m_tabBoxes;
    int                        m_pressedTab      = -1;      // index into the host group
    bool                       m_pressedTabClose = false;   // press was on a close affordance
    bool                       m_tabTearOff      = false;   // drag tears a tab out of its group
    std::string                m_tearToken;                 // tab being torn off

    PHLANIMVAR<CHyprColor>     m_realBarColor;

    CHyprSignalListener        m_mouseButtonCallback;
    CHyprSignalListener        m_mouseMoveCallback;

    bool                       effectiveEnabled();
    bool                       inputIsValid();
    Vector2D                   cursorRelativeToBar();
    std::vector<SButtonSlot>   layoutButtons(double barW, double barH);
    eOhmTabsButton             buttonAt(const Vector2D& rel);
    void                       onMouseButton(Event::SCallbackInfo& info, IPointer::SButtonEvent e);
    void                       onMouseMove(Vector2D coords);
    void                       handleDownEvent(Event::SCallbackInfo& info);
    void                       handleUpEvent(Event::SCallbackInfo& info);
    void                       startDrag();
    void                       endDrag();
    bool                       snapToZone();
    void                       updateSnapPreview();
    void                       snapFxTick();
    void                       activate(eOhmTabsButton b, const std::string& token);
    void                       renderTitle(const Vector2D& bufferSize, float scale, int maxWidth);
    SP<Render::ITexture>       glyph(eOhmTabsButton b, bool maximized, int size, const CHyprColor& color);

    // tab strip layout / hit-test / input
    std::vector<STabBox>       layoutTabs(double barW, double barH);
    int                        tabAt(const Vector2D& rel);      // segment index under the pointer, -1 if none
    bool                       tryJoinDrop();
    void                       startTabTearOff(const std::string& token);
    void                       renderTabs(float a, const CBox& titleBarBox, float SCALE, int PAD, const CHyprColor& textColor, bool focused);

    friend class COhmTabsPassElement;
};

// Compositor glue for the snap effect (defined in snapfx.cpp).
namespace SnapFx {
    CHyprColor glowColor(PHLWINDOW w);
    CHyprColor blendFrameColor(const CHyprColor& base, const CHyprColor& accent, double intensity);
    std::string statusJson();
}
