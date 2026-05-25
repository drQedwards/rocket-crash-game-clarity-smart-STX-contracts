import { Cl } from "@stacks/transactions";
import { describe, expect, it } from "vitest";

const CONTRACT = "fair-flip-vrf";

const accounts = simnet.getAccounts();
const deployer = accounts.get("deployer")!;
const wallet1 = accounts.get("wallet_1")!;

const STX_100 = 100_000_000n;

describe("fair-flip-vrf", () => {
  it("rejects place-bet before vrf-pubkey is set", () => {
    simnet.callPublicFn(CONTRACT, "fund-bond", [Cl.uint(STX_100 * 10n)], deployer);
    const r = simnet.callPublicFn(
      CONTRACT,
      "place-bet",
      [Cl.uint(0), Cl.uint(STX_100)],
      wallet1,
    );
    expect(r.result).toBeErr(Cl.uint(102)); // ERR-NO-PUBKEY
  });

  it("rejects set-vrf-pubkey from non-owner", () => {
    const fakePk = Buffer.alloc(33, 0x02);
    const r = simnet.callPublicFn(
      CONTRACT,
      "set-vrf-pubkey",
      [Cl.buffer(fakePk)],
      wallet1,
    );
    expect(r.result).toBeErr(Cl.uint(100)); // ERR-NOT-OWNER
  });

  it("owner can set vrf-pubkey and place a bet", () => {
    const fakePk = Buffer.alloc(33, 0x02);
    simnet.callPublicFn(
      CONTRACT,
      "set-vrf-pubkey",
      [Cl.buffer(fakePk)],
      deployer,
    );
    simnet.callPublicFn(CONTRACT, "fund-bond", [Cl.uint(STX_100 * 10n)], deployer);
    const r = simnet.callPublicFn(
      CONTRACT,
      "place-bet",
      [Cl.uint(0), Cl.uint(STX_100)],
      wallet1,
    );
    expect(r.result).toBeOk(Cl.uint(0));
  });

  it("settle-bet rejects an invalid signature", () => {
    const fakePk = Buffer.alloc(33, 0x02);
    simnet.callPublicFn(
      CONTRACT,
      "set-vrf-pubkey",
      [Cl.buffer(fakePk)],
      deployer,
    );
    simnet.callPublicFn(CONTRACT, "fund-bond", [Cl.uint(STX_100 * 10n)], deployer);
    simnet.callPublicFn(
      CONTRACT,
      "place-bet",
      [Cl.uint(0), Cl.uint(STX_100)],
      wallet1,
    );
    simnet.mineEmptyBlock();

    const fakeSig = Buffer.alloc(65, 0x01);
    const r = simnet.callPublicFn(
      CONTRACT,
      "settle-bet",
      [Cl.uint(0), Cl.buffer(fakeSig)],
      wallet1,
    );
    expect(r.result).toBeErr(Cl.uint(103)); // ERR-BAD-SIGNATURE
  });
});

// NOTE: full signature-verification happy path requires deriving an ECDSA
// signature off-chain and feeding it in. See `references/randomness.md` for
// a Node.js helper using @noble/secp256k1 that you can drop into a test.
