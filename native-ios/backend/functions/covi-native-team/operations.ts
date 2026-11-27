import type postgres from "npm:postgres@3.4.8";

type Claims = { sub: string; session_id: string };
type Operation =
    | { action: "directory" }
    | { action: "issue"; establishmentID: string; role: string }
    | { action: "revoke"; establishmentID: string; invitationID: string }
    | { action: "redeem"; code: string };

export function teamOperations(database: postgres.Sql) {
    return (claims: Claims, command: Operation) => {
        // A transaction releases both the restricted role and request claims.
        return database.begin(async (tx) => {
            // PostgreSQL receives constant statements and binds values separately.
            await tx.unsafe("set local role covi_native_team_gateway");
            await tx.unsafe("set local statement_timeout = '5s'");
            await tx.unsafe("select pg_catalog.set_config('request.jwt.claims', $1, true)", [JSON.stringify(claims)]);
            switch (command.action) {
                case "directory":
                    return { establishments: await tx.unsafe("select * from covi_native.list_active_establishment_access()") };
                case "issue": {
                    const [invitation] = await tx.unsafe(
                        "select * from covi_native.issue_team_invitation($1::uuid, $2)",
                        [command.establishmentID, command.role],
                    );
                    return { invitation };
                }
                case "revoke": {
                    const [result] = await tx.unsafe<{ revoked: boolean }[]>(
                        "select covi_native.revoke_team_invitation($1::uuid, $2::uuid) as revoked",
                        [command.establishmentID, command.invitationID],
                    );
                    return { revoked: result.revoked };
                }
                case "redeem": {
                    const [membership] = await tx.unsafe(
                        "select * from covi_native.redeem_team_invitation($1::uuid)", [command.code],
                    );
                    return { membership };
                }
            }
        });
    };
}
