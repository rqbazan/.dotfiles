// emulate (https://emulate.dev) serves the fake 1Password. The port comes from the command line
// (the start task in mise.toml, or tests/run.sh, which also picks the address).
import { defineConfig } from "emulate";
import vaults from "./fixtures/vaults.json" with { type: "json" };
import onepassword from "./src/connect.ts";

export default defineConfig({
  services: {
    onepassword: { emulator: onepassword, seed: vaults },
  },
});
