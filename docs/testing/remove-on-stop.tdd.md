# `remove-on-stop` TDD evidence

Date: 2026-08-02
Status: **Local GREEN; pinned Xcode 16.4 CI pending an authorized push**

## Source and scope

This change implements the `remove-on-stop` step in the
[ordered change plan](../architecture/quill-v2-architecture.md#ordered-change-plan)
under the repository's
[RED → GREEN rules](../architecture/governing-rules.md#change-and-verification-rules).
The separately supplied Phase 2 handoff was treated as planning input and
checked against the repository before use.

The change removes the configuration-driven command interpreter consumer,
warns about a legacy `on_stop` key without rendering its value, and enforces
the removal in CI. It does not change recording lifecycle, capture, config
snapshots, LaunchAgent behavior, model provisioning, signing, or storage.

## User journeys

- As a user with a legacy `on_stop` setting, I need a visible and actionable
  warning so I know the setting is ignored and must be removed.
- As a user without the legacy key, I need startup to remain free of migration
  notices.
- As a reporter, I need recording and transcription behavior to remain intact
  without a privileged background process executing config-supplied commands.
- As a maintainer, I need CI to reject reintroduced hook identifiers, command
  interpreters, and unreviewed subprocess sites.

## RED → GREEN report

### Hook-removal and migration contract

- RED checkpoint: `dc9385b test: add remove-on-stop security contracts`.
- Command: `ruby scripts/test-remove-on-stop.rb`.
- RED result: **7 runs, 32 assertions, 2 intended failures**. The runnable
  failures identified the absent actionable migration path and the existing
  `Config.onStop()`, `runHook(for:)`, `/bin/sh`, and unreviewed coordinator
  `Process` site.
- A contemporaneous local `swift test --filter ConfigMigrationTests` attempt
  stopped before the test target because this host's default Command Line
  Tools setup could not load the Swift Testing framework. That infrastructure
  failure was not counted as RED.
- GREEN checkpoint: `51e13f0 fix: retire on_stop shell hook`.
- GREEN result: the same Ruby contract passed with **7 runs, 45 assertions**;
  the standalone validator also passed.

### Exact subprocess allowlist

- RED checkpoint:
  `eb909df test: reproduce reviewed process allowlist bypass`.
- Command: `ruby scripts/test-remove-on-stop.rb`.
- RED result: **8 runs, 46 assertions, 1 intended failure**. A second
  executable inserted into an otherwise reviewed `Process` file bypassed the
  initial presence-only allowlist.
- GREEN checkpoint: `c2ae1dd fix: enforce exact subprocess allowlist`.
- GREEN result: **8 runs, 48 assertions, 0 failures**. Every `Process()` in a
  reviewed file must now have a matching literal executable assignment, and
  every assigned executable must equal that site's approved path.

### Once-per-launch reporting

- RED checkpoint:
  `b2735a5 test: require once-per-launch migration reporting`.
- Command: local Swift Testing framework/rpath equivalent of
  `swift test --filter ConfigMigrationTests`.
- RED result: the Swift compiler reached both new test calls and failed
  because `reportConfigMigrationNotices` did not exist. This was an intended
  compile-time API-boundary RED.
- GREEN checkpoint:
  `a7b339d refactor: isolate migration notice reporting`.
- GREEN result: **5 tests in `ConfigMigrationTests` passed**. A nonempty notice
  list emits exactly one stderr warning and one notification per notice; an
  empty list emits neither.

### Adversarial review remediation

- RED checkpoint:
  `348ea26 test: add adversarial Phase 2 regressions`.
- Commands: `ruby scripts/test-remove-on-stop.rb` and the local-framework
  equivalent of `swift test --filter ConfigMigrationTests`.
- RED result: the Ruby corpus reported **12 runs, 61 assertions, 4 intended
  failures** for `Process ()`, `NSTask`, C launch primitives, reviewed-file
  reassignment, and POSIX-locale UTF-8 handling. Swift compilation reached all
  four file-backed cases and failed only because the injectable config URL API
  did not exist.
- GREEN checkpoint:
  `b581624 fix: close Phase 2 adversarial gaps`.
- GREEN result: **12 Ruby runs, 81 assertions** in both the default and POSIX
  locales; **9 tests in `ConfigMigrationTests` passed**; the standalone
  validator passed in both locales.
- A fresh adversarial pass then found that taking a launch function as a value
  could evade call-shaped matching. RED checkpoint
  `5a87ee6 test: reject aliased launch primitives` reproduced the bypass;
  GREEN checkpoint `74f0edb fix: reject aliased launch primitives` rejects
  aliased `NSTask`, `posix_spawn`, `system`, `popen`, `exec*`, and dynamic-loader
  symbols. The final corpus passes with **13 runs, 105 assertions** in both
  locales.

## Implementation report

- `Config.swift` removes `Config.onStop()`, keeps unrelated accessors intact,
  and adds a pure migration detector. Key presence triggers one sanitized
  notice regardless of value type; the value is never interpolated.
- `Quill.swift` calls the detector once in the application startup path and
  reports each notice through stderr and the existing macOS notification
  boundary.
- `TranscriptionCoordinator.swift` removes both hook call sites and the
  `/bin/sh -c` consumer. Disabled transcription now returns without launching
  anything; successful transcription still writes output and notifies.
- `README.md` removes the active hook example and documents the ignored-key
  migration.
- `validate-no-shell-hook.rb` reads source as validated UTF-8 and rejects
  retired identifiers, direct or environment-selected shell interpreters,
  unreviewed `Process` references, `NSTask`, POSIX/C launch primitives,
  primitive aliases, dynamic executable assignments, and extra executables in
  reviewed files.
- `Config.migrationNotices(at:writeWarning:)` exercises the same file loader as
  startup with an injected URL and warning sink. Missing, legacy, unrelated,
  and malformed files are covered without touching the user's config.
- CI runs both the validator's adversarial contract suite and the standalone
  repository validation before Swift tests.

The validator deliberately allows only the existing argument-vector launches
in `Sources/quill/Notify.swift` (`/usr/bin/osascript`) and
`Sources/quill/Install.swift` (`/bin/launchctl`). Adding or changing a
subprocess requires an explicit validator review.

## Test specification

| Guarantee | Evidence | Type | Result |
|---|---|---|---|
| A populated legacy key produces one actionable warning without exposing its command | `ConfigMigrationTests.legacyOnStopKeyProducesAnActionableNoticeWithoutLeakingItsValue` | Swift unit | PASS |
| Empty, numeric, and null legacy values still warn exactly once | `ConfigMigrationTests.anyLegacyOnStopValueProducesExactlyOneNotice` | Swift boundary unit | PASS |
| Config without `on_stop` produces no migration notice | `ConfigMigrationTests.configWithoutLegacyKeyProducesNoMigrationNotice` | Swift negative unit | PASS |
| Inspecting migration state does not remove unrelated config values | legacy-key Swift unit fixture | Swift regression unit | PASS |
| One notice reaches stderr and notification exactly once | `ConfigMigrationTests.reportingEmitsEachNoticeOnceThroughBothChannels` | Swift interaction unit | PASS |
| Empty notice input has no reporting side effects | `ConfigMigrationTests.reportingNoNoticesEmitsNothing` | Swift negative unit | PASS |
| Missing, legacy, unrelated, and malformed config files use the expected migration/warning behavior | file-backed temporary config fixtures | Swift filesystem integration | PASS |
| Product source has no retired consumer, command interpreter, or unreviewed launch primitive | current-tree remove-on-stop contract plus standalone validator | static integration | PASS |
| Alternate direct and environment-selected interpreters are rejected | temporary adversarial fixtures | negative integration | PASS |
| Whitespace, constructed paths, `NSTask`, POSIX/C APIs, and aliased launch symbols are rejected | syntactically valid Swift fixture corpus | negative integration | PASS |
| A second executable cannot hide inside a reviewed process file | reviewed-site bypass fixture | negative integration | PASS |
| A reviewed process cannot be reassigned a dynamic executable | reviewed-site reassignment fixture | negative integration | PASS |
| Existing `osascript` and `launchctl` argument-vector sites remain allowed | reviewed process fixture | compatibility contract | PASS |
| Both security scripts work with `LANG=C LC_ALL=C` | explicit POSIX-locale CI and local runs | environment compatibility | PASS |
| CI invokes both remove-on-stop checks | workflow contract | CI contract | PASS |
| Existing config, transcript, clock, metadata, and segmentation tests remain green | complete Swift package suite | regression | PASS — local equivalent |

## Verification and coverage

Final local results:

- `ruby scripts/test-architecture.rb`: **11 runs, 59 assertions, PASS**.
- `ruby scripts/validate-architecture.rb`: **PASS**.
- `ruby scripts/test-remove-on-stop.rb`: **13 runs, 105 assertions, PASS** in
  both the default locale and `LANG=C LC_ALL=C`.
- `ruby scripts/validate-no-shell-hook.rb`: **PASS** in both locales.
- local-framework equivalent of `swift test`: **24 tests in 6 suites, PASS**.
- local-framework equivalent of `swift test --enable-code-coverage`:
  **24 tests in 6 suites, PASS**.
- `swiftc -frontend -parse` for the changed Swift production and test files:
  **PASS**.
- `git diff --check`: **PASS**.
- `gitleaks git --log-opts='285fabc..HEAD'`: **12 commits scanned, no leaks**.

`llvm-cov show` reports every executable line in the new pure
`Config.migrationNotices(in:)` decision, the injected file-backed migration
loader, and the `reportConfigMigrationNotices` reporting loop executed.
`Config.swift` as a whole reports 48.65% line coverage and `Quill.swift`
reports 7.22%; those file totals include legacy filesystem, CLI, AppKit, and
process-lifecycle paths outside this phase. No repository-wide 80% claim is
made. The behavior introduced for this phase is fully line-covered.

The local command requires Command Line Tools-only framework, interop-library,
module-cache, and sandbox flags. They are host accommodations, not product or
CI settings. The committed CI lane continues to run plain `swift test` on
macOS 15 with Xcode 16.4 / Swift 6.1.

## Security scope and known gaps

The relevant unsafe-execution check is fixed and regression-tested against
direct calls, spelling/whitespace changes, dynamic executable assignments, and
common function-alias indirection. It is a conservative source gate, not a
general proof against every possible future macOS execution API; adding a new
launch mechanism still requires validator review. Web-route
authorization, browser secrets, database row policies, JWT verification,
CSRF, SSRF, and server caching are not applicable to this local macOS
executable. Broader dependency, signing, sandbox, TCC, LaunchAgent, model, and
secret-history reviews remain assigned to their ordered changes and were not
expanded into Phase 2.

Tests inject warning and notification sinks; they do not display a real macOS
notification. The existing notification process site remains statically
allowlisted. Pinned branch-tip CI is the remaining Phase 2 completion gate and
cannot be recorded until a push is explicitly authorized and its run finishes.
