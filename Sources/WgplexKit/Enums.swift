import Foundation

// Enums of the API that must survive a value added later: an unrecognized
// string decodes to .unknown(raw), never to a decoding error.

/// `Status.icon`: the menu bar icon chosen by the daemon.
public enum Icon: Equatable, Sendable, Decodable {
    case off, on, warn, paused
    case unknown(String)

    public init(from decoder: any Decoder) throws { fatalError("not implemented") }
}

/// `TunnelStatus.state`: what actually runs.
public enum TunnelState: Equatable, Sendable, Decodable {
    case off, starting, up, dead, error
    case unknown(String)

    public init(from decoder: any Decoder) throws { fatalError("not implemented") }
}

/// `TunnelStatus.routes`: the route mode of a tunnel.
public enum RouteMode: Equatable, Sendable, Decodable {
    case config, rules
    case unknown(String)

    public init(from decoder: any Decoder) throws { fatalError("not implemented") }
}

/// `RuleStatus.fallback`: what a rule does when no tunnel of `via` serves it.
public enum Fallback: Equatable, Sendable, Decodable {
    case `default`, block
    case unknown(String)

    public init(from decoder: any Decoder) throws { fatalError("not implemented") }
}

/// `RuleStatus.reason`: why a rule is degraded (set only when `degraded`).
public enum RuleReason: Equatable, Sendable, Decodable {
    case dead, disabled, paused
    case unknown(String)

    public init(from decoder: any Decoder) throws { fatalError("not implemented") }
}

/// `Explanation.kind`.
public enum ExplanationKind: Equatable, Sendable, Decodable {
    case domain, ip
    case unknown(String)

    public init(from decoder: any Decoder) throws { fatalError("not implemented") }
}

/// `RouteInfo.target`.
public enum RouteTarget: Equatable, Sendable, Decodable {
    case tunnel, direct, reject
    case unknown(String)

    public init(from decoder: any Decoder) throws { fatalError("not implemented") }
}

/// `RouteInfo.source`: `endpoint`, `allowed-ips`, `rule-cidr` or `dynamic`.
public enum RouteSource: Equatable, Sendable, Decodable {
    case endpoint, allowedIPs, ruleCIDR, dynamic
    case unknown(String)

    public init(from decoder: any Decoder) throws { fatalError("not implemented") }
}
