import Foundation

// JSON fixtures taken from the tables of the engine's docs/api.md
// (api_version 1). No WireGuard keys.

enum Fixture {
    /// Full status.get for a caller that can control: two tunnels, one up
    /// with a check, one in error; one rule on a backup.
    static let statusFull = """
        {
          "api_version": 1,
          "version": "0.1.0-dev",
          "can_control": true,
          "control_group": "admin",
          "configured": true,
          "block_snapshot": false,
          "paused": false,
          "config_dir": "/opt/homebrew/etc/wgplex",
          "log_path": "/opt/homebrew/var/log/wgplex.log",
          "icon": "warn",
          "config_errors": ["wg0.conf: bad line"],
          "config_error_count": 1,
          "warnings": ["rule 1: unused service"],
          "warning_count": 1,
          "tunnels": [
            {
              "name": "work",
              "enabled": true,
              "state": "up",
              "interface": "utun5",
              "addresses": ["10.0.0.2/32", "fd00::2/128"],
              "routes": "rules",
              "route_count": 7,
              "peers": [
                {
                  "endpoint": "vpn.example.com:51820",
                  "resolved": "203.0.113.7:51820",
                  "last_handshake": "2026-11-05T10:20:30.123456789Z",
                  "rx_bytes": 1024,
                  "tx_bytes": 2048
                }
              ],
              "check": {
                "addr": "https://check.example.com/?token=abc",
                "last_ok": "2026-11-05T10:20:31Z",
                "rtt_ms": 12.5,
                "fails": 0
              }
            },
            {
              "name": "home",
              "enabled": true,
              "state": "error",
              "error": "resolve vpn.home.example: no such host",
              "routes": "config",
              "route_count": 0
            }
          ],
          "rules": [
            {
              "index": 0,
              "services": ["telegram", "youtube"],
              "via": ["work", "home"],
              "fallback": "block",
              "tunnel": "work",
              "in_fallback": false,
              "degraded": false
            },
            {
              "index": 1,
              "services": ["github"],
              "via": ["home", "work"],
              "fallback": "default",
              "tunnel": "work",
              "in_fallback": false,
              "degraded": true,
              "reason": "dead"
            }
          ]
        }
        """

    /// status.get for a caller that cannot control: redacted fields absent,
    /// counts present.
    static let statusRedacted = """
        {
          "api_version": 1,
          "version": "0.1.0-dev",
          "can_control": false,
          "control_group": "admin",
          "configured": true,
          "paused": false,
          "config_dir": "/opt/homebrew/etc/wgplex",
          "log_path": "/opt/homebrew/var/log/wgplex.log",
          "icon": "warn",
          "config_error_count": 2,
          "warning_count": 3,
          "tunnels": [
            {
              "name": "work",
              "enabled": true,
              "state": "dead",
              "interface": "utun5",
              "routes": "rules",
              "route_count": 3,
              "peers": [{"rx_bytes": 5, "tx_bytes": 6}],
              "check": {"fails": 4}
            },
            {"name": "home", "enabled": true, "state": "error", "routes": "config", "route_count": 0}
          ],
          "rules": []
        }
        """

    /// Daemon paused: every tunnel off with the toggle kept, rules degraded
    /// with reason paused.
    static let statusPaused = """
        {
          "api_version": 1,
          "version": "0.1.0-dev",
          "can_control": true,
          "control_group": "",
          "configured": true,
          "paused": true,
          "config_dir": "/opt/homebrew/etc/wgplex",
          "log_path": "/opt/homebrew/var/log/wgplex.log",
          "icon": "paused",
          "config_error_count": 0,
          "warning_count": 0,
          "tunnels": [
            {"name": "work", "enabled": true, "state": "off", "routes": "rules", "route_count": 0}
          ],
          "rules": [
            {"index": 0, "services": ["telegram"], "via": ["work"], "fallback": "block",
             "in_fallback": true, "degraded": true, "reason": "paused"}
          ]
        }
        """

    /// No config applied, the block snapshot is enforced.
    static let statusNotConfigured = """
        {
          "api_version": 1,
          "version": "0.1.0-dev",
          "can_control": true,
          "control_group": "",
          "configured": false,
          "block_snapshot": true,
          "paused": false,
          "config_dir": "/opt/homebrew/etc/wgplex",
          "log_path": "/opt/homebrew/var/log/wgplex.log",
          "icon": "warn",
          "config_errors": ["no such directory"],
          "config_error_count": 1,
          "warning_count": 0,
          "tunnels": [],
          "rules": []
        }
        """

    /// Degraded rules, one per reason (plus a healthy direct one).
    static let statusDegraded = """
        {
          "api_version": 1, "version": "0.1.0-dev", "can_control": true, "control_group": "",
          "configured": true, "paused": false, "config_dir": "/c", "log_path": "/l", "icon": "warn",
          "config_error_count": 0, "warning_count": 0,
          "tunnels": [],
          "rules": [
            {"index": 0, "services": ["a"], "via": ["t1", "t2"], "fallback": "default",
             "tunnel": "t2", "in_fallback": false, "degraded": true, "reason": "dead"},
            {"index": 1, "services": ["b"], "via": ["t1"], "fallback": "block",
             "in_fallback": true, "degraded": true, "reason": "disabled"},
            {"index": 2, "services": ["c"], "via": ["t1"], "fallback": "default",
             "in_fallback": true, "degraded": true, "reason": "paused"},
            {"index": 3, "services": ["d"], "via": [], "fallback": "default",
             "in_fallback": false, "degraded": false}
          ]
        }
        """

    static let explainDomain = """
        {
          "query": "example.com",
          "kind": "domain",
          "rule": {"index": 0, "services": ["example"], "via": ["work"], "fallback": "block",
                   "tunnel": "work", "in_fallback": false, "degraded": false},
          "skipped": {"index": 2, "services": ["other"], "via": ["home"], "fallback": "default",
                      "in_fallback": true, "degraded": true, "reason": "dead"},
          "upstream": "work",
          "zone": "example.com",
          "servers": ["10.0.0.1"],
          "drop_aaaa": true,
          "addrs": ["93.184.216.34"]
        }
        """

    static let explainIP = """
        {
          "query": "93.184.216.34",
          "kind": "ip",
          "rule": {"index": 0, "services": ["example"], "via": ["work"], "fallback": "default",
                   "tunnel": "work", "in_fallback": false, "degraded": false},
          "route": {"prefix": "93.184.216.0/24", "target": "tunnel", "tunnel": "work",
                    "source": "rule-cidr", "rule": 0}
        }
        """

    /// Explanation without optional parts (system default applies).
    static let explainBare = #"{"query": "10.1.2.3", "kind": "ip"}"#

    static let routes = """
        {
          "routes": [
            {"prefix": "10.0.0.0/8", "target": "tunnel", "tunnel": "work", "source": "allowed-ips", "rule": -1},
            {"prefix": "203.0.113.7/32", "target": "direct", "source": "endpoint", "rule": -1},
            {"prefix": "198.51.100.0/24", "target": "reject", "tunnel": "home", "source": "rule-cidr", "rule": 1},
            {"prefix": "192.0.2.9/32", "target": "tunnel", "tunnel": "work", "source": "dynamic", "rule": 0,
             "names": ["a.example.com"], "skipped": "no physical gateway"}
          ],
          "sync_error": "route add: file exists"
        }
        """

    static let applyResult = """
        {"warnings": ["w1"], "tunnels": [{"name": "home", "error": "boom"}]}
        """

    static let applyResultMinimal = #"{"warnings": []}"#
}
