This is an example project using CMake.

The requirements are:

- CMake 3.11 or better; 3.14+ highly recommended.
- A C++17 compatible compiler
- The Boost libararies (header only part is fine)
- Git
- Doxygen (optional)

To configure:

```bash
cmake -S . -B build
cmake -DARCH_PREFIX=arm -DCPU_PREFIX=cortex-a9 -DPLATFORM_PREFIX=am335x -GNinja -S . -B build
rm -rf build && cmake -DARCH_PREFIX=arm -DCPU_PREFIX=cortex-a9 -DPLATFORM_PREFIX=am335x -GNinja -S . -B build && cd build && ninja
```

Add `-GNinja` if you have Ninja.

To build:

```bash
cmake --build build
```

To test (`--target` can be written as `-t` in CMake 3.15+):

```bash
cmake --build build --target test
```

To build docs (requires Doxygen, output in `build/docs/html`):

```bash
cmake --build build --target docs
```

To use an IDE, such as Xcode:

```bash
cmake -S . -B xbuild -GXcode
cmake --open xbuild
```