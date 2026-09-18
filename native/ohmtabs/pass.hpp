#pragma once

// Render pass element for the OhmTabs strip. Structure follows Hyprbars'
// CBarPassElement (BSD-3-Clause, Hypr Development); see docs/UPSTREAM.md.

#include <hyprland/src/render/pass/PassElement.hpp>

class COhmTabsDeco;

class COhmTabsPassElement : public IPassElement {
  public:
    struct SBarData {
        COhmTabsDeco* deco = nullptr;
        float         a    = 1.F;
    };

    COhmTabsPassElement(const SBarData& data);
    virtual ~COhmTabsPassElement() = default;

    virtual std::vector<UP<IPassElement>> draw() override;
    virtual bool                          needsLiveBlur() override;
    virtual bool                          needsPrecomputeBlur() override;
    virtual std::optional<CBox>           boundingBox() override;

    virtual const char*                   passName() override {
        return "COhmTabsPassElement";
    }

    virtual ePassElementType type() override {
        return EK_CUSTOM;
    }

  private:
    SBarData m_data;
};
