import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { receiptAIDailyLimit } from "./_shared/receipt-ai-quota.ts";

async function sourceFor(functionName: string): Promise<string> {
  return await Deno.readTextFile(
    new URL(`./${functionName}/index.ts`, import.meta.url),
  );
}

async function quotaLimitArgumentFor(functionName: string): Promise<string> {
  const source = await Deno.readTextFile(
    new URL(`./${functionName}/index.ts`, import.meta.url),
  );
  const match = source.match(/\bp_limit:\s*([A-Za-z0-9_]+)/);
  if (!match) {
    throw new Error(`Missing quota p_limit in ${functionName}`);
  }
  return match[1];
}

Deno.test("receipt AI scan and bill item analysis use one code-owned daily quota", async () => {
  assertEquals(receiptAIDailyLimit, 30);
  assertEquals(await quotaLimitArgumentFor("analyze-receipt"), "receiptAIDailyLimit");
  assertEquals(await quotaLimitArgumentFor("analyze-bill-items"), "receiptAIDailyLimit");
  assertEquals((await sourceFor("analyze-receipt")).includes("const dailyLimit"), false);
  assertEquals((await sourceFor("analyze-bill-items")).includes("const dailyLimit"), false);
});
