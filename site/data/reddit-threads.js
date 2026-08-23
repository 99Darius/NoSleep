// Seed list of Reddit threads where a helpful NoSleep reply belongs, with a
// pre-drafted reply for each. URLs were pulled from Reddit's live search index
// (verified real, not fabricated). The admin dashboard reads this list and
// tracks which ones have been replied to (that state lives in the encrypted
// blob, not here, so this file stays a static, reviewable seed).
export const threads = [
  {
    id: "mac-1sznsu0",
    title: "How do I force my MacBook to stay awake when closing the lid on battery power?",
    url: "https://www.reddit.com/r/mac/comments/1sznsu0/how_do_i_force_my_macbook_to_stay_awake_when/",
    subreddit: "r/mac",
    recency: "recent (~Apr 2026)",
    priority: "high",
    fit: "Exact use case (lid-closed + battery); the Smart battery-release feature answers the implied risk.",
    reply: "On battery, macOS sleeps on lid-close by design and caffeinate won't override it. Full disclosure, I built a free open-source menu-bar app called NoSleep that does exactly this — stays awake with the lid shut on battery — and since draining the battery is the obvious risk there, its Smart mode releases the sleep block before the battery gets critically low. It's on GitHub (99Darius/NoSleep), no telemetry, if you want to try it."
  },
  {
    id: "macapps-1kje6zv",
    title: "How to keep M3 Macbook Pro \"awake\" and online when lid is closed",
    url: "https://www.reddit.com/r/macapps/comments/1kje6zv/how_to_keep_m3_macbook_pro_awake_and_online_when/",
    subreddit: "r/macapps",
    recency: "~May 2025",
    priority: "high",
    fit: "Direct 'keep it awake lid-closed' question in your core sub.",
    reply: "The reason most keep-awake tools fail here is that closing the lid triggers a lower-level clamshell sleep a normal power assertion can't stop. Full disclosure, I made a free open-source menu-bar app called NoSleep for exactly this — it holds the Mac awake with the lid shut (no external monitor needed) so downloads and agents keep running, then Smart mode lets it sleep once you're done. Repo's at github.com/99Darius/NoSleep — universal binary, no telemetry."
  },
  {
    id: "macapps-1ecbrj5",
    title: "Anyone else facing this issue with the Amphetamine app's Clamshell Mode function?",
    url: "https://www.reddit.com/r/macapps/comments/1ecbrj5/anyone_else_facing_this_issue_with_the/",
    subreddit: "r/macapps",
    recency: "~Jul 2024",
    priority: "medium",
    fit: "Complaint about Amphetamine's clamshell mode — natural opening for an alternative.",
    reply: "Amphetamine's closed-display mode has been finicky for a lot of people because it leans on the display-based clamshell path. Full disclosure, I ended up building my own free open-source alternative called NoSleep — it keeps the Mac awake lid-closed without needing an external display, and has a Smart mode that returns to normal sleep once your task finishes. Might be worth a look if Amphetamine keeps dropping the session: github.com/99Darius/NoSleep."
  },
  {
    id: "topmactools-1uis13b",
    title: "How to keep the mac running with lid closed",
    url: "https://www.reddit.com/r/topmactools/comments/1uis13b/how_to_keep_the_mac_running_with_lid_closed/",
    subreddit: "r/topmactools",
    recency: "recent (~Jun 2026)",
    priority: "high",
    fit: "Straight keep-running-lid-closed question.",
    reply: "caffeinate and most menu-bar apps only block idle sleep, not the clamshell sleep that fires when you physically close the lid. Full disclosure, I built a free open-source menu-bar app for this exact case called NoSleep — it keeps the Mac running with the lid closed even without an external monitor, which is great for long agent runs or overnight tasks. go.99.co/No-Sleep if you want to grab it."
  },
  {
    id: "macbookair-1qh8ugn",
    title: "MacBook Air M2 clamshell on battery?",
    url: "https://www.reddit.com/r/macbookair/comments/1qh8ugn/macbook_air_m2_clamshell_on_battery/",
    subreddit: "r/macbookair",
    recency: "recent (~Jan 2026)",
    priority: "medium",
    fit: "Clamshell-on-battery question; battery-release feature is the differentiator.",
    reply: "Native clamshell only kicks in with power plus an external display, which is why the Air won't stay awake lid-closed on battery by default. Full disclosure, I made a free open-source app called NoSleep that forces it to stay awake with the lid shut on battery too — and because battery is the risk there, Smart mode releases the block before it gets critically low. Repo: github.com/99Darius/NoSleep."
  },
  {
    id: "sideproject-1tz4jfs",
    title: "i turn my MacBook into a Mac mini so my agents stop dying",
    url: "https://www.reddit.com/r/SideProject/comments/1tz4jfs/i_turn_my_macbook_into_a_mac_mini_so_my_agents/",
    subreddit: "r/SideProject",
    recency: "recent (~Jun 2026)",
    priority: "high",
    fit: "Poster's whole pain point is agents dying when the machine sleeps — your exact angle.",
    reply: "Nice workaround. For the specific \"agents die when the lid closes\" problem I went a lighter route — full disclosure, I built a free open-source menu-bar app called NoSleep that just holds the Mac awake with the lid shut so Claude Code / Codex / Cursor keep running, and its Smart mode drops the block once the agents go idle so it isn't awake forever. Might save you the reconfiguration: go.99.co/No-Sleep."
  },
  {
    id: "macbook-1dv347u",
    title: "Downloads from Steam interrupted when laptop is closed",
    url: "https://www.reddit.com/r/macbook/comments/1dv347u/issue_with_macbook_pro_downloads_from_steam/",
    subreddit: "r/macbook",
    recency: "~Jul 2024",
    priority: "medium",
    fit: "Long download killed by lid-close sleep — same mechanism you solve.",
    reply: "That's the clamshell sleep path kicking in the moment the lid closes, and regular caffeinate-style tools don't cover it. Full disclosure, I built a free open-source menu-bar app called NoSleep that keeps the Mac awake lid-closed so downloads and transfers actually finish, then Smart mode lets it sleep again afterward. Works on both Intel and Apple Silicon, no telemetry: github.com/99Darius/NoSleep."
  },
  {
    id: "plex-hfhr2j",
    title: "Running MacBook Pro as a headless server — auto-run caffeinate -s to keep Mac awake?",
    url: "https://www.reddit.com/r/PleX/comments/hfhr2j/running_macbook_pro_as_a_headless_server_how_to/",
    subreddit: "r/PleX",
    recency: "older (~2020), evergreen",
    priority: "low",
    fit: "Wants a hands-off keep-awake for an always-on lid-closed Mac.",
    reply: "If you'd rather not babysit a caffeinate LaunchAgent, full disclosure, I built a free open-source menu-bar app called NoSleep that keeps a Mac awake lid-closed with no external display needed — handy for a headless Plex/always-on box — and can also let it sleep when idle if you ever want that. No telemetry, universal binary: github.com/99Darius/NoSleep."
  },
  {
    id: "macbookpro-1pcax2j",
    title: "App idea: Quick & easy battery/sleep configurer, from Menu bar dropdown",
    url: "https://www.reddit.com/r/macbookpro/comments/1pcax2j/app_idea_quick_easy_batterysleep_configurer_from/",
    subreddit: "r/macbookpro",
    recency: "recent (~Dec 2025)",
    priority: "medium",
    fit: "Poster is wishing for a menu-bar sleep controller — you already built one.",
    reply: "Part of this already exists if it helps — full disclosure, I built a free open-source menu-bar app called NoSleep that toggles keep-awake (including lid-closed, no external monitor) straight from the menu bar, with a Smart mode that restores normal sleep once your task or agent finishes and releases before the battery dies. It's open source, so you could even fork the sleep-config bits: github.com/99Darius/NoSleep."
  },
  {
    id: "mac-y9lbxz",
    title: "Keep a MacBook awake while the lid is closed and not connected to WiFi?",
    url: "https://www.reddit.com/r/mac/comments/y9lbxz/is_there_a_way_to_wake_up_and_keep_a_macbook/",
    subreddit: "r/mac",
    recency: "older (~2022)",
    priority: "low",
    fit: "Directly asks how to keep it awake lid-closed (remote-wake half is separate).",
    reply: "For the keep-awake-with-the-lid-closed part specifically, full disclosure, I made a free open-source menu-bar app called NoSleep that handles it without an external monitor — it holds the clamshell sleep off so the Mac keeps running, then Smart mode lets it sleep again when idle. It won't do the remote-wake-from-iPhone side, but it nails staying awake: go.99.co/No-Sleep."
  },
  {
    id: "mac-14mm3db",
    title: "Keep a Mac awake for any duration with a user friendly easy to setup script",
    url: "https://www.reddit.com/r/mac/comments/14mm3db/keep_a_mac_awake_for_any_duration_with_a_user/",
    subreddit: "r/mac",
    recency: "~Jun 2023",
    priority: "low",
    fit: "Active keep-awake discussion; you add the one thing scripts can't do (lid-closed).",
    reply: "Nice script. If anyone here wants a GUI version that also survives the lid closing — the one thing plain caffeinate/scripts can't do — full disclosure, I built a free open-source menu-bar app called NoSleep: keep-awake lid-closed with no external monitor, plus a Smart mode that releases once your task finishes. Source is at github.com/99Darius/NoSleep."
  }
];
