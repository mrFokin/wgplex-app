import Foundation

// Enums of the API that must survive a value added later: an unrecognized
// string decodes to .unknown(raw), never to a decoding error.

/// `Status.icon`: the menu bar icon chosen by the daemon.
public enum Icon: Equatable, Sendable, Decodable {
    case off, on, warn, paused
    case unknown(String)

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "off": self = .off
        case "on": self = .on
        case "warn": self = .warn
        case "paused": self = .paused
        default: self = .unknown(raw)
        }
    }
}

/// `TunnelStatus.state`: what actually runs.
public enum TunnelState: Equatable, Sendable, Decodable {
    case off, starting, up, dead, error
    case unknown(String)

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "off": self = .off
        case "starting": self = .starting
        case "up": self = .up
        case "dead": self = .dead
        case "error": self = .error
        default: self = .unknown(raw)
        }
    }
}

/// `TunnelStatus.routes`: the route mode of a tunnel.
public enum RouteMode: Equatable, Sendable, Decodable {
    case config, rules
    case unknown(String)

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "config": self = .config
        case "rules": self = .rules
        default: self = .unknown(raw)
        }
    }
}

/// `RuleStatus.fallback`: what a rule does when no tunnel of `via` serves it.
public enum Fallback: Equatable, Sendable, Decodable {
    case `default`, block
    case unknown(String)

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "default": self = .`default`
        case "block": self = .block
        default: self = .unknown(raw)
        }
    }
}

/// `RuleStatus.reason`: why a rule is degraded (set only when `degraded`).
public enum RuleReason: Equatable, Sendable, Decodable {
    case dead, disabled, paused
    case unknown(String)

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "dead": self = .dead
        case "disabled": self = .disabled
        case "paused": self = .paused
        default: self = .unknown(raw)
        }
    }
}

/// `Explanation.kind`.
public enum ExplanationKind: Equatable, Sendable, Decodable {
    case domain, ip
    case unknown(String)

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "domain": self = .domain
        case "ip": self = .ip
        default: self = .unknown(raw)
        }
    }
}

/// `RouteInfo.target`.
public enum RouteTarget: Equatable, Sendable, Decodable {
    case tunnel, direct, reject
    case unknown(String)

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "tunnel": self = .tunnel
        case "direct": self = .direct
        case "reject": self = .reject
        default: self = .unknown(raw)
        }
    }
}

/// `RouteInfo.source`: `endpoint`, `allowed-ips`, `rule-cidr` or `dynamic`.
public enum RouteSource: Equatable, Sendable, Decodable {
    case endpoint, allowedIPs, ruleCIDR, dynamic
    case unknown(String)

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "endpoint": self = .endpoint
        case "allowed-ips": self = .allowedIPs
        case "rule-cidr": self = .ruleCIDR
        case "dynamic": self = .dynamic
        default: self = .unknown(raw)
        }
    }
}
