# Spinel test proof of concept

Run the existing RawSource tests under both Ruby and Spinel:

```sh
SPINEL=/path/to/spinel ruby script/test_spinel.rb
# or
SPINEL=/path/to/spinel rake test:spinel
```

Use Ruby 3.0 or newer for the host runner (on a Mise-managed machine,
`mise exec ruby -- ruby script/test_spinel.rb`). `SPINEL` defaults to `spinel`
on PATH. It is an executable path, not a shell command with flags.

Normal `rake test` still uses Minitest and SimpleCov. No library code or test
methods are changed. `shared_helper.rb` holds helpers used by both runners.

The host Ruby process discovers test methods. For each method it writes a
copy of its test file under the ignored `tmp/spinel-tests/` directory,
replacing only the `test_helper` require with the assertion adapter and shared
helpers, then appends explicit construction/setup/test/teardown calls.
Each case gets a fresh instance and executable. The generated program runs
under Ruby and Spinel; both must exit successfully and their captured output must match.
Compile errors, assertion failures, missing tools and timeouts fail the run.
Generated Ruby, executables and per-case logs are retained for debugging.

Default coverage is the eight tests in `test/test_raw_source.rb`. You can
supply other files, but this is intentionally a first proof of concept:

```sh
SPINEL=/path/to/spinel ruby script/test_spinel.rb test/test_raw_source.rb
```

The adapter currently implements only `assert`, `assert_equal`, and
`assert_respond_to`, plus setup/teardown hooks. It does not implement the full
Minitest lifecycle, assertion counts, plugins, or skips. Unsupported assertions
must fail rather than silently pass. Tests relying on their own `__dir__` or
additional relative requires need adaptation before copying them this way;
the shared fixture helper retains its original location.

Validated with Spinel `2026.09.12+1839` (`7f08abd9`) on macOS ARM64. This runner
checks existing assertions; it does not by itself prove byte-for-byte parity
for values that a test never prints or compares.

## First run

On the compiler revision above: 7 pass, 1 fails. The failure is
`TestRawSource#test_pixel_responds_to_rgb`: Spinel raises
`undefined method 'respond_to?' for an instance of PureJPEG::Source::Pixel`
inside the assertion adapter. It remains a failure (exit status 1), not a skip
or weakened assertion. The encode/decode test passes. The normal Ruby suite
passes all 103 tests and 6,302,250 assertions.

The adapter's false/unequal assertion paths were also checked with
`spinel diff`; both raise the expected assertion exception, matching Ruby.
