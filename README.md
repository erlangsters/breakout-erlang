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

The intended long-term OpenGL target is OpenGL ES 3.1. The current checkout
temporarily uses OpenGL 4.6 so the rest of the stack can be proven together on
desktop Linux.

Written by the Erlangsters [community](https://about.erlangsters.org/) and
released under the MIT [license](https://opensource.org/license/mit).

## Getting started

Build and run the current prototype with:

```sh
./run.sh
```

`run.sh` compiles the application and its native bindings, then starts the
game. Close the window or press Escape to quit.

Controls:

- Left / Right, or A / D, to move the paddle
- Space to serve, and to restart after a win or loss
- Escape to quit

The window title shows the score and remaining lives.

To smoke-test a few frames without playing, set `BREAKOUT_MAX_TICKS`:

```sh
BREAKOUT_MAX_TICKS=30 ./run.sh
```

The prototype currently depends on `egl-1.5`, `glfw`, `glm`, and `opengl-4.6`.
Switching back to OpenGL ES 3.1 is a dependency change in `rebar.config`; the
shaders already select a GLSL preamble from the binding's API and version
macros.
