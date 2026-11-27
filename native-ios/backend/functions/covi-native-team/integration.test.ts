import assert from "node:assert/strict";
import postgres from "npm:postgres@3.4.8";
import { createNativeTeamHandler } from "./handler.mjs";
import { teamOperations } from "./operations.ts";

const shop = "22000000-0000-4000-8000-000000000001";
const ownerToken = "owner.test.fixture";
const memberToken = "member.test.fixture";
const sessions = new Map([
    [ownerToken, {
        sub: "02000000-0000-4000-8000-000000000001",
        session_id: "12000000-0000-4000-8000-000000000001",
    }],
    [memberToken, {
        sub: "02000000-0000-4000-8000-000000000002",
        session_id: "12000000-0000-4000-8000-000000000002",
    }],
]);

Deno.test("HTTP team gateway runs under the restricted SQL role on one reused connection", async () => {
    const databaseURL = Deno.env.get("COVI_TEAM_TEST_DATABASE_URL");
    assert.ok(databaseURL, "The disposable PostgreSQL service is required");
    const database = postgres(databaseURL, { max: 1, prepare: false, connect_timeout: 5, ssl: false });
    try {
        const handle = createNativeTeamHandler({
            verifySession: async (token: string) => sessions.get(token) ?? null,
            execute: teamOperations(database),
        });
        async function send(token: string, command: object, status: number) {
            const response = await handle(new Request("https://gateway.example.test", {
                method: "POST",
                headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
                body: JSON.stringify(command),
            }));
            const body = await response.json();
            assert.equal(response.status, status, JSON.stringify(body));
            return body;
        }

        const directory = { action: "directory" };
        const issue = { action: "issue", establishmentID: shop, role: "cashier" };
        assert.deepEqual(await send(ownerToken, directory, 200),
            { establishments: [{ establishment_id: shop, role: "owner" }] });
        assert.deepEqual(await send(memberToken, directory, 200), { establishments: [] });
        await send(memberToken, issue, 403);

        const { invitation } = await send(ownerToken, issue, 200);
        const redeem = { action: "redeem", code: invitation.code };
        assert.deepEqual(await send(memberToken, redeem, 200),
            { membership: { establishment_id: shop, role: "cashier" } });
        await send(memberToken, redeem, 409);
        assert.deepEqual(await send(memberToken, directory, 200),
            { establishments: [{ establishment_id: shop, role: "cashier" }] });

        const revoked = (await send(ownerToken, issue, 200)).invitation;
        assert.deepEqual(await send(ownerToken, {
            action: "revoke", establishmentID: shop, invitationID: revoked.invitation_id,
        }, 200), { revoked: true });
        await send(memberToken, { action: "redeem", code: revoked.code }, 409);
        await send("unknown.test.fixture", directory, 401);
    } finally {
        await database.end({ timeout: 1 });
    }
});
