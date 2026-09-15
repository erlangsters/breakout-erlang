%%
%% Copyright (c) 2026, Byteplug LLC.
%%
%% This source file is part of a project made by the Erlangsters community and
%% is released under the MIT license. Please refer to the LICENSE.md file that
%% can be found at the root of the project repository.
%%
%% Written by Jonathan De Wachter <jonathan.dewachter@byteplug.io>
%%
-module(window).
-moduledoc """
GLFW window plus EGL context setup for Breakout.

It creates a contextless GLFW window, opens a matching EGL display for the
selected window-system platform, and makes an OpenGL or OpenGL ES context
current on that window.
""".

-export([
    initialize/3,
    terminate/1,
    should_close/1,
    swap_buffers/1,
    poll_events/0,
    drain_events/0,
    glfw_window/1
]).

-include_lib("gl/include/gl.hrl").
-include_lib("glfw/include/glfw.hrl").

-doc """
Create a window and make a graphics context current.

It returns an opaque context map used by the rest of the window helpers.
""".
-spec initialize(pos_integer(), pos_integer(), string()) -> map().
initialize(Width, Height, Title) ->
    ok = init_glfw(),

    Display = open_egl_display(),
    {ok, {EglMajor, EglMinor}} = initialize_egl(Display),
    ok = bind_api(),

    Config = choose_config(Display),
    ok = ensure_context_extension(Display),
    Context = create_context(Display, Config),
    Window = create_window(Width, Height, Title, Display, Context),
    Surface = create_surface(Display, Config, Window, Context),

    case egl:make_current(Display, Surface, Surface, Context) of
        ok ->
            ok;
        not_ok ->
            erlang:error({egl_error, make_current, egl:get_error()})
    end,
    % bind_api/1 is per-OS-thread. The first call is for create_context/4 on
    % a scheduler thread; this second call runs on the context executor.
    ok = bind_api(),

    ok = load_gl_entry_points(),
    ok = print_info(EglMajor, EglMinor),

    ok = glfw:set_framebuffer_size_handler(Window, self()),
    ok = glfw:set_window_close_handler(Window, self()),
    {FbWidth, FbHeight} = glfw:framebuffer_size(Window),
    ok = gl:viewport(0, 0, FbWidth, FbHeight),
    _ = egl:swap_interval(Display, 1),

    #{
        display => Display,
        context => Context,
        surface => Surface,
        window => Window
    }.

-doc "Destroy the window, surface, context, and EGL display.".
-spec terminate(map()) -> ok.
terminate(#{display := Display, context := Context, surface := Surface, window := Window}) ->
    % On Wayland the EGL display wraps GLFW's wl_display. Release EGL
    % first so glfw:terminate/0 does not close that connection out from
    % under a live EGL display.
    _ = egl:make_current(Display, no_surface, no_surface, no_context),
    _ = egl:destroy_surface(Display, Surface),
    _ = egl:destroy_context(Display, Context),
    _ = egl:terminate(Display),
    _ = glfw:set_error_handler(undefined),
    _ = glfw:destroy_window(Window),
    _ = glfw:terminate(),
    ok.

-doc "Return whether the user asked the window to close.".
-spec should_close(map()) -> boolean().
should_close(#{window := Window}) ->
    glfw:window_should_close(Window).

-doc "Present the current back buffer.".
-spec swap_buffers(map()) -> ok.
swap_buffers(#{display := Display, surface := Surface}) ->
    case egl:swap_buffers(Display, Surface) of
        ok ->
            ok;
        not_ok ->
            erlang:error({egl_error, swap_buffers, egl:get_error()})
    end.

-doc "Poll native window events and deliver handler messages.".
-spec poll_events() -> ok.
poll_events() ->
    glfw:poll_events().

-doc """
Drain pending window messages.

It updates the viewport on framebuffer resize.
""".
-spec drain_events() -> ok.
drain_events() ->
    receive
        #glfw_framebuffer_size{size = {Width, Height}} ->
            gl:viewport(0, 0, Width, Height),
            drain_events();
        #glfw_window_close{} ->
            drain_events();
        _Event ->
            drain_events()
    after 0 ->
        ok
    end.

-doc "Return the GLFW window handle stored in the context map.".
-spec glfw_window(map()) -> glfw:window().
glfw_window(#{window := Window}) ->
    Window.

init_glfw() ->
    ErrorHandler = spawn(fun glfw_error_loop/0),
    ok = glfw:set_error_handler(ErrorHandler),
    case glfw:init() of
        true ->
            ok;
        false ->
            erlang:error({glfw_init_failed, glfw:get_error()})
    end.

glfw_error_loop() ->
    receive
        #glfw_error{code = Code, description = Description} ->
            io:format(
                standard_error,
                "GLFW error ~p: ~s~n",
                [Code, Description]
            ),
            glfw_error_loop()
    end.

open_egl_display() ->
    {ok, GlfwPlatform} = glfw:platform(),
    NativeDisplay = case glfw:display_egl_handle() of
        error ->
            erlang:error(glfw_display_egl_handle_failed);
        Handle ->
            Handle
    end,
    EglPlatform = egl_platform(GlfwPlatform),
    case egl:get_platform_display(EglPlatform, NativeDisplay, []) of
        no_display ->
            erlang:error({egl_get_platform_display_failed, EglPlatform});
        Display ->
            Display
    end.

egl_platform(wayland) ->
    wayland;
egl_platform(x11) ->
    x11;
egl_platform(win32) ->
    angle;
egl_platform(cocoa) ->
    angle;
egl_platform(Other) ->
    erlang:error({unsupported_glfw_platform, Other}).

initialize_egl(Display) ->
    case egl:initialize(Display) of
        {ok, Version} ->
            {ok, Version};
        not_ok ->
            erlang:error({egl_initialize_failed, egl:get_error()})
    end.

bind_api() ->
    Api = case ?GL_BINDING_API of
        gl ->
            opengl_api;
        gles ->
            opengl_es_api
    end,
    case egl:bind_api(Api) of
        ok ->
            ok;
        not_ok ->
            erlang:error({egl_bind_api_failed, Api, egl:get_error()})
    end.

load_gl_entry_points() ->
    case ?GL_BINDING_API of
        gl ->
            ok = gl:glad_load_gl();
        gles ->
            ok
    end.

choose_config(Display) ->
    RenderableType = case ?GL_BINDING_API of
        gl ->
            opengl_bit;
        gles ->
            opengl_es2_bit
    end,
    Attribs = [
        {surface_type, [window_bit]},
        {renderable_type, [RenderableType]},
        {red_size, 8},
        {green_size, 8},
        {blue_size, 8},
        {depth_size, 24}
    ],
    case egl:choose_config(Display, Attribs) of
        {ok, [Config | _]} ->
            Config;
        not_ok ->
            erlang:error({egl_choose_config_failed, egl:get_error()})
    end.

create_context(Display, Config) ->
    {Major, Minor} = ?GL_BINDING_VERSION,
    Attribs = [
        {context_major_version, Major},
        {context_minor_version, Minor}
    ],
    case egl:create_context(Display, Config, no_context, Attribs) of
        {ok, Context} ->
            Context;
        not_ok ->
            erlang:error({
                egl_create_context_failed,
                ?GL_BINDING_API,
                ?GL_BINDING_VERSION,
                egl:get_error()
            })
    end.

ensure_context_extension(Display) ->
    case {?GL_BINDING_API, ?GL_BINDING_VERSION} of
        {gles, {Major, _Minor}} when Major >= 3 ->
            case egl:query_string(Display, extensions) of
                {ok, Extensions} ->
                    case lists:member("EGL_KHR_create_context", string:tokens(Extensions, " ")) of
                        true ->
                            ok;
                        false ->
                            erlang:error(egl_khr_create_context_required)
                    end;
                not_ok ->
                    erlang:error(egl_query_extensions_failed)
            end;
        _ ->
            ok
    end.

create_window(Width, Height, Title, Display, Context) ->
    case glfw:create_window(Width, Height, Title) of
        {ok, Window} ->
            Window;
        no_window ->
            glfw:terminate(),
            egl:destroy_context(Display, Context),
            egl:terminate(Display),
            erlang:error({glfw_create_window_failed, glfw:get_error()})
    end.

create_surface(Display, Config, Window, Context) ->
    WindowHandle = glfw:window_egl_handle(Window),
    case egl:create_window_surface(Display, Config, WindowHandle, []) of
        {ok, Surface} ->
            Surface;
        not_ok ->
            glfw:destroy_window(Window),
            glfw:terminate(),
            egl:destroy_context(Display, Context),
            egl:terminate(Display),
            erlang:error({egl_create_window_surface_failed, egl:get_error()})
    end.

print_info(EglMajor, EglMinor) ->
    {ok, GlfwPlatform} = glfw:platform(),
    io:format("GLFW platform: ~p~n", [GlfwPlatform]),
    io:format("EGL version: ~p.~p~n", [EglMajor, EglMinor]),
    io:format("GL binding: ~p ~p~n", [?GL_BINDING_API, ?GL_BINDING_VERSION]),

    {ok, Version} = gl:get_string(version),
    io:format("OpenGL version: ~s~n", [Version]),
    {ok, Vendor} = gl:get_string(vendor),
    io:format("OpenGL vendor: ~s~n", [Vendor]),
    {ok, Renderer} = gl:get_string(renderer),
    io:format("OpenGL renderer: ~s~n", [Renderer]),
    {ok, ShadingLanguageVersion} = gl:get_string(shading_language_version),
    io:format("OpenGL shading language version: ~s~n", [ShadingLanguageVersion]),
    ok.
