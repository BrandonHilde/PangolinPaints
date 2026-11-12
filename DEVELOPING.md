# Developing Pangolin Paints

How to build, run, test and change it. For using it, see the [README](README.md) and the [guide](GUIDE.md).

## Building and installing from source

Build with `./build.sh` on Linux/macOS or `build.bat` on Windows. [OdinUI](https://gitlab.com/patrick.pixelshuffle/odinui) and
the code shared with the other Pangolin tools are git submodules in `libs/odinui` and `libs/shared`: clone with
`git clone --recursive`, or let the build scripts fetch them on the first build (`git submodule update --init`). The build
scripts copy the shared code into `src` as `shared_*.odin`. To build by hand: `sh libs/shared/sync.sh`, then
`odin build src -out:PangolinPaints -o:speed -collection:odinui=libs/odinui`.
To update to the newest version, run `update.bat` (Windows) or `./update.sh`: it pulls the latest commits and moves the
submodules to the versions they expect (a plain `git pull` leaves the submodules where they were, and the build then
fails). `build.bat` / `./build.sh` on their own build whatever is there now.
On Linux, `./install.sh` builds the program and installs it for your account: in `~/.local/opt/pangolin/PangolinPaints`, with
its own settings, workspaces and macros (apart from this folder's build), and in the application list with its icon.
Run it again to update, or `./install.sh --uninstall` to remove it. To install a build made elsewhere (for another
account on the computer, or without Odin), put `install.sh`, the `PangolinPaints` program and `assets/icon` in one folder and
run `sh install.sh --no-build` there.
Drag images or projects onto the window to open them; hold Shift while dropping to import an image as a layer.
`PangolinPaints --selftest` runs the headless test suite (on Windows use `PangolinPaints-console.exe`, since the GUI build has no console).

## Developer flags
`--selftest` (tests), `--demo` (sample painting), `--shot file.png` (screenshot after a few frames), `--shot-frame N` (the frame to
take it on), `--size WxH`, `--scale N` (UI scale in percent for this run: not saved),
`--menu N` (opens menu N), `--dialog N` (opens dialog N), `--demo-frames N` (the sample painting with N frames and the timeline showing),
`--files folder` (opens the file browser there, as the system's folder picker can't be scripted),
`--drag "frame:x0,y0,x1,y1;..."` (presses at the first point on that frame, moves to the second and releases, for checking drags),
`--clicks "frame:x,y;..."` (left clicks at window pixels on those frames, for checking the interface with `--shot`),
`--hover "frame:x,y"` (rests the pointer there from that frame on, for checking tooltips with `--shot` and a later `--shot-frame`),
`--bench` (timings on a 4000x3000 canvas), `--brush-sheet out.png` (one stroke per preset),
`--icon-sheet out.png` (every icon at each size and UI scale, and the logo),
`--crop x,y,w,h` (the part of the window `--shot` saves), `--type "frame:text;frame:ENTER"` (typing on those frames, for checking
text fields with `--shot`), `--convert in out` (opens one file, saves it as the other and exits, with no window).

Icons are SVG files in `assets/icons` (24 x 24, drawn in `currentColor` with round-capped 2 px strokes) and the logo is
`assets/icon`; both are built into the executable and rasterised at the screen's resolution by `src/svg.odin`.

## Releases
A tag such as `v0.9.0-beta` (matching `APP_VERSION` in `src/brand.odin`) runs `.github/workflows/release.yml`: it builds Windows, macOS and Linux bundles, runs `--selftest` inside each, and makes a draft GitHub release to try before publishing. Actions > Release > Run workflow builds the bundles without releasing. The workflow and the packaging script (`libs/shared/release/package.sh`) live in [PangolinShared](https://github.com/BrandonHilde/PangolinShared).

## License
BSD 3-Clause. See [LICENSE](LICENSE).
