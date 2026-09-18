// Standalone unit test for TabStore (pure logic, no Hyprland, no session).
//
// Build:  g++ -std=c++20 -I../native/ohmtabs tabs_store_test.cpp ../native/ohmtabs/tabs.cpp -o tabs_store_test
//   (or run ./run_tabs_test.sh)
//
// Prints PASS/FAIL per case and exits non-zero on the first failure.

#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>

#include "tabs.hpp"

static int  g_checks = 0;
static int  g_failed = 0;
static bool g_caseFailed = false;

#define CHECK(cond)                                                                                              \
    do {                                                                                                         \
        ++g_checks;                                                                                              \
        if (!(cond)) {                                                                                           \
            ++g_failed;                                                                                          \
            g_caseFailed = true;                                                                                 \
            std::printf("    CHECK failed: %s (%s:%d)\n", #cond, __FILE__, __LINE__);                            \
        }                                                                                                        \
    } while (0)

static void runCase(const char* name) {
    g_caseFailed = false;
    std::printf("CASE %s\n", name);
}

static void endCase() {
    std::printf("  %s\n\n", g_caseFailed ? "FAIL" : "PASS");
}

int main() {
    // --- create (drop A onto B) ------------------------------------------
    runCase("create group via join");
    {
        TabStore s;
        auto r = s.join("A", "B");
        CHECK(r.ok);
        CHECK(r.id != 0);
        const auto* g = s.group(r.id);
        CHECK(g != nullptr);
        CHECK(g->tabs == std::vector<std::string>({"B", "A"})); // host first
        CHECK(g->active == 0);                                  // host visible
        CHECK(g->tabs[g->active] == "B");
        CHECK(s.groupOf("A") == g);
        CHECK(s.groupOf("B") == g);
        CHECK(s.hostGroup("B") == g);
        CHECK(s.hostGroup("A") == nullptr); // A is hidden, not the host
        CHECK(s.groupCount() == 1);
    }
    endCase();

    // --- join into existing group -----------------------------------------
    runCase("join appends to existing group");
    {
        TabStore s;
        auto r = s.join("A", "B");
        auto r2 = s.join("C", "B");
        CHECK(r2.ok);
        CHECK(r2.id == r.id);
        const auto* g = s.group(r.id);
        CHECK(g->tabs == std::vector<std::string>({"B", "A", "C"}));
        CHECK(g->active == 0);
        CHECK(s.groupCount() == 1);
    }
    endCase();

    // --- join self --------------------------------------------------------
    runCase("join self refused");
    {
        TabStore s;
        auto r = s.join("A", "A");
        CHECK(!r.ok);
        CHECK(!r.error.empty());
        CHECK(s.groupCount() == 0);
    }
    endCase();

    // --- join already-grouped source --------------------------------------
    runCase("join grouped source refused");
    {
        TabStore s;
        s.join("A", "B");
        auto r = s.join("A", "C");
        CHECK(!r.ok);
        auto r2 = s.join("B", "C"); // B is now a host
        CHECK(!r2.ok);
        CHECK(s.groupCount() == 1); // no new group
    }
    endCase();

    // --- join onto a hidden (non-host) member -----------------------------
    runCase("join onto a non-host member refused");
    {
        TabStore s;
        auto r = s.join("A", "B");
        auto r2 = s.join("C", "A"); // A is a member, not the host
        CHECK(!r2.ok);
        CHECK(s.groupCount() == 1);
    }
    endCase();

    // --- activate ordering ------------------------------------------------
    runCase("activate changes the visible tab");
    {
        TabStore s;
        auto r = s.join("A", "B");
        s.join("C", "B"); // tabs: B A C
        CHECK(s.activate(r.id, 1)); // show A
        const auto* g = s.group(r.id);
        CHECK(g->active == 1);
        CHECK(g->tabs[g->active] == "A");
        CHECK(s.hostGroup("A") == g);
        CHECK(s.hostGroup("B") == nullptr);
        CHECK(!s.activate(r.id, 99)); // out of range
        CHECK(g->active == 1);
    }
    endCase();

    // --- active-index adjustment after member removal ---------------------
    runCase("active index adjusts after member removal");
    {
        TabStore s;
        auto r = s.join("A", "B");
        s.join("C", "B"); // tabs: B A C
        s.join("D", "B"); // tabs: B A C D
        s.activate(r.id, 3); // host is D (index 3)
        const auto* g = s.group(r.id);
        CHECK(g->active == 3);

        // Remove a member before the host: active must shift left.
        CHECK(s.detach("A")); // tabs: B C D
        CHECK(g->active == 2);
        CHECK(g->tabs[g->active] == "D");

        // Remove a member after the host: active unchanged.
        // (re-add a tail member first)
        s.join("E", "D"); // tabs: B C D E ; host D index 2
        CHECK(s.detach("E")); // tabs: B C D
        CHECK(g->active == 2);

        // Remove a member that leaves exactly two -> still alive.
        CHECK(s.detach("C")); // tabs: B D
        CHECK(s.group(r.id) != nullptr);
        CHECK(g->active == 1);
    }
    endCase();

    // --- detach host dissolves -------------------------------------------
    runCase("removing the host dissolves the group");
    {
        TabStore s;
        auto r = s.join("A", "B");
        s.join("C", "B");
        CHECK(s.detach("B")); // B is the host
        CHECK(s.group(r.id) == nullptr);
        CHECK(s.groupCount() == 0);
        CHECK(s.groupOf("A") == nullptr);
        CHECK(s.groupOf("C") == nullptr);
    }
    endCase();

    // --- dissolve below two ----------------------------------------------
    runCase("group dissolves below two members");
    {
        TabStore s;
        auto r = s.join("A", "B");
        CHECK(s.groupCount() == 1);
        CHECK(s.detach("A")); // B left alone
        CHECK(s.group(r.id) == nullptr);
        CHECK(s.groupCount() == 0);
    }
    endCase();

    // --- ungroup ----------------------------------------------------------
    runCase("ungroup dissolves an entire group");
    {
        TabStore s;
        auto r = s.join("A", "B");
        s.join("C", "B");
        CHECK(s.ungroup(r.id));
        CHECK(s.groupCount() == 0);
        CHECK(!s.ungroup(r.id)); // already gone
        CHECK(s.groupOf("A") == nullptr);
        CHECK(s.groupOf("B") == nullptr);
    }
    endCase();

    // --- closeAll order + removal ----------------------------------------
    runCase("closeAll returns tokens in join order and dissolves");
    {
        TabStore s;
        auto r = s.join("A", "B");
        s.join("C", "B");
        auto tokens = s.closeAll(r.id);
        CHECK(tokens == std::vector<std::string>({"B", "A", "C"}));
        CHECK(s.groupCount() == 0);
        CHECK(s.closeAll(r.id).empty()); // second call: nothing
    }
    endCase();

    // --- forget == detach -------------------------------------------------
    runCase("forget removes a closed window");
    {
        TabStore s;
        auto r = s.join("A", "B");
        s.join("C", "B");
        s.forget("C"); // C closed
        const auto* g = s.group(r.id);
        CHECK(g != nullptr);
        CHECK(g->tabs == std::vector<std::string>({"B", "A"}));
        s.forget("B"); // host closed -> dissolve
        CHECK(s.group(r.id) == nullptr);
    }
    endCase();

    // --- multiple independent groups --------------------------------------
    runCase("independent groups do not interfere");
    {
        TabStore s;
        auto r1 = s.join("A", "B");
        auto r2 = s.join("X", "Y");
        CHECK(r1.id != r2.id);
        CHECK(s.groupCount() == 2);
        CHECK(s.detach("A")); // dissolves group 1 only
        CHECK(s.group(r1.id) == nullptr);
        CHECK(s.group(r2.id) != nullptr);
        CHECK(s.groupOf("X") == s.group(r2.id));
    }
    endCase();

    // --- clear ------------------------------------------------------------
    runCase("clear drops everything");
    {
        TabStore s;
        s.join("A", "B");
        s.join("X", "Y");
        s.clear();
        CHECK(s.groupCount() == 0);
        CHECK(s.groupOf("A") == nullptr);
    }
    endCase();

    std::printf("----\n%d checks, %d failed\n", g_checks, g_failed);
    return g_failed == 0 ? 0 : 1;
}
