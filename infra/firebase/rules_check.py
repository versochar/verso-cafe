#!/usr/bin/env python3
"""Firestore güvenlik kurallarını (firestore.rules) emülatörde uzaktan doğrular.

Kurallar sunucuda çalışır; bu betik istemci kodundan bağımsız olarak REST ile
yazma denemeleri yapar. Firebase Emulator Suite açık olmalıdır:

    cd infra/firebase && firebase emulators:start --project demo-verso-cafe

Kullanım (hesaplar emülatörde kayıtlı olmalı — kayıt UI'dan yapılır):

    python3 infra/firebase/rules_check.py [host_adı host_parolası [uye_adı uye_parolası]]

Betik host'u yetkili, ikinci hesabı deney faresi olarak kullanır: mod/üye
geçişi yapar, yazma denemeleri gönderir ve sonunda rolleri eski hâline getirir.
"""
import json
import sys
import urllib.error
import urllib.request

AUTH_HOST = "127.0.0.1:9099"
FS_HOST = "127.0.0.1:8188"
PROJECT = "demo-verso-cafe"
AUTH = f"http://{AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=fake"
FS = f"http://{FS_HOST}/v1/projects/{PROJECT}/databases/(default)/documents"


def call(url, body=None, token=None, method=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data,
                                 method=method or ("POST" if data else "GET"),
                                 headers={"Content-Type": "application/json"})
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(req) as r:
            return r.status, json.load(r)
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b"{}")


def sign_in(name, password):
    st, d = call(AUTH, {"email": f"{name}@hesap.verso.app", "password": password})
    if st != 200:
        sys.exit(f"giriş başarısız ({name}): {d.get('error', d)}")
    return d["idToken"], d["localId"]


def create(token, coll, doc_id, fields):
    return call(f"{FS}/{coll}?documentId={doc_id}", {"fields": fields}, token)


def update(token, coll, doc_id, fields, mask):
    """Yalnız mask'elenen alanları günceller (belgenin anahtar alanına dokunmaz)."""
    q = "&".join(f"updateMask.fieldPaths={f}" for f in mask)
    return call(f"{FS}/{coll}/{doc_id}?{q}", {"fields": fields}, token, method="PATCH")


def main():
    a = sys.argv[1:]
    host_name, host_pass = (a[0], a[1]) if len(a) >= 2 else ("hosthesap", "123456")
    other_name, other_pass = (a[2], a[3]) if len(a) >= 4 else ("misafir", "123456")

    results = []

    def check(name, ok, detail=""):
        results.append((name, ok))
        print(("PASS " if ok else "FAIL ") + name + (f"  [{detail}]" if detail else ""))

    host_tok, host_uid = sign_in(host_name, host_pass)
    other_tok, other_uid = sign_in(other_name, other_pass)
    before = call(f"{FS}/users/{other_uid}", token=host_tok)[1] \
        .get("fields", {}).get("role", {}).get("stringValue", "user")

    # 1) Yetkili (host) duyuru yazabilir.
    st, d = create(host_tok, "announcements", "rulestest-h", {
        "title": {"stringValue": "host-yazdi"}, "body": {"stringValue": ""},
        "authorUid": {"stringValue": host_uid}, "authorName": {"stringValue": host_name}})
    check("host duyuru yazabilir", st == 200, d.get("error", {}).get("status", ""))

    # 2) Host, ikinci hesabı mod yapabilir (istemcinin update yolu).
    st, d = update(host_tok, "users", other_uid, {"role": {"stringValue": "mod"}}, ["role"])
    check("host mod atayabilir", st == 200, d.get("error", {}).get("status", ""))

    # 3) Mod duyuru yazabilir.
    st, d = create(other_tok, "announcements", "rulestest-m", {
        "title": {"stringValue": "mod-yazdi"}, "body": {"stringValue": ""},
        "authorUid": {"stringValue": other_uid}, "authorName": {"stringValue": other_name}})
    check("mod duyuru yazabilir", st == 200, d.get("error", {}).get("status", ""))

    # 4) Üyeye indirilince yazamaz.
    st, _ = update(host_tok, "users", other_uid, {"role": {"stringValue": "user"}}, ["role"])
    st, d = create(other_tok, "announcements", "rulestest-u", {
        "title": {"stringValue": "uye-yazdi"}, "body": {"stringValue": ""},
        "authorUid": {"stringValue": other_uid}, "authorName": {"stringValue": other_name}})
    check("sıradan üye duyuru yazamaz", st == 403, d.get("error", {}).get("status", ""))

    # 5) Kendi rolünü yükseltemez (ayrıcalık kaçırma).
    st, d = update(other_tok, "users", other_uid, {"role": {"stringValue": "host"}}, ["role"])
    check("kendi rolünü host yapamaz", st == 403, d.get("error", {}).get("status", ""))

    # 6) Başka birinin belgesini değiştiremez.
    st, d = update(other_tok, "users", host_uid, {"username": {"stringValue": "ele-gecirdim"}},
                   ["username"])
    check("başkasının belgesini değiştiremez", st == 403, d.get("error", {}).get("status", ""))

    # 7) Anonim okuma yapamaz.
    st, d = call(f"{FS}/users")
    check("token'sız okuma yapamaz", st in (401, 403), d.get("error", {}).get("status", ""))

    # Eski hâline döndür + temizlik.
    update(host_tok, "users", other_uid, {"role": {"stringValue": before}}, ["role"])
    for doc in ("rulestest-h", "rulestest-m", "rulestest-u"):
        call(f"{FS}/announcements/{doc}", token=host_tok, method="DELETE")

    fails = [n for n, ok in results if not ok]
    print("\n" + ("TÜMÜ GEÇTİ" if not fails else f"{len(fails)} BAŞARISIZ: {fails}"))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
