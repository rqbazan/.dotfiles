import { createEmulator } from "emulate";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import vaults from "../fixtures/vaults.json" with { type: "json" };
import onepassword from "../src/connect.ts";

type VaultSummary = { id: string; name: string; items: number };
type ItemSummary = { id: string; title: string };
type ItemFull = ItemSummary & { fields: { label: string; value: string }[] };

const start = () => createEmulator({ service: onepassword, listen: false, seed: vaults });
let api: Awaited<ReturnType<typeof start>>;

beforeEach(async () => {
  api = await start();
});

afterEach(async () => {
  await api.close();
});

const auth = { headers: { Authorization: "Bearer fake-connect-token" } };
const byTitle = (title: string) => `filter=${encodeURIComponent(`title eq "${title}"`)}`;

async function get<T>(path: string): Promise<T> {
  const res = await api.request(path, auth);
  expect(res.status).toBe(200);
  return (await res.json()) as T;
}

async function one<T>(path: string): Promise<T> {
  const found = await get<T[]>(path);
  expect(found).toHaveLength(1);
  return found[0] as T;
}

// What `op read op://<vault>/<item>/<field>` does against a Connect server.
async function read(vault: string, item: string, field: string) {
  const v = await one<VaultSummary>(`/v1/vaults?${byTitle(vault)}`);
  const i = await one<ItemSummary>(`/v1/vaults/${v.id}/items?${byTitle(item)}`);
  const full = await get<ItemFull>(`/v1/vaults/${v.id}/items/${i.id}`);
  return full.fields.find((f) => f.label === field)?.value;
}

describe("the fake 1Password Connect server", () => {
  it("answers the heartbeat without a token", async () => {
    const res = await api.request("/heartbeat");
    expect(res.status).toBe(200);
    expect(await res.text()).toBe(".");
  });

  it("refuses /v1 without a bearer token, like Connect", async () => {
    expect((await api.request("/v1/vaults")).status).toBe(401);
  });

  it("finds a vault by title, and only that one", async () => {
    const vault = await one<VaultSummary>(`/v1/vaults?${byTitle("rcrd-dotfiles")}`);
    expect(vault).toMatchObject({ name: "rcrd-dotfiles", items: 2 });
  });

  it("gives IDs of 26 characters of [a-z0-9], or op would take them for titles", async () => {
    const all = await get<VaultSummary[]>("/v1/vaults");
    expect(all).toHaveLength(3);
    for (const vault of all) expect(vault.id).toMatch(/^[a-z0-9]{26}$/);
  });

  it("serves the fixtures' fake values the way op reads them", async () => {
    expect(await read("dotfiles", "context7", "credential")).toBe("fake-context7-api-key");
    expect(await read("rcrd-dotfiles", "npm", "credential")).toBe("fake-npm-token");
    expect(await read("rcrd-dotfiles", "vland-registry", "url")).toBe("registry.invalid/fake/npm");
  });

  it("makes a fresh SSH key pair for an item with sshKey, as 1Password stores one", async () => {
    expect(await read("dotfiles", "github", "private key")).toMatch(/^-----BEGIN PRIVATE KEY-----\n/);
    expect(await read("dotfiles", "github", "public key")).toMatch(/^ssh-ed25519 AAAAC3NzaC1lZDI1NTE5[A-Za-z0-9+/=]+$/);
  });

  it("finds no item that the vault doesn't have", async () => {
    const vault = await one<VaultSummary>(`/v1/vaults?${byTitle("np-dotfiles")}`);
    expect(await get<ItemSummary[]>(`/v1/vaults/${vault.id}/items?${byTitle("npm")}`)).toEqual([]);
  });

  it("answers 404 for a vault ID it doesn't know", async () => {
    expect((await api.request("/v1/vaults/aaaaaaaaaaaaaaaaaaaaaaaaaa/items", auth)).status).toBe(404);
  });
});
