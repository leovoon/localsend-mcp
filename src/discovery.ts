/**
 * UDP Multicast Peer Discovery for LocalSend.
 */

import * as dgram from "node:dgram";
import type { DeviceInfo, LocalSendConfig, Peer } from "./types.js";
import { DEFAULT_PORT, MULTICAST_ADDRESS, PROTOCOL_VERSION } from "./types.js";
import { ensureTlsMaterial } from "./tls.js";

export interface DiscoveryOptions {
  timeoutMs?: number;
  listenPort?: number;
  signal?: AbortSignal;
}

export interface DiscoveryResult {
  peers: Peer[];
  warnings: string[];
}

export class PeerCollector {
  private peersMap = new Map<string, Peer>();

  constructor(private ownFingerprint: string) {}

  public add(info: any, host: string): void {
    if (!info || typeof info !== "object" || !host) return;
    if (info.fingerprint && info.fingerprint === this.ownFingerprint) return;

    const alias = typeof info.alias === "string" ? info.alias : host;
    const port = typeof info.port === "number" && info.port > 0 ? info.port : DEFAULT_PORT;
    const protocol = info.protocol === "http" ? "http" : "https";

    const peer: Peer = {
      alias,
      host,
      port,
      protocol,
      fingerprint: String(info.fingerprint || ""),
      deviceModel: info.deviceModel,
      deviceType: info.deviceType,
      download: info.download,
    };

    this.peersMap.set(`${host}:${port}`, peer);
  }

  public list(): Peer[] {
    return [...this.peersMap.values()].sort((a, b) => a.alias.localeCompare(b.alias));
  }
}

function delay(ms: number, signal?: AbortSignal): Promise<void> {
  return new Promise((resolve) => {
    const timer = setTimeout(resolve, ms);
    signal?.addEventListener("abort", () => {
      clearTimeout(timer);
      resolve();
    }, { once: true });
  });
}

export async function discoverPeers(
  config: LocalSendConfig,
  options: DiscoveryOptions = {},
): Promise<DiscoveryResult> {
  const timeoutMs = options.timeoutMs ?? 3000;
  const listenPort = options.listenPort ?? config.port;
  const tls = config.protocol === "https" ? ensureTlsMaterial() : null;
  const ownFingerprint = tls?.fingerprint || config.fingerprint;

  const collector = new PeerCollector(ownFingerprint);
  const warnings: string[] = [];

  const sender = dgram.createSocket({ type: "udp4", reuseAddr: true });
  let multicastListener: dgram.Socket | null = null;

  try {
    await new Promise<void>((resolve, reject) => {
      sender.once("error", reject);
      sender.bind(0, () => {
        try {
          sender.setBroadcast(true);
          sender.setMulticastTTL(1);
        } catch {}
        resolve();
      });
    });

    // Try to join multicast group to pick up incoming announcements
    multicastListener = await new Promise<dgram.Socket | null>((resolve) => {
      const socket = dgram.createSocket({ type: "udp4", reuseAddr: true });
      let settled = false;

      socket.on("error", () => {
        if (!settled) {
          settled = true;
          warnings.push("Could not bind UDP 53317 (LocalSend app is likely running). Multicast broadcast fallback active.");
          try { socket.close(); } catch {}
          resolve(null);
        }
      });

      socket.on("message", (msg, rinfo) => {
        try {
          const parsed = JSON.parse(msg.toString("utf-8"));
          collector.add(parsed, rinfo.address);
        } catch {}
      });

      socket.bind(DEFAULT_PORT, () => {
        try {
          socket.addMembership(MULTICAST_ADDRESS);
        } catch {}
        if (!settled) {
          settled = true;
          resolve(socket);
        }
      });
    });

    const announcement: DeviceInfo = {
      alias: config.alias,
      version: PROTOCOL_VERSION,
      deviceModel: config.deviceModel,
      deviceType: config.deviceType,
      fingerprint: ownFingerprint,
      port: listenPort,
      protocol: config.protocol,
      download: true,
      ...( { announce: true } as any ),
    };

    const packet = Buffer.from(JSON.stringify(announcement), "utf-8");

    // Fire 3 UDP bursts
    const bursts = [0, 400, 1200].filter((t) => t < timeoutMs);
    for (const t of bursts) {
      void delay(t, options.signal).then(() => {
        try {
          sender.send(packet, DEFAULT_PORT, MULTICAST_ADDRESS);
        } catch {}
      });
    }

    await delay(timeoutMs, options.signal);
  } finally {
    try { sender.close(); } catch {}
    if (multicastListener) {
      try { multicastListener.close(); } catch {}
    }
  }

  return {
    peers: collector.list(),
    warnings,
  };
}

export function findPeer(peers: ReadonlyArray<Peer>, query: string): Peer | undefined {
  const target = query.trim().toLowerCase();
  return (
    peers.find((p) => p.alias.toLowerCase() === target) ??
    peers.find((p) => p.fingerprint.toLowerCase() === target) ??
    peers.find((p) => p.host === query.trim()) ??
    peers.find((p) => p.alias.toLowerCase().includes(target))
  );
}
