import { describe, expect, it } from "vitest";

// Starter Clarinet/Vitest test file. Copy this into the generated Clarinet project
// and expand each case before any testnet/mainnet deployment.

const accounts = simnet.getAccounts();
const deployer = accounts.get("deployer")!;
const wallet1 = accounts.get("wallet_1")!;

describe("fair-flip-stx", () => {
  it("exposes the configured project owner", () => {
    const response = simnet.callReadOnlyFn(
      "fair-flip-stx",
      "get-config",
      [],
      deployer,
    );

    expect(response.result).toContain("SP3PXGYYR9Y7GCQKNDWTWJW4R1YMAZ97VKSDWAGB8");
  });

  it("rejects wagers below the minimum", () => {
    const response = simnet.callPublicFn(
      "fair-flip-stx",
      "create-flip",
      [
        "0x1111111111111111111111111111111111111111111111111111111111111111",
        "0x2222222222222222222222222222222222222222222222222222222222222222",
        "u1",
        "true",
      ],
      wallet1,
    );

    expect(response.result).toBeErr();
  });
});
