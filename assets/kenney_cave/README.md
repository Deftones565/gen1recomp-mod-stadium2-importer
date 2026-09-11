# Cave scene assets

Source: Kenney Game Assets All-in-1 3.7.0, **Modular Cave Kit** (CC0).
Selected pieces: `template-wall`, `template-detail`, `gate-rock`.
Rubble uses `rock_smallA` from the CC0 Nature Kit; its license is retained in
`../kenney_nature/License.txt`. The cave kit license is alongside this file.

Rebuild from the local collection:

```sh
python3 tools/build_kenney_cave.py '/path/to/3D assets/Modular Cave Kit'
```

The runtime combines these pieces with a continuous floor and vaulted ceiling.
It reuses the stone and bark quadrants of the generated woodland watercolor
material atlas, documented in `../kenney_nature/README.md`.
