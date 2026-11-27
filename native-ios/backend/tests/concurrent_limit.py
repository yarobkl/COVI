"""Real PostgreSQL connections; disposable CI database only, no hosted secrets."""
import subprocess
import uuid


def query(sql, check=True):
    return subprocess.run(['psql', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1', '-c', sql],
                          text=True, capture_output=True, check=check, timeout=20)


owner = uuid.uuid4()
shops = [uuid.uuid4() for _ in range(4)]
query(f"insert into auth.users(id) values ('{owner}'); "
      f"insert into covi_native.establishments(id, owner_id) values "
      f"('{shops[0]}', '{owner}'), ('{shops[1]}', '{owner}');")
first = subprocess.Popen(['psql', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1'],
                         stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                         stderr=subprocess.PIPE, text=True)
try:
    first.stdin.write(f"begin; insert into covi_native.establishments(id, owner_id) "
                      f"values ('{shops[2]}', '{owner}');\n\\echo THIRD_INSERTED\n"
                      "select pg_sleep(2); commit;\n")
    first.stdin.close()
    # The third insert is uncommitted. The second connection must wait for the
    # per-owner lock and then reject the fourth, rather than count only two.
    assert first.stdout.readline().strip() == 'THIRD_INSERTED'
    second = query(f"insert into covi_native.establishments(id, owner_id) "
                   f"values ('{shops[3]}', '{owner}');", check=False)
    assert first.wait(timeout=20) == 0, first.stderr.read()
    assert second.returncode != 0, 'Concurrent fourth establishment accepted'
    assert 'Maximum three active establishments' in second.stderr, second.stderr
    count = query(f"select count(*) from covi_native.establishments "
                  f"where owner_id = '{owner}' and archived_at is null;").stdout.strip()
    assert count == '3', count
    print('PASS: concurrent third/fourth establishment, exactly three active')
finally:
    if first.poll() is None:
        first.kill()
        first.wait()
    query(f"delete from covi_native.establishments where owner_id = '{owner}'; "
          f"delete from auth.users where id = '{owner}';")


def check_concurrent_invitation():
    issuer, first_member, second_member = (uuid.uuid4() for _ in range(3))
    issuer_session, first_session, second_session = (uuid.uuid4() for _ in range(3))
    shop = uuid.uuid4()
    query(f"insert into auth.users(id) values ('{issuer}'), ('{first_member}'), ('{second_member}'); "
          f"insert into auth.sessions(id, user_id) values "
          f"('{issuer_session}', '{issuer}'), ('{first_session}', '{first_member}'), "
          f"('{second_session}', '{second_member}'); "
          f"insert into covi_native.establishments(id, owner_id) values ('{shop}', '{issuer}');")

    def claims(account, session):
        return ("select set_config('request.jwt.claims', "
                f"jsonb_build_object('sub', '{account}', 'session_id', '{session}')::text, true);")

    code = uuid.UUID(query(claims(issuer, issuer_session) +
                           f" select code from covi_native.issue_team_invitation('{shop}', 'cashier');"
                           ).stdout.splitlines()[-1])
    first = subprocess.Popen(['psql', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1'],
                             stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                             stderr=subprocess.PIPE, text=True)
    try:
        first.stdin.write("begin; " + claims(first_member, first_session) +
                          f" select * from covi_native.redeem_team_invitation('{code}');\n"
                          "\\echo FIRST_REDEEMED\nselect pg_sleep(2); commit;\n")
        first.stdin.close()
        for line in first.stdout:
            if line.strip() == 'FIRST_REDEEMED':
                break
        else:
            raise AssertionError(first.stderr.read())
        second = query(claims(second_member, second_session) +
                       f" select * from covi_native.redeem_team_invitation('{code}');", check=False)
        assert first.wait(timeout=20) == 0, first.stderr.read()
        assert second.returncode != 0, 'The same invitation was redeemed twice'
        assert 'Invitation unavailable' in second.stderr, second.stderr
        members = query(f"select account_id from covi_native.memberships "
                        f"where establishment_id = '{shop}' and revoked_at is null;").stdout.strip()
        assert members == str(first_member), members
        print('PASS: concurrent invitation redemption, exactly one membership')
    finally:
        if first.poll() is None:
            first.kill()
            first.wait()


check_concurrent_invitation()
