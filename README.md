# The Breakout game in Erlang

[![Erlangsters Repository](https://img.shields.io/badge/erlangsters-breakout--erlang-%23a90432)](https://github.com/erlangsters/breakout-erlang)
![Supported Erlang/OTP Versions](https://img.shields.io/badge/erlang%2Fotp-28-%23a90432)
![License](https://img.shields.io/github/license/erlangsters/breakout-erlang)
[![Build Status](https://img.shields.io/github/actions/workflow/status/erlangsters/breakout-erlang/workflow.yml)](https://github.com/erlangsters/breakout-erlang/actions/workflows/workflow.yml)

:construction: It's a work-in-progress. Do not use this repo yet.

The classic Breakout game implemented in Erlang, for reference.

It is also a composition check for the Erlangsters graphics stack: GLFW
creates the window, EGL owns the context and surface, GLM builds the
projection and model matrices, and the OpenGL binding draws.

It uses OpenGL ES 3.1 (via EGL). On Windows and macOS that means ANGLE.

Written by the Erlangsters [community](https://about.erlangsters.org/) and
released under the MIT [license](https://opensource.org/license/mit).

## Getting started

Build and run the current prototype with:

```sh
./run.sh
```

On Windows:

```powershell
.\run.ps1
```

The run scripts compile the application and its native bindings, then start
the game. Close the window or press Escape to quit.

On Windows and macOS, set `ANGLE_INCLUDE_DIR` and `ANGLE_LIB_DIR` to your
ANGLE install. `run.ps1` puts ANGLE's `bin` directory on `PATH`. Windows also
needs `VCPKG_ROOT` pointing at a vcpkg tree that can provide GLFW (GitHub
Actions uses `C:\vcpkg`; a Chocolatey install is often `C:\tools\vcpkg`).

Controls:

- Left / Right, or A / D, to move the paddle
- Space to serve, and to restart after a win or loss
- Escape to quit

The window title shows the score and remaining lives.

To smoke-test a few frames without playing, set `BREAKOUT_MAX_TICKS`:

```sh
BREAKOUT_MAX_TICKS=30 ./run.sh
```

The prototype depends on `egl-1.5`, `glfw`, `glm`, and `opengl-es-3.1`. The
shaders select a GLSL preamble from the binding's API and version macros.
