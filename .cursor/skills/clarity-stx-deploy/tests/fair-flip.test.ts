import { describe, it, expect, beforeEach } from "vitest";
import { Cl, ClarityValue } from "@stacks/transactions";

// NOTE: Update the import path based on your Clarinet SDK version.
// Clarinet SDK v3+: import { initSimnet } from "@stacks/clarinet-sdk";
// Clarinet SDK v2:  import { initSimnet } from "@hirosystems/clarinet-sdk";
import { initSimnet } from "@stacks/clarinet-sdk";

const simnet = await initSimnet();
const accounts = simnet.getAccounts();
const deployer = accounts.get("deployer")!;
const wallet1 = accounts.get("wallet_1")!;

describe("fair-flip-commit-reveal", () => {
  it("should read config", () => {
    const result = simnet.callReadOnlyFn(
      "fair-flip",
      "get-config",
      [],
      deployer
    );
    expect(result.result).toBeOk(
      expect.objectContaining({
        type: expect.any(Number),
      })
    );
  });

  it("should allow a player to commit", () => {
    // Generate a secret and side
    const secret = new Uint8Array(32);
    crypto.getRandomValues(secret);
    const side = 1; // heads
    const sideByte = new Uint8Array([side]);

    // Compute commitment hash: sha256(secret || side_byte)
    const combined = new Uint8Array(33);
    combined.set(secret, 0);
    combined.set(sideByte, 32);

    // In a real test, compute sha256 of `combined` and pass as buff 32
    // For this template, we use a placeholder hash
    const hash = new Uint8Array(32);
    crypto.getRandomValues(hash);

    const betAmount = 1_000_000; // 1 STX in microSTX

    const result = simnet.callPublicFn(
      "fair-flip",
      "commit",
      [Cl.buffer(hash), Cl.uint(betAmount)],
      wallet1
    );

    expect(result.result).toBeOk(Cl.uint(1)); // game-id = 1
  });

  it("should reject bet below minimum", () => {
    const hash = new Uint8Array(32);
    const betAmount = 100; // way below 1 STX minimum

    const result = simnet.callPublicFn(
      "fair-flip",
      "commit",
      [Cl.buffer(hash), Cl.uint(betAmount)],
      wallet1
    );

    expect(result.result).toBeErr(Cl.uint(107)); // ERR-BELOW-MIN-BET
  });

  it("should reject double commit from same player", () => {
    const hash = new Uint8Array(32);
    crypto.getRandomValues(hash);
    const betAmount = 1_000_000;

    // First commit
    simnet.callPublicFn(
      "fair-flip",
      "commit",
      [Cl.buffer(hash), Cl.uint(betAmount)],
      wallet1
    );

    // Second commit should fail
    const result = simnet.callPublicFn(
      "fair-flip",
      "commit",
      [Cl.buffer(hash), Cl.uint(betAmount)],
      wallet1
    );

    expect(result.result).toBeErr(Cl.uint(102)); // ERR-ALREADY-COMMITTED
  });

  it("should allow owner to pause/unpause", () => {
    const pauseResult = simnet.callPublicFn(
      "fair-flip",
      "set-paused",
      [Cl.bool(true)],
      deployer
    );
    expect(pauseResult.result).toBeOk(Cl.bool(true));

    // Commit should fail when paused
    const hash = new Uint8Array(32);
    const commitResult = simnet.callPublicFn(
      "fair-flip",
      "commit",
      [Cl.buffer(hash), Cl.uint(1_000_000)],
      wallet1
    );
    expect(commitResult.result).toBeErr(Cl.uint(101)); // ERR-PAUSED

    // Unpause
    simnet.callPublicFn(
      "fair-flip",
      "set-paused",
      [Cl.bool(false)],
      deployer
    );
  });

  it("should reject non-owner from admin functions", () => {
    const result = simnet.callPublicFn(
      "fair-flip",
      "set-paused",
      [Cl.bool(true)],
      wallet1
    );
    expect(result.result).toBeErr(Cl.uint(100)); // ERR-NOT-OWNER
  });

  it("should reject fee above 10%", () => {
    const result = simnet.callPublicFn(
      "fair-flip",
      "set-fee-bps",
      [Cl.uint(1001)], // > MAX-FEE-BPS (1000)
      deployer
    );
    expect(result.result).toBeErr(Cl.uint(113)); // ERR-FEE-TOO-HIGH
  });
});
