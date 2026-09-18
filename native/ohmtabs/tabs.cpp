#include "tabs.hpp"

#include <algorithm>

TabStore::SJoinResult TabStore::join(const std::string& source, const std::string& host) {
    SJoinResult r;

    if (source == host) {
        r.error = "a window cannot join itself";
        return r;
    }

    // The source must be free: a window belongs to at most one group.
    if (const auto it = m_member.find(source); it != m_member.end()) {
        const auto& g = m_groups.at(it->second);
        r.error = (source == g.tabs[g.active]) ? "the source window is itself a tab host"
                                               : "the source window is already in a tab group";
        return r;
    }

    auto hostIt = m_member.find(host);
    if (hostIt != m_member.end()) {
        auto& g = m_groups.at(hostIt->second);
        // Dropping onto a hidden (non-host) member is not a valid target; only
        // the visible host window can accept a drop.
        if (host != g.tabs[g.active]) {
            r.error = "the target window is a tab, not a group host";
            return r;
        }
        g.tabs.push_back(source);
        m_member.emplace(source, g.id);
        r.ok = true;
        r.id = g.id;
        return r;
    }

    // Neither window is grouped yet: create a fresh group with host as the
    // active (visible) member and source as the first hidden tab.
    STabGroup g;
    g.id     = m_nextId++;
    g.active = 0;
    g.tabs   = {host, source};
    m_groups.emplace(g.id, g);
    m_member.emplace(host, g.id);
    m_member.emplace(source, g.id);
    r.ok = true;
    r.id = g.id;
    return r;
}

bool TabStore::detach(const std::string& token) {
    auto it = m_member.find(token);
    if (it == m_member.end())
        return false;

    const uint64_t gid = it->second;
    auto&         g   = m_groups.at(gid);

    // Removing the host dissolves the whole group.
    if (g.tabs[g.active] == token) {
        eraseGroup(gid);
        return true;
    }

    const auto pos = std::find(g.tabs.begin(), g.tabs.end(), token);
    if (pos == g.tabs.end())
        return false;
    const int idx = static_cast<int>(std::distance(g.tabs.begin(), pos));

    g.tabs.erase(pos);
    m_member.erase(token);

    if (g.tabs.size() < 2) {
        // Dissolved below two members.
        eraseGroup(gid);
        return true;
    }

    // Keep `active` (the host's index) pointing at the same window after the
    // removal shifted later indices left.
    if (idx < g.active)
        g.active -= 1;

    return true;
}

bool TabStore::ungroup(uint64_t groupId) {
    auto it = m_groups.find(groupId);
    if (it == m_groups.end())
        return false;
    eraseGroup(groupId);
    return true;
}

bool TabStore::activate(uint64_t groupId, int index) {
    auto it = m_groups.find(groupId);
    if (it == m_groups.end())
        return false;
    if (index < 0 || static_cast<size_t>(index) >= it->second.tabs.size())
        return false;
    it->second.active = index;
    return true;
}

std::vector<std::string> TabStore::closeAll(uint64_t groupId) {
    auto it = m_groups.find(groupId);
    if (it == m_groups.end())
        return {};
    std::vector<std::string> tokens = it->second.tabs;
    eraseGroup(groupId);
    return tokens;
}

void TabStore::forget(const std::string& token) {
    (void)detach(token);
}

void TabStore::clear() {
    m_groups.clear();
    m_member.clear();
}

const STabGroup* TabStore::groupOf(const std::string& token) const {
    auto it = m_member.find(token);
    if (it == m_member.end())
        return nullptr;
    auto g = m_groups.find(it->second);
    return g == m_groups.end() ? nullptr : &g->second;
}

const STabGroup* TabStore::hostGroup(const std::string& token) const {
    auto it = m_member.find(token);
    if (it == m_member.end())
        return nullptr;
    auto g = m_groups.find(it->second);
    if (g == m_groups.end())
        return nullptr;
    return (g->second.tabs[g->second.active] == token) ? &g->second : nullptr;
}

const STabGroup* TabStore::group(uint64_t groupId) const {
    auto it = m_groups.find(groupId);
    return it == m_groups.end() ? nullptr : &it->second;
}

std::vector<const STabGroup*> TabStore::groups() const {
    std::vector<const STabGroup*> out;
    out.reserve(m_groups.size());
    for (const auto& [id, g] : m_groups)
        out.push_back(&g);
    return out;
}

size_t TabStore::groupCount() const {
    return m_groups.size();
}

void TabStore::eraseGroup(uint64_t groupId) {
    auto it = m_groups.find(groupId);
    if (it == m_groups.end())
        return;
    for (const auto& token : it->second.tabs)
        m_member.erase(token);
    m_groups.erase(it);
}
