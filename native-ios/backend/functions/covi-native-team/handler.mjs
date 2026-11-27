const uuid = /^[\da-f]{8}(?:-[\da-f]{4}){3}-[\da-f]{12}$/i;
const tokenPattern = /^Bearer ([\w-]+\.[\w-]+\.[\w-]+)$/i;
const roles = new Set(["manager", "seller", "cashier", "waiter", "kitchen", "stylist", "reception"]);
const bodyLimit = 2_048;

function isUUID(value) {
    return typeof value === "string" && uuid.test(value);
}

function json(status, value, extraHeaders = {}) {
    return Response.json(value, {
        status,
        headers: { "Cache-Control": "no-store", ...extraHeaders },
    });
}

export function supabaseSessionVerifier(projectURL, publishableKey, fetcher = fetch) {
    const userURL = new URL("/auth/v1/user", projectURL);
    return async (token) => {
        const response = await fetcher(userURL, {
            headers: { apikey: publishableKey, Authorization: `Bearer ${token}` },
            redirect: "error",
            signal: AbortSignal.timeout(5_000),
        });
        if ([400, 401, 403].includes(response.status)) return null;
        if (!response.ok) throw new Error("Auth unavailable");
        const user = await response.json();

        // Auth has verified this exact bearer. Forward only the account and
        // session identifiers that the private database functions recheck.
        let jwt;
        try {
            const encoded = token.split(".")[1].replaceAll("-", "+").replaceAll("_", "/");
            jwt = JSON.parse(new TextDecoder().decode(Uint8Array.from(atob(encoded), c => c.charCodeAt(0))));
        } catch {
            return null;
        }
        if (!jwt || jwt.role !== "authenticated" || jwt.is_anonymous === true || user?.is_anonymous === true ||
            !isUUID(user?.id) || jwt.sub !== user.id || !isUUID(jwt.session_id)) return null;
        return { sub: user.id, session_id: jwt.session_id };
    };
}

async function readBody(request) {
    if (Number(request.headers.get("content-length")) > bodyLimit) return { tooLarge: true };
    const reader = request.body?.getReader();
    if (!reader) return {};
    const decoder = new TextDecoder("utf-8", { fatal: true });
    let size = 0;
    let body = "";
    try {
        for (;;) {
            const { done, value } = await reader.read();
            if (done) break;
            size += value.byteLength;
            if (size > bodyLimit) {
                await reader.cancel();
                return { tooLarge: true };
            }
            body += decoder.decode(value, { stream: true });
        }
        return { value: JSON.parse(body + decoder.decode()) };
    } finally {
        reader.releaseLock();
    }
}

function operation(value) {
    if (!value || typeof value !== "object") return null;
    switch (value.action) {
        case "directory": return { action: "directory" };
        case "issue":
            return isUUID(value.establishmentID) && roles.has(value.role)
                ? { action: "issue", establishmentID: value.establishmentID, role: value.role } : null;
        case "revoke":
            return isUUID(value.establishmentID) && isUUID(value.invitationID)
                ? { action: "revoke", establishmentID: value.establishmentID, invitationID: value.invitationID } : null;
        case "redeem":
            return isUUID(value.code) ? { action: "redeem", code: value.code } : null;
        default: return null;
    }
}

export function createNativeTeamHandler({ verifySession, execute }) {
    return async (request) => {
        if (request.method !== "POST") return json(405, { error: "method_not_allowed" }, { Allow: "POST" });
        const authorization = request.headers.get("authorization");
        const token = authorization && authorization.length <= 8_200
            ? authorization.match(tokenPattern)?.[1] : null;
        if (!token) return json(401, { error: "authentication_required" });
        if (request.headers.get("content-type")?.split(";")[0].trim().toLowerCase() !== "application/json") {
            return json(415, { error: "json_required" });
        }

        let body;
        try {
            body = await readBody(request);
        } catch {
            return json(400, { error: "invalid_request" });
        }
        if (body.tooLarge) return json(413, { error: "request_too_large" });
        const command = operation(body.value);
        if (!command) return json(400, { error: "invalid_request" });

        try {
            const claims = await verifySession(token);
            if (!claims) return json(401, { error: "authentication_required" });
            return json(200, await execute(claims, command));
        } catch (error) {
            if (error?.code === "42501") return json(403, { error: "access_denied" });
            if (error?.code === "22023") return json(409, { error: "invitation_unavailable" });
            return json(503, { error: "service_unavailable" });
        }
    };
}
