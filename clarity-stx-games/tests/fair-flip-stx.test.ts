import { describe, expect, it } from "vitest";
import { boolCV, bufferCV, cvToString, uintCV } from "@stacks/transactions";

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

    expect(cvToString(response.result)).toContain(
      "SP3PXGYYR9Y7GCQKNDWTWJW4R1YMAZ97VKSDWAGB8",
    );
  });

  it("rejects wagers below the minimum", () => {
    const response = simnet.callPublicFn(
      "fair-flip-stx",
      "create-flip",
      [
        bufferCV(Buffer.alloc(32, 0x11)),
        bufferCV(Buffer.alloc(32, 0x22)),
        uintCV(1),
        boolCV(true),
      ],
      wallet1,
    );

    expect(response.result).toBeErr(uintCV(102));
  });
});
