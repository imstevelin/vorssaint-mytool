# Fork maintenance

Read `CONTRIBUTING_FORK.md` and `docs/FORK_CUSTOMIZATIONS.md` before changing this repository. They define the fork's required behavior, validation, and upstream merge policy.

Use `origin` for this fork and `upstream` for vorssaint/vorssaint-utils. Preserve upstream ancestry with normal merges. Do not replace fork identity, update sources, display recovery, window memory, selected-device Bluetooth policy, volume feedback, or custom companion behavior while resolving conflicts.

Run `python3 Tools/check-upstream.py` when assessing upstream. For integrations, update `docs/upstream-state.json` and add a record under `docs/upstream-sync/`. Build/test success is not physical-device validation. Never claim a release or installation occurred merely because source merged into main.
