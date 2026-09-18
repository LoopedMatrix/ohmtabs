#include "pass.hpp"

#include <hyprland/src/render/OpenGL.hpp>
#include <hyprland/src/render/Renderer.hpp>

#include "bar.hpp"

COhmTabsPassElement::COhmTabsPassElement(const COhmTabsPassElement::SBarData& data) : m_data(data) {
    ;
}

std::vector<UP<IPassElement>> COhmTabsPassElement::draw() {
    m_data.deco->renderPass(g_pHyprRenderer->m_renderData.pMonitor.lock(), m_data.a);
    return {};
}

bool COhmTabsPassElement::needsLiveBlur() {
    return false;
}

std::optional<CBox> COhmTabsPassElement::boundingBox() {
    // Expand a little so occlusion culling does not clip the strip's rounded corners.
    return m_data.deco->assignedBoxGlobal().translate(-g_pHyprRenderer->m_renderData.pMonitor->m_position).expand(10);
}

bool COhmTabsPassElement::needsPrecomputeBlur() {
    return false;
}
