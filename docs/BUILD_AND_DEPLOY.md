# Build and deploy NIGHT SCHOOL

NIGHT SCHOOL targets Godot **4.5.1 stable**, the Compatibility renderer, and a single-threaded Web export. The generated browser build is `build/web/index.html`. `Assets/` contains the original source packs; only the curated game assets in `art/` are included in the exported game.

## Build locally on Windows

Install the standard Godot 4.5.1 editor and matching export templates. Run this from the project directory in PowerShell:

```powershell
./scripts/build_web.ps1
```

The script looks for `GODOT_EXE`, a `godot` or `godot4` executable on PATH, then the current user's downloaded Godot 4.5.1 console executable. To choose it explicitly:

```powershell
./scripts/build_web.ps1 -GodotExe 'C:\path\Godot_v4.5.1-stable_win64_console.exe'
```

The script imports assets, runs every `tests/test_*.gd` plus `tests/smoke_test.gd`, and exports the Web preset. Tests must terminate with `quit(0)` for success or a nonzero exit code for failure. Script/import/export errors also fail the build even if Godot returns zero. Logs are written to `build/logs/`. The build clears only generated files inside this checkout's `build/web/`. `-SkipTests` is available for local export iteration; CI always runs tests.

Open the build through a local web server, not by double-clicking the HTML file:

```powershell
python tools/serve_web.py
```

Visit `http://127.0.0.1:8060/`. Use `--port 8061` if that port is occupied. The server binds only to localhost, serves the correct WebAssembly content type, and disables caching for development. A desktop browser with WebGL 2 and WebAssembly is required. The branded shell tracks download progress and resizes the canvas with the browser. Game controls receive focus when the player clicks the canvas. This release does not enable threads, GDExtensions, or service-worker caching, so GitHub Pages does not need custom cross-origin isolation headers.

## Publish on pushes to main

The workflow `.github/workflows/web.yml` runs on pushes to `main` and manual dispatch. A self-hosted Windows X64 runner imports, tests, and exports the game. GitHub's official Pages artifact and deployment actions then publish the result. The deployment job runs on GitHub's Ubuntu runner; no game build or asset import runs there. Build logs are retained for seven days.

Repository prerequisites:

1. Register an online self-hosted runner for this repository, or an organization runner allowed to access it, with the labels `self-hosted`, `Windows`, and `X64`. A runner registered to a different repository cannot pick up this build.
2. Install PowerShell 7 (`pwsh`), Git for Windows (including Git Bash and GNU tar), Godot 4.5.1 stable, and the matching export templates for the account running the runner. Use a current GitHub Actions runner supporting Node 24 for `actions/checkout@v6` (runner 2.327.1 or later).
3. Set the repository Actions variable `GODOT_EXE` if the executable is not on PATH or in the default Downloads location. A service account has a different profile and export-template directory from an interactive user.
4. Under **Settings → Pages → Build and deployment**, select **GitHub Actions** as the source. The `github-pages` environment must permit `main` deployments.
5. Push the tested source and curated art to `main`. The workflow has read access to source; only its deployment job receives `pages: write` and `id-token: write`.

Do not enable pull-request triggers for arbitrary contributors on a personal self-hosted runner. This workflow intentionally runs only trusted pushes to `main` or explicit manual dispatches. Checkout cleanup is disabled to avoid deleting local source asset packs; export exclusions and the generated-output cleanup keep those packs out of the published game.

The game is published at [Night School on GitHub Pages](https://ethannyakabuski.github.io/DealerRPG/). The [first verified deployment](https://github.com/EthannYakabuski/DealerRPG/actions/runs/36884531478) built commit `402c05a`, passed all tests, and published successfully on October 1, 2026. A separate Chrome session then loaded and played the actual public WebAssembly build; see [release verification](VALIDATION.md).

### Register a separate runner

This workspace has a separate runner named `night-school-desktop` under `.local/actions-runner`. It was registered for DealerRPG using the official, checksum-verified GitHub runner 2.337.0. Its process must remain running for builds to start; no Windows service was installed. Pages is configured to use GitHub Actions, and the `GODOT_EXE` repository variable selects the installed editor.

To replace this setup on another machine, open **Settings → Actions → Runners → New self-hosted runner**, select Windows and X64, and follow GitHub's download and checksum instructions in a new directory. Do not reconfigure a runner that belongs to another repository.

From the new runner directory, configure it for this repository. GitHub's setup page supplies a short-lived registration token; enter it when prompted instead of saving it in the project:

```powershell
./config.cmd --url https://github.com/EthannYakabuski/DealerRPG --name night-school-desktop --labels night-school
./run.cmd
```

Keep the runner running and the computer awake when pushing a build. A runner running in a terminal stops when that session ends; installing it as a Windows service is a separate optional setup step. The Actions workflow remains queued while no matching runner is online.

## Visual and browser checks

`tests/render_capture.gd` runs the real game renderer and saves title, campus, backpack, city-map, apartment, and evening screenshots under `build/screenshots/`. Run it with the Godot console executable, `--path . --rendering-method gl_compatibility --resolution 1280x800 --script res://tests/render_capture.gd`. Do not add `--headless`: the capture needs a real graphics device. It uses a separate test save.

`tools/browser_smoke.mjs` uses Node 22+ and an installed Chrome to test the exported game through WebAssembly. Start the localhost server first, then run `node tools/browser_smoke.mjs boot --name browser-title`. This creates a fresh browser profile under `.local/chrome-qa-profile`, listens for debugging only on localhost, and records browser errors and a screenshot in `build/`. It does not use a personal browser session and does not disable browser security.

After inspecting that screenshot, use `click --x X --y Y --name label` or `key --key b --name backpack` to exercise the visible game. `capture --name label` captures the current state, `reload` loads a fresh export, and `close` shuts down only that isolated QA browser. Set `CHROME_EXE` if Chrome is installed in a different location. Browser testing is an explicit local QA step; CI runs the deterministic game, interface, world, and scene tests.

Use `benchmark --name browser-performance` for a five-second animation-frame sample with average FPS, median and 95th-percentile frame intervals, and the WebGL renderer. The measurement describes the current visible scene, so record whether play is paused. To verify the published build, start a new isolated session with `boot --url https://ethannyakabuski.github.io/DealerRPG/`. The driver allows only localhost and that exact published game URL.

## Asset and output boundaries

`Assets/.gdignore` prevents importing the full source packs. The Web preset excludes `Assets/*`, test files, documentation, build tools, and build output. It exports all remaining imported resources so dynamically loaded curated models are available, and explicitly includes the JSON asset manifest. The original GLB files are not additionally packed as raw files. Keep new playable art in `art/`; do not remove the source-pack exclusion. Do not commit `build/` or `.godot/`.

## References

- [Godot 4.5 Web export](https://docs.godotengine.org/en/4.5/tutorials/export/exporting_for_web.html)
- [Godot custom HTML shell](https://docs.godotengine.org/en/4.5/tutorials/platform/web/customizing_html5_shell.html)
- [GitHub Pages custom workflows](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages)
- [Official Pages artifact action, including Windows support](https://github.com/actions/upload-pages-artifact)
- [GitHub self-hosted runner setup](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/adding-self-hosted-runners)
