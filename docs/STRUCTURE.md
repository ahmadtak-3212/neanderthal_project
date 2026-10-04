# Project structure

Every project uses the same top-level layout. Only create the folders the project needs:
a pure CAD project may have just `docs/` and `mechanical/`, and a web app may have just `docs/` and `software/`.

```
project_name/
├── README.md            what it is, status table, how to rebuild, results
├── .gitignore           covers KiCad, SolidWorks, PlatformIO, Vivado, Python, Node
├── .gitattributes       line endings + Git LFS for big binary CAD
├── docs/
│   ├── images/          photos, renders, diagrams used by the README and site
│   ├── reference/       datasheets, app notes, papers (not your own work)
│   ├── reports/         proposal, design review, final report (source + PDF)
│   └── STRUCTURE.md     this file
├── mechanical/
│   ├── cad/             native files: SolidWorks .SLDPRT/.SLDASM, Fusion .f3d
│   ├── exports/         STEP, STL, 3MF, DXF, SVG, generated from cad/
│   └── cam/             toolpaths, G-code, slicer projects, laser/CNC setups
├── electrical/
│   ├── <board_name>/    one KiCad project per board, created from the KiCad template
│   │                    (cad/ docs/ jlcpcb/ libs/ manufacturing/ meta/ templates/)
│   └── sim/             SPICE, LTspice, loop and filter sims not tied to one board
├── firmware/
│   └── <target_name>/   one PlatformIO (or CubeIDE / ESP-IDF) project per MCU
│                        (include/ lib/ src/ test/ platformio.ini)
├── fpga/                AMD flow: vivado/<board>/ vitis/{ip,src}/ linux/{petalinux,yocto,dtg}/
│                        ps_apps/ vss/; small RTL-only projects use rtl/ sim/ constraints/
├── software/
│   └── <app_name>/      host tools, servers, web apps, GUIs (src/ tests/ + manifest)
├── analysis/            MATLAB / Python / notebooks: models, calculations, test data + plots
├── tools/               scripts to build, flash, export, or test the whole project
├── admin/               budget, receipts, orders, quotes. Git-ignored (private)
└── archive/             superseded designs kept for reference. Nothing live goes here
```

## Rules

1. **Names:** lowercase `snake_case`, no spaces, for folders and for files you create.
   Vendor files (datasheets, library parts) keep their own names.
2. **Pick the folder by discipline.** A board goes in `electrical/`, its enclosure in `mechanical/`,
   its code in `firmware/`. Don't use tool names (`kicad/`) or version numbers (`design_v2/`) at the top level.
3. **One tool project per subfolder.** Each board, firmware target, and app gets its own folder
   named for what it is (`main_board/`, `led_driver/`, `receiver_fw/`), never `pcb/` or `firmware2/`.
4. **Revisions:** use git tags (`hw-rev-a`, `fw-v1.2`) and the KiCad revision-history sheet,
   not copied folders. If two revisions really must live side by side, use `<board_name>/rev_a/`, `rev_b/`.
   Retired designs move to `archive/`.
5. **Native vs. exported:** native CAD goes in `cad/`, generated files go in `exports/`. Re-export whenever the native file changes.
6. **Don't commit generated files**: build outputs, `.pio/`, KiCad backups, and Vivado run dirs are covered by `.gitignore`.
   The exception is fab outputs for a board you actually ordered: commit them under that board's `manufacturing/` or `jlcpcb/`.
7. **Your own work vs. references:** datasheets and other people's papers go in `docs/reference/`;
   third-party libraries go in firmware `lib/` or as git submodules.
8. **No absolute paths** inside project files. In KiCad use `${KIPRJMOD}/…`, and use relative paths everywhere else,
   so the project works on both Windows and Linux.
