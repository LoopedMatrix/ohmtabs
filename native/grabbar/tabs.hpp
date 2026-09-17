#pragma once

// TabStore: the pure data model for browser-like window tab groups.
//
// This file and tabs.cpp are deliberately free of every Hyprland header so
// the model can be unit-tested standalone (tests/unit/tabs_store_test.cpp).
// Only std:: headers are allowed here.
//
// Model invariant:
//   * A window may belong to at most one group.
//   * A group always has >= 2 members; dropping below two dissolves it.
//   * The group host is the window that owns the visible tab strip and is
//     therefore always the currently-shown window: host == tabs[active].
//   * Removing the host always dissolves the whole group.
//   * Tokens are the backend's "g<epoch>-<generation>" identifiers; the store
//     never resolves them, it only compares and orders them.

#include <cstdint>
#include <map>
#include <string>
#include <vector>

struct STabGroup {
    uint64_t                 id     = 0;  // store-assigned, monotonically increasing
    int                      active = 0;  // index into tabs == the visible host window
    std::vector<std::string> tabs;        // member tokens, in stable join order
};

class TabStore {
  public:
    struct SJoinResult {
        bool        ok    = false;
        uint64_t    id    = 0;
        std::string error; // human-readable reason when !ok
    };

    // Drop `source` onto `host`. Creates a group when `host` is ungrouped,
    // otherwise appends `source` to `host`'s existing group. `source` becomes
    // a hidden member; the active/host window is unchanged.
    SJoinResult join(const std::string& source, const std::string& host);

    // Tear `token` out of its group. Removing the host dissolves the group;
    // removing a member dissolves the group when it drops below two members.
    // Returns false when `token` was not in any group.
    bool detach(const std::string& token);

    // Dissolve a group entirely. Returns false when no such group exists.
    bool ungroup(uint64_t groupId);

    // Make `index` the active (visible/host) tab. Returns false on bad input.
    bool activate(uint64_t groupId, int index);

    // Dissolve the group and return its member tokens in join order (the
    // caller closes them). Empty when no such group exists.
    std::vector<std::string> closeAll(uint64_t groupId);

    // Window gone (closed/destroyed for any reason): same effect as detach().
    void forget(const std::string& token);

    // Drop all groups (backend shutdown / plugin stop).
    void clear();

    // Queries. `groupOf` matches host or member; `hostGroup` matches only the
    // current host (== tabs[active]).
    const STabGroup* groupOf(const std::string& token) const;
    const STabGroup* hostGroup(const std::string& token) const;
    const STabGroup* group(uint64_t groupId) const;
    std::vector<const STabGroup*> groups() const;
    size_t groupCount() const;

  private:
    void eraseGroup(uint64_t groupId);

    uint64_t                         m_nextId = 1;
    std::map<uint64_t, STabGroup>    m_groups;   // id -> group
    std::map<std::string, uint64_t>  m_member;   // token -> group id (host and members)
};
