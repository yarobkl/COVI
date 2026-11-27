import assert from "node:assert/strict";
import test from "node:test";
import {
    createNativeTeamHandler,
    supabaseSessionVerifier,
} from "../functions/covi-native-team/handler.mjs";

const account = "01000000-0000-4000-8000-000000000001";
const session = "11000000-0000-4000-8000-000000000001";
const shop = "21000000-0000-4000-8000-000000000001";
const invitation = "31000000-0000-4000-8000-000000000001";
const claims = { sub: account, session_id: session };

function token(payload = {}) {
    return `test.${Buffer.from(JSON.stringify({ ...claims, role: "authenticated", ...payload })).toString("base64url")}.test`;
}

function request(command, bearer = token()) {
    return new Request("https://gateway.example.test", {
        method: "POST",
        headers: { Authorization: `Bearer ${bearer}`, "Content-Type": "application/json; charset=utf-8" },
        body: JSON.stringify(command),
    });
}

test("verifies the same bearer with the configured Auth server and passes only account and session", async () => {
    const signedTestToken = token({ user_metadata: { role: "owner" } });
    const verify = supabaseSessionVerifier("https://staging.example.test", "fixture-key", async (url, options) => {
        assert.equal(url.href, "https://staging.example.test/auth/v1/user");
        assert.equal(options.headers.Authorization, `Bearer ${signedTestToken}`);
        assert.equal(options.headers.apikey, "fixture-key");
        assert.equal(options.redirect, "error");
        return Response.json({ id: account, is_anonymous: false });
    });
    assert.deepEqual(await verify(signedTestToken), claims);
});

test("rejects rejected bearers, anonymous sessions, wrong accounts and missing session IDs", async () => {
    const rejected = supabaseSessionVerifier("https://staging.example.test", "fixture-key",
        async () => Response.json({}, { status: 401 }));
    assert.equal(await rejected(token()), null);
    const anonymous = supabaseSessionVerifier("https://staging.example.test", "fixture-key",
        async () => Response.json({ id: account, is_anonymous: true }));
    assert.equal(await anonymous(token()), null);
    const verified = supabaseSessionVerifier("https://staging.example.test", "fixture-key",
        async () => Response.json({ id: account }));
    assert.equal(await verified(token({ sub: shop })), null);
    assert.equal(await verified(token({ session_id: null })), null);
    assert.equal(await verified(token({ role: "service_role" })), null);
});

test("passes only four authorized command shapes and prevents caching", async () => {
    const handle = createNativeTeamHandler({
        verifySession: async () => claims,
        execute: async (sessionClaims, command) => {
            assert.deepEqual(sessionClaims, claims);
            return command;
        },
    });
    const commands = [
        { action: "directory" },
        { action: "issue", establishmentID: shop, role: "cashier" },
        { action: "revoke", establishmentID: shop, invitationID: invitation },
        { action: "redeem", code: invitation },
    ];
    for (const command of commands) {
        const response = await handle(request({ ...command, session_id: invitation, sub: shop }));
        assert.equal(response.status, 200);
        assert.equal(response.headers.get("cache-control"), "no-store");
        assert.deepEqual(await response.json(), command);
    }
});

test("rejects invalid inputs before invoking the database", async () => {
    const handle = createNativeTeamHandler({
        verifySession: async () => assert.fail("Rejected input reached Auth"),
        execute: async () => assert.fail("Rejected input reached the database"),
    });
    assert.equal((await handle(new Request("https://gateway.example.test"))).status, 405);
    assert.equal((await handle(request({ action: "directory" }, "not-a-token"))).status, 401);
    assert.equal((await handle(request({ action: "issue", establishmentID: shop, role: "owner" }))).status, 400);
    assert.equal((await handle(request({ action: "redeem", code: "bad" }))).status, 400);
    assert.equal((await handle(request({ action: "delete" }))).status, 400);
    assert.equal((await handle(request({ action: "directory", padding: "a".repeat(2_100) }))).status, 413);
});

test("requires a verified session and redacts database and Auth failures", async () => {
    const denied = createNativeTeamHandler({
        verifySession: async () => null,
        execute: async () => assert.fail("Unauthenticated request reached the database"),
    });
    assert.equal((await denied(request({ action: "directory" }))).status, 401);
    const unavailable = createNativeTeamHandler({
        verifySession: async () => { throw new Error("Private Auth detail"); },
        execute: async () => assert.fail("Auth outage reached the database"),
    });
    const authFailure = await unavailable(request({ action: "directory" }));
    assert.equal(authFailure.status, 503);
    assert.deepEqual(await authFailure.json(), { error: "service_unavailable" });
    for (const [code, status, error] of [
        ["42501", 403, "access_denied"],
        ["22023", 409, "invitation_unavailable"],
        ["08000", 503, "service_unavailable"],
    ]) {
        const handler = createNativeTeamHandler({
            verifySession: async () => claims,
            execute: async () => { throw Object.assign(new Error("Private database detail"), { code }); },
        });
        const response = await handler(request({ action: "redeem", code: invitation }));
        assert.equal(response.status, status);
        assert.deepEqual(await response.json(), { error });
    }
});
