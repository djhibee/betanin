# This is a fork

Forked from [`sentriz/betanin`](https://github.com/sentriz/betanin) at **v0.5.6**,
which is the version running on mochi.

## Why fork

Upstream is effectively dormant. Its author has moved to
[`wrtag`](https://github.com/sentriz/wrtag), and betanin's `master` has had one
commit since 2026-05-31 (a release chore). Between v0.5.6 and v0.6.3 — a span of
29 months — upstream landed 18 commits, of which 3 were substantive; the rest
were release chores, dependabot bumps, CI and README. `jobs/import_torrents.py`
has been touched 13 times in 7 years.

So the usual argument against forking (you inherit a rebase treadmill) does not
apply. There is no treadmill. What there is instead is a dependency file nobody
is maintaining, and two local patches that were being carried as bind mounts
over a container's `site-packages` — which is a worse way to own a change than a
commit is.

## What is different from upstream

Four commits on top of `v0.5.6`:

1. **`deps:`** — every dependency pinned. See below; this is the important one.
2. **`fix:`** — notification greenlet no longer touches ORM attributes outside
   the Flask app context. Upstream fixed this independently in `b3f652be`; when
   this fork rebases onto a 0.6.x base, drop ours in favour of theirs.
3. **`feat:`** — `server.beet_quiet` config key, to run `beet import -q`.
4. **`build:`** — base images digest-pinned, `soundfile` bundled, dependency
   install moved above the source copy.

## Security hardening

- **Console output is HTML-escaped.** Beets output (which echoes torrent and
  file names, and MusicBrainz metadata) used to be rendered as raw HTML.
- **Socket.IO requires a JWT and is same-origin only.** The web UI sends its
  token when connecting; connections without a valid token are refused, and
  cross-origin connections are rejected. Behind a reverse proxy that does not
  forward `X-Forwarded-Proto` / `X-Forwarded-Host`, list the origin(s) the UI is
  reached from explicitly (this replaces the same-origin check, so list all):

  ```toml
  [server]
  socket_allowed_origins = ["https://betanin.lan"]
  ```

- **The API key only works for `POST /api/torrents`.** That is the one call
  torrent client hooks make. Every other endpoint (beets config, notifications,
  directory listing, history, stdin) needs the web UI's JWT, so a leaked key can
  no longer rewrite the beets config into code execution.
- **Login hardening.** Username, password and API key are compared in constant
  time. After 5 failed logins from one IP, that IP gets `429` for 5 minutes
  (in memory, reset on restart; behind a reverse proxy every client shares the
  proxy's IP, so rate-limit there too). The `[frontend] password` in
  `config.toml` may now be a hash instead of plain text:

  ```sh
  docker exec -it betanin betanin-hash-password   # prompts for the password
  ```

  Paste the output (`scrypt:...`) as the password value. Plain text still works.

## The dependency pinning, and why it is the point

Upstream's `requirements-docker.txt` was almost entirely unconstrained:

```
beets @ https://github.com/beetbox/beets/archive/master.zip
beets-bpmanalyser @ https://github.com/adamjakab/BeetsPluginBpmAnalyser/archive/devel.zip
```

plus twelve PyPI packages with no version specifier at all.

That is not a theoretical problem:

- **The build was broken.** `BeetsPluginBpmAnalyser`'s `devel` branch has been
  deleted upstream. That URL is a hard 404, so the `pip install` layer fails and
  no image could be built at all. Note `docker compose up` builds when an image
  is merely *absent* — a `docker image prune -a` was enough to be left with no
  betanin.
- **`master.zip` is not even "master at build time".** The image running on
  mochi was built at 20:23Z on 2023-12-22, but the beets it contains is the tree
  at `296f01b`, which landed at 13:46Z — two later commits had already been
  merged by build time. GitHub's archive endpoint is CDN-cached, so what you get
  is whatever the cache had.
- **Building from source would have moved beets 1.6.1 → 2.13.1**, silently. That
  is one major and thirteen minor versions in the single component every match
  setting we have tuned actually targets.

Two of the pins are commits rather than versions, and have to be:

| package | pin | why not a version |
|---|---|---|
| `beets` | `296f01b775d3c48fa720d487e9887c074f3b3194` | Our 1.6.1 is a *master snapshot*, not the PyPI 1.6.1 release, which is older and different. |
| `beets-bpmanalyser` | `ed621feffba9e8d7b1154e230176144311355724` | 1.3.4 was never published to PyPI — that project's releases skip 1.3.3 → 1.4.0. |

Both commits were identified by extracting the running container's
`site-packages` and matching every installed file against upstream git trees by
blob hash. For beets that is 107 of 107 files byte-identical.

### Two files, not one

`requirements-docker.txt` pins what the Dockerfile installs by name.
`constraints.txt` pins **everything else** — betanin's own `pyproject.toml`
dependencies, which carry no version specifiers, and the entire transitive
closure beneath them.

The second file is not belt-and-braces. Building with only the first pinned was
tried, and the result had beets byte-for-byte identical to production while
sixty-odd other packages had moved, including:

```
jellyfish   1.0.3  -> 1.2.1     string distance; feeds beets match scores
mediafile   0.12.0 -> 0.17.0    beets' tag reader/writer
confuse     2.0.1  -> 2.2.1     beets' config parser
numpy       1.26.2 -> 2.4.6     major version
```

`jellyfish` is the one to understand. It computes how close a candidate release
is to what is on disk, which determines whether the match clears
`match.strong_rec_thresh` — which determines whether an album imports silently
or stops and asks a human. Pinning beets alone would have reproduced beets and
still changed which albums import.

`constraints.txt` is generated from the site-packages of the running container,
so it locks to a set known to work rather than to whatever resolves today.
`beets` and `beets-bpmanalyser` are deliberately absent from it: they install
from pinned commit URLs, and a version constraint cannot apply to a direct URL
requirement.

**Bump one thing at a time, deliberately, and read the beets changelog when you
bump beets.**

## Known upstream bug this fork has *not* fixed

`_right_exit_status()` maps a `None` exit status to `0`, and nothing ever calls
`proc.wait()`, so `proc.exitstatus` is always `None`. **betanin cannot report a
failed import.** Every job records `exit status 0` regardless of what beets did.

This matters more than it sounds: it means `quiet_fallback: skip` plus the
`skipfail` beets plugin produces jobs that look COMPLETED while having imported
nothing. Still true in upstream 0.6.3.

Fixing it is a real change in behaviour — a lot of currently-green history would
have been red — so it is deliberately not bundled in with the fork itself.

## Known cosmetic issue: an ignored traceback at every import

Every import console now opens with:

```
Exception ignored in: <function _after_fork at 0x...>
  ...
AssertionError: Thread.__init__() not called
```

It is harmless, it is not our code, and it is not a regression in betanin. It
is a consequence of the base image's Python moving 3.11.6 -> 3.11.12.

CPython added exactly one block to `threading._after_fork` between those
versions:

```python
if isinstance(thread, _DummyThread):
    thread.__class__ = _MainThread
    thread._name = 'MainThread'
    thread._daemonic = False
    thread._set_tstate_lock()
```

gevent registers its hub as a `_DummyThread`, and `_DummyThread` never runs
`Thread.__init__`, so `self._initialized` is False. The new code calls
`_set_tstate_lock()`, which reads `self.daemon`, which asserts on
`_initialized`. Every frame in the traceback is this block.

It fires in the forked child between `fork()` and `execv()` inside
`PtyProcessUnicode.spawn`. CPython prints it and continues; the child then
execs `beet` immediately, so nothing depends on the lock that failed to be set.
Imports complete normally with correct MusicBrainz matches and exit status 0.

If the noise ever becomes worth removing, the options are: pin the base to an
Alpine point release still shipping 3.11.6 (restores exact parity, at the cost
of an older base receiving fewer security fixes), or bump gevent, which is not
in beets' matching path and is therefore a low-risk pin to relax. Neither is
worth doing for cosmetics alone.

This is also the concrete example of what the Dockerfile comment means when it
says the OS layer reproduces forward but not backward.

## Moving to a 0.6.x base

Not done, and not a routine bump. The known work:

- Drop commit 2; upstream's `b3f652be` supersedes it.
- Commit 3 needs re-deriving: 0.6.x wraps the spawn in a `BoundedSemaphore` that
  restores the real `os.close` during `PtyProcessUnicode.spawn()`, because
  gevent's monkey-patched version makes spawn hang. Insert `-q` *inside* that
  block; do not replace the function.
- 0.6.x is alpine 3.23 / python 3.12, so any remaining `python3.11` paths move.
- Upstream dropped `py-pip` for `uv`.
- **beets 2.x config migration, which is the dangerous part:**
  - `match.distance_weights.source` is renamed to `data_source`. A config
    setting `source: 0.0` goes silently inert and the built-in `2.0` applies.
  - beets 2.x moved MusicBrainz out of core into a plugin that lives in the
    *default* `plugins:` list. A config that sets `plugins:` explicitly
    **replaces** that default rather than merging, and the compatibility shim
    keys off `musicbrainz.enabled`, which our configs do not set — so
    `mb_enabled` is `None`, neither branch of the shim fires, and MusicBrainz
    never loads. The symptom is zero candidates on every album, therefore
    `quiet_fallback` on every album, therefore a **silent 100% skip rate**.
    The fix is to add `musicbrainz` to `plugins:`. Nothing warns you.
  - `mbretry.py` does `import musicbrainzngs`; beets 2.x dropped that dependency
    entirely. The plugin will fail to import and its DNS-retry protection is
    gone.
  - beets 2.x ships its own `beetsplug/autobpm.py`. Ours still wins via
    `pluginpath`, but it is now shadowing a bundled plugin rather than supplying
    a missing one.

Do that on a branch, and verify MusicBrainz actually returns candidates before
pointing anything real at it.
