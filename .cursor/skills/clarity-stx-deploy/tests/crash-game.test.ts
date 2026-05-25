import { describe, it, expect } from "vitest";
import { Cl } from "@stacks/transactions";

// NOTE: Update import based on your Clarinet SDK version
import { initSimnet } from "@stacks/clarinet-sdk";

const simnet = await initSimnet();
const accounts = simnet.getAccounts();
const deployer = accounts.get("deployer")!;
const wallet1 = accounts.get("wallet_1")!;
const wallet2 = accounts.get("wallet_2")!;

describe("crash-game", () => {
  it("should read config", () => {
    const result = simnet.callReadOnlyFn(
      "crash-game",
      "get-config",
      [],
      deployer
    );
    expect(result.result).toBeOk(
      expect.objectContaining({ type: expect.any(Number) })
    );
  });

  it("should allow owner to start a round", () => {
    const seedHash = new Uint8Array(32);
    crypto.getRandomValues(seedHash);

    const result = simnet.callPublicFn(
      "crash-game",
      "start-round",
      [Cl.buffer(seedHash)],
      deployer
    );
    expect(result.result).toBeOk(Cl.uint(1)); // round-id = 1
  });

  it("should reject non-owner from starting a round", () => {
    const seedHash = new Uint8Array(32);
    const result = simnet.callPublicFn(
      "crash-game",
      "start-round",
      [Cl.buffer(seedHash)],
      wallet1
    );
    expect(result.result).toBeErr(Cl.uint(200)); // ERR-NOT-OWNER
  });

  it("should allow player to join an open round", () => {
    // Start a round first
    const seedHash = new Uint8Array(32);
    crypto.getRandomValues(seedHash);
    simnet.callPublicFn(
      "crash-game",
      "start-round",
      [Cl.buffer(seedHash)],
      deployer
    );

    const roundId = 2; // second round
    const betAmount = 5_000_000; // 5 STX
    const autoCashout = 200; // 2.00x

    const result = simnet.callPublicFn(
      "crash-game",
      "join-round",
      [Cl.uint(roundId), Cl.uint(betAmount), Cl.uint(autoCashout)],
      wallet1
    );
    expect(result.result).toBeOk(Cl.bool(true));
  });

  it("should reject bets below minimum", () => {
    const seedHash = new Uint8Array(32);
    crypto.getRandomValues(seedHash);
    simnet.callPublicFn(
      "crash-game",
      "start-round",
      [Cl.buffer(seedHash)],
      deployer
    );

    const result = simnet.callPublicFn(
      "crash-game",
      "join-round",
      [Cl.uint(3), Cl.uint(100), Cl.uint(200)], // 100 microSTX < min
      wallet1
    );
    expect(result.result).toBeErr(Cl.uint(208)); // ERR-BELOW-MIN-BET
  });

  it("should reject invalid cashout multiplier", () => {
    const seedHash = new Uint8Array(32);
    crypto.getRandomValues(seedHash);
    simnet.callPublicFn(
      "crash-game",
      "start-round",
      [Cl.buffer(seedHash)],
      deployer
    );

    const result = simnet.callPublicFn(
      "crash-game",
      "join-round",
      [Cl.uint(4), Cl.uint(1_000_000), Cl.uint(50)], // 0.50x < MIN_CASHOUT
      wallet1
    );
    expect(result.result).toBeErr(Cl.uint(207)); // ERR-INVALID-CASHOUT
  });

  it("should allow owner to pause and block new rounds", () => {
    simnet.callPublicFn(
      "crash-game",
      "set-paused",
      [Cl.bool(true)],
      deployer
    );

    const seedHash = new Uint8Array(32);
    const result = simnet.callPublicFn(
      "crash-game",
      "start-round",
      [Cl.buffer(seedHash)],
      deployer
    );
    expect(result.result).toBeErr(Cl.uint(201)); // ERR-PAUSED

    // Unpause for subsequent tests
    simnet.callPublicFn(
      "crash-game",
      "set-paused",
      [Cl.bool(false)],
      deployer
    );
  });
});
