## Summary

<!-- What this changes and why. A sentence or two is fine. -->

Closes #

<!--
Non-trivial changes should start from an issue so the goal and how to verify it are
agreed up front — see "Issue, branch and worktree workflow" in CLAUDE.md. A typo or
one-line fix doesn't need one; just delete the line above.
-->

## Type of change

- [ ] Bug fix
- [ ] New feature
- [ ] Refactor or internal cleanup
- [ ] Documentation
- [ ] Build, CI or release tooling

## How this was verified

<!--
The commands you ran and the cases you covered, including anything checked by hand.
"Tests pass" on its own doesn't say much — what would have failed before?
-->

```bash
xcodebuild -project SimulatorManager.xcodeproj -scheme SimulatorManager test
```

## Screenshots or recording

<!--
Required for anything that changes the menu bar UI — the menu can't be reviewed from a
diff. Before and after if you can manage it. Delete this section for non-UI changes.
-->

## Checklist

- [ ] Targets `develop`, from a branch named after its issue
- [ ] Tests pass, and new behaviour is covered (Swift Testing — `@Suite` / `@Test` / `#expect`)
- [ ] Keeps the observation split: view models are `@MainActor @Observable`, the model and service layer stays `ObservableObject` + Combine
- [ ] Discovery, monitoring and filesystem logic lives in services, not views
- [ ] Missing files and decode failures are handled defensively and logged with `os_log` rather than crashing
- [ ] New preferences go through `Settings`; CoreSimulator paths go through `SimulatorPaths`
- [ ] App sandbox is still disabled — it has to be, for the app to reach `~/Library/Developer/CoreSimulator`

<!-- Conventions and the reasoning behind them: CLAUDE.md and SimulatorManagerTests/README.md -->

## Notes for reviewers

<!-- Trade-offs, follow-ups, anything deliberately left out of scope. -->
