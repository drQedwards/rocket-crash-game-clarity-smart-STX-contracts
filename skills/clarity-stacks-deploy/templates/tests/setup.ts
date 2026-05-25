import { afterEach, beforeEach } from "vitest";

declare global {
  // eslint-disable-next-line no-var
  var simnet: import("@hirosystems/clarinet-sdk").Simnet;
}

beforeEach(() => {
  // simnet is provided by vitest-environment-clarinet
});

afterEach(() => {
  // Per-test isolation handled by the clarinet env via fork pool.
});

export {};
