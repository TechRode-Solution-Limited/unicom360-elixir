# Contributing

Thanks for helping. Issues and pull requests are welcome at
<https://github.com/TechRode-Solution-Limited/unicom360-elixir>. Report security problems
privately instead: see [SECURITY.md](SECURITY.md).

Two rules apply to everything in this repository (code, comments, docs, commit messages): never
write the em dash character, and add no AI attribution lines to commits or pull requests.

## Set up

Elixir 1.19.4 on Erlang/OTP 28.2 (`.tool-versions` pins them for asdf). The library supports Elixir
1.15 and OTP 25 and up, but the formatter's output differs between Elixir versions, so format with
this one.

```sh
mix deps.get
```

`mix.lock` is committed on purpose, so every checkout and CI run tests the same dependencies. It is
not published: Hex resolves a user's dependencies from the requirements in `mix.exs`.

## Checks

CI runs all of these; run them before you push:

```sh
mix format --check-formatted
mix compile --warnings-as-errors
MIX_ENV=test mix compile --warnings-as-errors   # the library and the examples
mix credo --strict
mix dialyzer
mix docs --warnings-as-errors
mix test                                        # the unit tests and the whole conformance suite
grep -rn --exclude-dir=.git --exclude-dir=deps --exclude-dir=_build --exclude-dir=doc --exclude-dir=priv $'\xe2\x80\x94' . && echo "em dash found"
```

### Other Elixir versions

CI tests Elixir 1.15 on OTP 25, 1.17 on OTP 27, and 1.19.4 on OTP 28.2. To run one locally without
installing it, use its Docker image (the source is copied, so the container never writes to your
checkout):

```sh
docker run --rm -v "$PWD":/src:ro hexpm/elixir:1.15.8-erlang-25.3.2.21-debian-bookworm-20261027-slim sh -c '
  cp -r /src /work && cd /work && rm -rf _build deps priv/plts doc
  export MIX_ENV=test LANG=C.UTF-8 LC_ALL=C.UTF-8
  mix local.hex --force && mix local.rebar --force && mix deps.get
  mix compile --warnings-as-errors && mix test'
```

### Other Req versions

`mix.exs` allows every Req from 0.5, whose adapter API changed in 0.7. CI also runs the suite on Req
0.5.0. Locally, in a throwaway copy, change the requirement to `{:req, "== 0.5.0"}`, delete
`mix.lock`, and run `mix deps.get` and `mix test`. The SDK's own code must not depend on anything
newer than 0.5.0.

### The contract test

`test/unicom360/contract_test.exs` sends every call in `requests.json` through the real transport to
a [Prism](https://stoplight.io/open-source/prism) mock of `openapi.yaml`, and fails on any response
that is not a 2xx or that has an `sl-violations` header. It is not part of the default run:

```sh
docker run --rm -p 4014:4010 -v /path/to/unicom360-openapi:/spec:ro stoplight/prism:5 \
  mock --multiprocess=false --errors -h 0.0.0.0 /spec/openapi.yaml
UNICOM360_CONTRACT_BASE_URL=http://127.0.0.1:4014 mix test --only contract
```

(`--multiprocess=false` avoids a crash of the Prism 5 image at start-up.) When the tests run in a
container themselves, start it with `--network container:<prism>` and use
`http://127.0.0.1:4010`: `host.docker.internal` is correctly refused by the plain-http rule.

## The conformance fixtures

`test/fixtures/conformance/` is a vendored copy of `conformance/` from
[unicom360-openapi](https://github.com/TechRode-Solution-Limited/unicom360-openapi), pinned by the
tag and sha256 in `test/fixtures/conformance/VERSION`. Never edit it by hand: the suite recomputes
the sha256 and fails on any change. To move to a new contract version:

```sh
cd ../unicom360-openapi && git checkout vX.Y.Z
scripts/sync-conformance ../unicom360-elixir/test/fixtures/conformance
scripts/sync-conformance --check ../unicom360-elixir/test/fixtures/conformance
```

Then update `@contract_version` in `lib/unicom360.ex`, make the suite pass, update the README's
"targets" line and Known differences, and commit the fixtures with the code. The fixtures never ship
in the Hex package: `mix.exs` lists the package's files explicitly, and CI checks the unpacked
package.

Every vector of every fixture file runs through the public API, one test per vector
(`test/unicom360/conformance/`, with the shared harness in `test/support/conformance.ex`). A vector
the harness does not understand fails, it is never skipped. When the contract adds a rule, extend the
harness rather than filtering vectors.

## Examples

`examples/` holds one module per operation, plus a Phoenix controller and a plain Plug webhook
receiver. They compile with the tests (`elixirc_paths(:test)`) and
`test/unicom360/examples_test.exs` runs them against canned responses, so they cannot go stale. Run
one for real (every accepted send is real and billed) with:

```sh
UNICOM360_API_KEY=... MIX_ENV=test mix run -e "Unicom360.Examples.BalanceGet.main()"
```

## Releasing

1. Update `@version` in `mix.exs` and `lib/unicom360.ex`.
2. In `CHANGELOG.md`, give the version's section today's date (`## [X.Y.Z] - YYYY-MM-DD`) and add the
   link at the bottom. The release refuses an undated heading.
3. Commit, then tag and push the tag:

   ```sh
   git tag vX.Y.Z
   git push origin vX.Y.Z
   ```

4. `release.yml` checks that the tag matches `mix.exs` and `Unicom360.version/0` and that the
   CHANGELOG has the dated section, runs every check on the whole version matrix, runs
   `mix hex.publish --yes` with the `HEX_API_KEY` repository secret, and creates the GitHub Release
   with the CHANGELOG section as its notes.

One-time setup: on [hex.pm](https://hex.pm), generate an API key with `mix hex.user key generate`
(or in your dashboard), and add it to this repository's secrets as `HEX_API_KEY`.

### Publishing without GitHub Actions

When Actions is unavailable, publish from a clean checkout of the tag:

```sh
git checkout vX.Y.Z
mix deps.get
mix hex.user auth
mix hex.publish
```

Then create the GitHub Release by hand from the CHANGELOG section.
