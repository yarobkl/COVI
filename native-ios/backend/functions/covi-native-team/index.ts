import postgres from "npm:postgres@3.4.8";
import { createNativeTeamHandler, supabaseSessionVerifier } from "./handler.mjs";
import { teamOperations } from "./operations.ts";

const projectURL = Deno.env.get("SUPABASE_URL");
const publishableKey = Deno.env.get("COVI_TEAM_PUBLISHABLE_KEY");
const databaseURL = Deno.env.get("COVI_TEAM_DATABASE_URL");
const rootCA = Deno.env.get("COVI_TEAM_DATABASE_CA");
if (!projectURL || new URL(projectURL).protocol !== "https:" || !publishableKey || !databaseURL) {
    throw new Error("Missing native team gateway configuration");
}

const database = postgres(databaseURL, {
    max: 1,
    prepare: false,
    connect_timeout: 5,
    idle_timeout: 20,
    ssl: rootCA ? { ca: rootCA, rejectUnauthorized: true } : { rejectUnauthorized: true },
});

Deno.serve(createNativeTeamHandler({
    verifySession: supabaseSessionVerifier(projectURL, publishableKey),
    execute: teamOperations(database),
}));
