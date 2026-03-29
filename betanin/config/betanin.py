# standard library
import os
import tomlib
import hmac
from contextlib import contextmanager

# 3rd party
import tomli_w
from werkzeug.security import check_password_hash
from werkzeug.security import generate_password_hash

# betanin
from betanin import paths


DEFAULT_CONFIG = {
    "frontend": {"username": "", "password": ""},
    "notifications": {
        "services": {},
        "strings": {
            "body": "@ $time. view/use the console at http://127.0.0.1:9393/$console_path",
            "title": "[betanin] torrent `$name` $status",
        },
    },
    "clients": {"api_key": ""},
    "server": {"num_parallel_jobs": 1, "beet_quiet": False},
}


def gen_api_key(length=16):
    return os.urandom(length).hex()


def read():
    with open(paths.CONFIG_PATH, "rb") as file:
        return tomllib.load(file)


def write(config):
    with open(paths.CONFIG_PATH, "wb") as file:
        tomli_w.dump(config, file)


@contextmanager
def mutate():
    config = read()
    yield config
    write(config)


# prefixes of hashes produced by werkzeug's generate_password_hash
_PASSWORD_HASH_PREFIXES = ("scrypt:", "pbkdf2:")


def _const_eq(a, b):
    return hmac.compare_digest(str(a).encode(), str(b).encode())


def hash_password(password):
    return generate_password_hash(password)


def password_is_hashed(stored):
    return str(stored).startswith(_PASSWORD_HASH_PREFIXES)


def _password_correct(stored, password):
    if password_is_hashed(stored):
        return check_password_hash(stored, password)
    return _const_eq(stored, password)


def find_creds_correct(conf, username, password):
    # evaluate both so the response time doesn't reveal which one was wrong
    username_ok = _const_eq(conf["frontend"]["username"], username)
    password_ok = _password_correct(conf["frontend"]["password"], password)
    return username_ok and password_ok


def find_api_key(conf):
    return conf["clients"]["api_key"]


def find_api_key_correct(conf, api_key):
    return _const_eq(conf["clients"]["api_key"], api_key)


def find_num_parallel_jobs(conf):
    return conf.get("server", {}).get("num_parallel_jobs", 1)


def find_beet_quiet(conf):
    return conf.get("server", {}).get("beet_quiet", False)


def find_socket_allowed_origins(conf):
    return conf.get("server", {}).get("socket_allowed_origins", [])


def find_import_roots(conf):
    return conf.get("server", {}).get("import_roots", [])
