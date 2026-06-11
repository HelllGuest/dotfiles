// Zen Browser — privacy defaults (per-profile; deployed by browser-hardening.sh)
// Restart Zen after ./install.sh or scripts/browser-hardening.sh

// Telemetry & reporting
user_pref("datareporting.healthreport.uploadEnabled", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("datareporting.spolicy.current_revision", 0);
user_pref("toolkit.telemetry.enabled", false);
user_pref("toolkit.telemetry.unified", false);
user_pref("toolkit.telemetry.archive.enabled", false);
user_pref("toolkit.telemetry.server", "");
user_pref("app.shield.optoutstudies.enabled", false);
user_pref("app.normandy.enabled", false);
user_pref("breakpad.reportURL", "");
user_pref("browser.tabs.crashReporting.sendReport", false);
user_pref("browser.crashReports.unsubmittedCheck.autoSubmit2", false);
user_pref("browser.ping-centre.telemetry", false);
user_pref("browser.newtabpage.activity-stream.feeds.telemetry", false);
user_pref("browser.newtabpage.activity-stream.telemetry", false);
user_pref("browser.newtabpage.activity-stream.feeds.snippets", false);
user_pref("browser.newtabpage.activity-stream.showSponsored", false);
user_pref("browser.newtabpage.activity-stream.showSponsoredTopSites", false);

// Debloat: suggestions, pocket, discovery
user_pref("browser.urlbar.quicksuggest.enabled", false);
user_pref("browser.urlbar.suggest.quicksuggest.sponsored", false);
user_pref("browser.urlbar.suggest.quicksuggest.nonsponsored", false);
user_pref("browser.discovery.enabled", false);
user_pref("extensions.pocket.enabled", false);
user_pref("captivedetect.canonicalURL", "");
user_pref("network.captive-portal-service.enabled", false);

// Follow GNOME / freedesktop color-scheme (Wayland portal)
user_pref("widget.content.gtk", true);
user_pref("layout.css.prefers-color-scheme.enabled", true);
user_pref("browser.theme.content-theme", 0);
user_pref("browser.theme.toolbar-theme", 0);
