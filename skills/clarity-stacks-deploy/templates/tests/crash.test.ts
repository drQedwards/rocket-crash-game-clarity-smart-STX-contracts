import { Cl } from "@stacks/transactions";
import { describe, expect, it } from "vitest";
import { createHash } from "node:crypto";

const CONTRACT = "crash";

const accounts = simnet.getAccounts();
const deployer = accounts.get("deployer")!;
const wallet1 = accounts.get("wallet_1")!;
const wallet2 = accounts.get("wallet_2")!;

const STX_1 = 1_000_000n;
const STX_10 = 10_000_000n;
const STX_100 = 100_000_000n;

function sha256(buf: Buffer): Buffer {
  return createHash("sha256").update(buf).digest();
}

function randomSecret(): Buffer {
  const b = Buffer.alloc(32);
  for (let i = 0; i < 32; i++) b[i] = Math.floor(Math.random() * 256);
  return b;
}

describe("crash", () => {
  it("commit → bet (player1) → bet (player2) → close → reveal → settle each", () => {
    simnet.callPublicFn(
      CONTRACT,
      "fund-bond",
      [Cl.uint(STX_100 * 100n)],
      deployer,
    );

    const secret = randomSecret();
    const commit = sha256(secret);
    const c = simnet.callPublicFn(
      CONTRACT,
      "commit-round",
      [Cl.buffer(commit)],
      deployer,
    );
    expect(c.result).toBeOk(Cl.uint(1));

    // Player 1 targets 2.00x with 10 STX
    const b1 = simnet.callPublicFn(
      CONTRACT,
      "place-bet",
      [Cl.uint(200), Cl.uint(STX_10)],
      wallet1,
    );
    expect(b1.result.type).toBe("ok");

    // Player 2 targets 5.00x with 1 STX
    const b2 = simnet.callPublicFn(
      CONTRACT,
      "place-bet",
      [Cl.uint(500), Cl.uint(STX_1)],
      wallet2,
    );
    expect(b2.result.type).toBe("ok");

    // Lock the round
    const close = simnet.callPublicFn(CONTRACT, "close-round", [Cl.uint(1)], deployer);
    expect(close.result).toBeOk(Cl.bool(true));

    // Mine forward so block-id-hash of close-block is queryable
    simnet.mineEmptyBlock();

    // Reveal
    const r = simnet.callPublicFn(
      CONTRACT,
      "reveal-round",
      [Cl.uint(1), Cl.buffer(secret)],
      deployer,
    );
    expect(r.result.type).toBe("ok");

    // Settle each player's bet
    const s1 = simnet.callPublicFn(CONTRACT, "settle-bet", [Cl.uint(1)], wallet1);
    expect(s1.result.type).toBe("ok");

    const s2 = simnet.callPublicFn(CONTRACT, "settle-bet", [Cl.uint(1)], wallet2);
    expect(s2.result.type).toBe("ok");
  });

  it("rejects target below 1.01x", () => {
    simnet.callPublicFn(CONTRACT, "fund-bond", [Cl.uint(STX_100 * 10n)], deployer);
    simnet.callPublicFn(
      CONTRACT,
      "commit-round",
      [Cl.buffer(sha256(randomSecret()))],
      deployer,
    );
    const r = simnet.callPublicFn(
      CONTRACT,
      "place-bet",
      [Cl.uint(100), Cl.uint(STX_1)],
      wallet1,
    );
    expect(r.result).toBeErr(Cl.uint(105)); // ERR-BAD-TARGET
  });

  it("rejects bet on a LOCKED round", () => {
    simnet.callPublicFn(CONTRACT, "fund-bond", [Cl.uint(STX_100 * 10n)], deployer);
    simnet.callPublicFn(
      CONTRACT,
      "commit-round",
      [Cl.buffer(sha256(randomSecret()))],
      deployer,
    );
    simnet.callPublicFn(CONTRACT, "close-round", [Cl.uint(1)], deployer);
    const r = simnet.callPublicFn(
      CONTRACT,
      "place-bet",
      [Cl.uint(200), Cl.uint(STX_1)],
      wallet1,
    );
    expect(r.result).toBeErr(Cl.uint(110)); // ERR-NOT-OPEN
  });
});
