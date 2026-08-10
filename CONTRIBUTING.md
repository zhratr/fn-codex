# Contributing

Issues and pull requests are welcome. Please keep changes small and reviewable, preserve the non-official/community labeling, and add a local validation step for new behavior.

Before opening a pull request:

```sh
npm run check
bash scripts/validate-fpk.sh --source fpk
```

Real fnOS installation tests should state the fnOS version, CPU architecture, install method, lifecycle result, and whether the browser UI was reached end to end.
