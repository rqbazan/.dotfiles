// A fake 1Password Connect server, for the end-to-end test only. With OP_CONNECT_HOST and
// OP_CONNECT_TOKEN set, `op read` and `op inject` talk to it instead of 1Password: for each
// op://vault/item/field they look the vault up by title, then the item, then read the item.
// That is all this implements. Values come from fixtures/vaults.json and are fake.
import { createHash, generateKeyPairSync } from "node:crypto";
import { defineEmulator } from "emulate";

type Field = { label: string; value: string; type?: string };
// An item with `"sshKey": "ed25519"` gets a fresh key pair as its "private key" and "public key" fields.
type Item = { title: string; category: string; fields?: Field[]; sshKey?: string };
type Vault = { name: string; items: Item[] };
type State = { vaults: Vault[] };

// A new Ed25519 pair each time the mock starts, so no private key, not even a fake one, lives in the repo.
// 1Password keeps the private key as PKCS#8; `op read …/private key?ssh-format=openssh` converts it.
function fakeSshKeyFields(): Field[] {
  const { privateKey, publicKey } = generateKeyPairSync("ed25519");
  const raw = Buffer.from(publicKey.export({ format: "jwk" }).x ?? "", "base64url");
  const part = (b: Buffer) => Buffer.concat([Buffer.from([0, 0, 0, b.length]), b]);
  const blob = Buffer.concat([part(Buffer.from("ssh-ed25519")), part(raw)]);
  return [
    { label: "private key", type: "SSHKEY", value: privateKey.export({ type: "pkcs8", format: "pem" }).toString() },
    { label: "public key", value: `ssh-ed25519 ${blob.toString("base64")}` },
  ];
}

// Connect IDs are 26 characters of [a-z0-9]; anything else op treats as a title.
const id = (...parts: string[]) => createHash("sha256").update(parts.join("/")).digest("hex").slice(0, 26);
// op sends filter=title eq "<name>"
const titleIn = (filter: string | undefined) => filter?.match(/^title eq "(.*)"$/)?.[1];

const vaultSummary = (v: Vault) => ({ id: id(v.name), name: v.name, type: "USER_CREATED", items: v.items.length });
const itemSummary = (v: Vault, i: Item) => ({
  id: id(v.name, i.title),
  title: i.title,
  vault: { id: id(v.name) },
  category: i.category,
});
const itemFull = (v: Vault, i: Item) => ({
  ...itemSummary(v, i),
  fields: (i.fields ?? []).map((f) => ({ id: f.label, label: f.label, type: f.type ?? "STRING", value: f.value })),
});

export default defineEmulator({
  name: "onepassword",
  state: (): State => ({ vaults: [] }),
  validateSeed(seed: unknown): State {
    const vaults = (seed as State)?.vaults;
    if (!Array.isArray(vaults) || !vaults.every((v) => typeof v.name === "string" && Array.isArray(v.items))) {
      throw new Error('vaults.json: expected { "vaults": [{ "name": string, "items": [...] }] }');
    }
    return {
      vaults: vaults.map((v) => ({
        ...v,
        items: v.items.map((i) => (i.sshKey ? { ...i, fields: [...(i.fields ?? []), ...fakeSshKeyFields()] } : i)),
      })),
    };
  },
  setup({ app, state }) {
    const notFound = (what: string) => ({ status: 404, message: `${what} not found` });
    const vaultById = (vid: string) => state.vaults.find((v) => id(v.name) === vid);

    // Connect wants a bearer token on /v1; op never checks the token, and neither does this.
    app.use(async (c, next) => {
      if (c.req.path.startsWith("/v1/") && !c.req.header("Authorization")?.startsWith("Bearer ")) {
        return c.json({ status: 401, message: "Invalid bearer token" }, 401);
      }
      await next();
    });

    app.get("/heartbeat", (c) => c.text("."));

    app.get("/v1/vaults", (c) => {
      const title = titleIn(c.req.query("filter"));
      return c.json(state.vaults.filter((v) => title === undefined || v.name === title).map(vaultSummary));
    });

    app.get("/v1/vaults/:vid", (c) => {
      const vault = vaultById(c.req.param("vid"));
      return vault ? c.json(vaultSummary(vault)) : c.json(notFound("vault"), 404);
    });

    app.get("/v1/vaults/:vid/items", (c) => {
      const vault = vaultById(c.req.param("vid"));
      if (!vault) return c.json(notFound("vault"), 404);
      const title = titleIn(c.req.query("filter"));
      return c.json(vault.items.filter((i) => title === undefined || i.title === title).map((i) => itemSummary(vault, i)));
    });

    app.get("/v1/vaults/:vid/items/:iid", (c) => {
      const vault = vaultById(c.req.param("vid"));
      const item = vault?.items.find((i) => id(vault.name, i.title) === c.req.param("iid"));
      return vault && item ? c.json(itemFull(vault, item)) : c.json(notFound("item"), 404);
    });
  },
});
