%%
%% Copyright (c) 2026, Byteplug LLC.
%%
%% This source file is part of a project made by the Erlangsters community and
%% is released under the MIT license. Please refer to the LICENSE.md file that
%% can be found at the root of the project repository.
%%
%% Written by Jonathan De Wachter <jonathan.dewachter@byteplug.io>
%%
-module(breakout).
-moduledoc """
Classic Breakout implemented with the Erlangsters graphics stack.

It composes GLFW, EGL, GLM, and the selected OpenGL binding into a small
playable reference. The default checkout currently uses OpenGL 4.6; the
intended long-term target is OpenGL ES 3.1.
""".

-export([start/0]).

-include_lib("gl/include/gl.hrl").
-include_lib("glfw/include/glfw.hrl").

-define(WIDTH, 800).
-define(HEIGHT, 600).
-define(PADDLE_WIDTH, 110.0).
-define(PADDLE_HEIGHT, 16.0).
-define(PADDLE_MARGIN, 24.0).
-define(PADDLE_SPEED, 520.0).
-define(BALL_SIZE, 14.0).
-define(BALL_SPEED, 420.0).
-define(BRICK_WIDTH, 70.0).
-define(BRICK_HEIGHT, 22.0).
-define(BRICK_ROWS, 5).
-define(BRICK_COLS, 10).
-define(BRICK_PADDING, 6.0).
-define(BRICK_OFFSET_TOP, 56.0).
-define(MAX_DT, 0.05).

-record(game, {
    ctx,
    program,
    vao,
    vbo,
    projection_location,
    model_location,
    color_location,
    projection,
    paddle_x,
    ball_x,
    ball_y,
    ball_vx,
    ball_vy,
    bricks = [],
    lives = 3,
    score = 0,
    phase = ready,
    last_ns
}).

-doc """
Start the game.

It opens a window, runs until the window closes, then shuts the graphics
stack down. `BREAKOUT_MAX_TICKS` can limit the loop for smoke tests.
""".
-spec start() -> ok.
start() ->
    ok = load_graphics_apps(),
    Ctx = window:initialize(?WIDTH, ?HEIGHT, "Breakout"),
    try
        Resources = setup_resources(),
        try
            loop(new_game(Ctx, Resources), 0, max_ticks())
        after
            cleanup(Resources)
        end
    after
        window:terminate(Ctx)
    end,
    ok.

load_graphics_apps() ->
    lists:foreach(fun(App) ->
        case application:load(App) of
            ok ->
                ok;
            {error, {already_loaded, App}} ->
                ok
        end,
        {module, _} = code:ensure_loaded(App)
    end, [egl, glm, gl, glfw]).

setup_resources() ->
    Program = create_program(),
    ok = gl:use_program(Program),

    {ok, ProjectionLocation} = gl:get_uniform_location(Program, <<"u_projection">>),
    {ok, ModelLocation} = gl:get_uniform_location(Program, <<"u_model">>),
    {ok, ColorLocation} = gl:get_uniform_location(Program, <<"u_color">>),

    {ok, [VertexArray]} = gl:gen_vertex_arrays(1),
    {ok, [VertexBuffer]} = gl:gen_buffers(1),

    ok = gl:bind_vertex_array(VertexArray),
    ok = gl:bind_buffer(array_buffer, VertexBuffer),
    ok = gl:buffer_data(array_buffer, quad_vertices(), static_draw),
    ok = gl:vertex_attrib_pointer(0, 2, float, false, 2 * 4, 0),
    ok = gl:enable_vertex_attrib_array(0),
    ok = gl:bind_vertex_array(none),

    Projection = glm_transform:ortho(
        glm:float(0.0),
        glm:float(float(?WIDTH)),
        glm:float(float(?HEIGHT)),
        glm:float(0.0),
        glm:float(-1.0),
        glm:float(1.0)
    ),

    #{
        program => Program,
        vao => VertexArray,
        vbo => VertexBuffer,
        projection_location => ProjectionLocation,
        model_location => ModelLocation,
        color_location => ColorLocation,
        projection => Projection
    }.

create_program() ->
    {ok, VertexShader} = gl:create_shader(vertex_shader),
    ok = gl:shader_source(VertexShader, [vertex_shader_source()]),
    ok = gl:compile_shader(VertexShader),
    ok = assert_shader_compiled(VertexShader),

    {ok, FragmentShader} = gl:create_shader(fragment_shader),
    ok = gl:shader_source(FragmentShader, [fragment_shader_source()]),
    ok = gl:compile_shader(FragmentShader),
    ok = assert_shader_compiled(FragmentShader),

    {ok, Program} = gl:create_program(),
    ok = gl:attach_shader(Program, VertexShader),
    ok = gl:attach_shader(Program, FragmentShader),
    ok = gl:link_program(Program),
    ok = assert_program_linked(Program),

    ok = gl:detach_shader(Program, VertexShader),
    ok = gl:detach_shader(Program, FragmentShader),
    ok = gl:delete_shader(VertexShader),
    ok = gl:delete_shader(FragmentShader),
    Program.

new_game(Ctx, Resources) ->
    PaddleX = (float(?WIDTH) - ?PADDLE_WIDTH) / 2.0,
    #game{
        ctx = Ctx,
        program = maps:get(program, Resources),
        vao = maps:get(vao, Resources),
        vbo = maps:get(vbo, Resources),
        projection_location = maps:get(projection_location, Resources),
        model_location = maps:get(model_location, Resources),
        color_location = maps:get(color_location, Resources),
        projection = maps:get(projection, Resources),
        paddle_x = PaddleX,
        ball_x = ball_x_on_paddle(PaddleX),
        ball_y = ball_y_on_paddle(),
        ball_vx = 0.0,
        ball_vy = 0.0,
        bricks = generate_bricks(),
        lives = 3,
        score = 0,
        phase = ready,
        last_ns = erlang:monotonic_time(nanosecond)
    }.

loop(_Game, Counter, MaxTicks) when is_integer(MaxTicks), Counter >= MaxTicks ->
    ok;
loop(Game, Counter, MaxTicks) ->
    case window:should_close(Game#game.ctx) of
        true ->
            ok;
        false ->
            window:poll_events(),
            window:drain_events(),
            Now = erlang:monotonic_time(nanosecond),
            Dt = frame_dt(Game#game.last_ns, Now),
            Next = render(update(handle_input(Game#game{last_ns = Now}, Dt), Dt)),
            window:swap_buffers(Next#game.ctx),
            loop(Next, Counter + 1, MaxTicks)
    end.

handle_input(Game, Dt) ->
    Window = window:glfw_window(Game#game.ctx),
    case glfw:key(Window, key_escape) of
        press ->
            ok = glfw:set_window_should_close(Window, true);
        release ->
            ok
    end,
    case {Game#game.phase, glfw:key(Window, key_space)} of
        {ready, press} ->
            launch_ball(Game);
        {won, press} ->
            reset_game(Game);
        {lost, press} ->
            reset_game(Game);
        _ ->
            move_paddle(Game, Dt, Window)
    end.

move_paddle(Game, Dt, Window) ->
    Direction = case {glfw:key(Window, key_left), glfw:key(Window, key_a)} of
        {press, _} ->
            -1.0;
        {_, press} ->
            -1.0;
        _ ->
            case {glfw:key(Window, key_right), glfw:key(Window, key_d)} of
                {press, _} ->
                    1.0;
                {_, press} ->
                    1.0;
                _ ->
                    0.0
            end
    end,
    MaxX = float(?WIDTH) - ?PADDLE_WIDTH,
    PaddleX = clamp(Game#game.paddle_x + Direction * ?PADDLE_SPEED * Dt, 0.0, MaxX),
    case Game#game.phase of
        ready ->
            Game#game{
                paddle_x = PaddleX,
                ball_x = ball_x_on_paddle(PaddleX),
                ball_y = ball_y_on_paddle()
            };
        _ ->
            Game#game{paddle_x = PaddleX}
    end.

launch_ball(Game) ->
    Angle = (rand:uniform() - 0.5) * 0.6,
    Game#game{
        phase = playing,
        ball_vx = ?BALL_SPEED * math:sin(Angle),
        ball_vy = -?BALL_SPEED * math:cos(Angle)
    }.

reset_game(Game) ->
    new_game(Game#game.ctx, #{
        program => Game#game.program,
        vao => Game#game.vao,
        vbo => Game#game.vbo,
        projection_location => Game#game.projection_location,
        model_location => Game#game.model_location,
        color_location => Game#game.color_location,
        projection => Game#game.projection
    }).

update(Game, _Dt) when Game#game.phase =/= playing ->
    Game;
update(Game, Dt) ->
    BallX = Game#game.ball_x + Game#game.ball_vx * Dt,
    BallY = Game#game.ball_y + Game#game.ball_vy * Dt,
    {ClampedX, VelX0} = bounce_axis(BallX, Game#game.ball_vx, 0.0, float(?WIDTH) - ?BALL_SIZE),
    {ClampedY, VelY0} = bounce_top(BallY, Game#game.ball_vy),
    case ClampedY > float(?HEIGHT) of
        true ->
            lose_life(Game);
        false ->
            AfterPaddle = bounce_paddle(
                Game#game{
                    ball_x = ClampedX,
                    ball_y = ClampedY,
                    ball_vx = VelX0,
                    ball_vy = VelY0
                }
            ),
            AfterBricks = bounce_bricks(AfterPaddle),
            case AfterBricks#game.bricks of
                [] ->
                    AfterBricks#game{phase = won};
                _ ->
                    AfterBricks
            end
    end.

lose_life(Game) ->
    Lives = Game#game.lives - 1,
    case Lives of
        0 ->
            Game#game{phase = lost, lives = 0};
        _ ->
            PaddleX = Game#game.paddle_x,
            Game#game{
                phase = ready,
                lives = Lives,
                ball_x = ball_x_on_paddle(PaddleX),
                ball_y = ball_y_on_paddle(),
                ball_vx = 0.0,
                ball_vy = 0.0
            }
    end.

bounce_axis(Position, Velocity, Min, _Max) when Position < Min ->
    {Min, -Velocity};
bounce_axis(Position, Velocity, _Min, Max) when Position > Max ->
    {Max, -Velocity};
bounce_axis(Position, Velocity, _Min, _Max) ->
    {Position, Velocity}.

bounce_top(Position, Velocity) when Position < 0.0 ->
    {0.0, -Velocity};
bounce_top(Position, Velocity) ->
    {Position, Velocity}.

bounce_paddle(Game) ->
    PaddleY = paddle_y(),
    Overlap = aabb_overlap(
        Game#game.ball_x,
        Game#game.ball_y,
        ?BALL_SIZE,
        ?BALL_SIZE,
        Game#game.paddle_x,
        PaddleY,
        ?PADDLE_WIDTH,
        ?PADDLE_HEIGHT
    ),
    case Overlap andalso Game#game.ball_vy > 0.0 of
        true ->
            Hit = (Game#game.ball_x + ?BALL_SIZE / 2.0 - Game#game.paddle_x) / ?PADDLE_WIDTH,
            Angle = (Hit - 0.5) * 1.2,
            Speed = math:sqrt(
                Game#game.ball_vx * Game#game.ball_vx +
                    Game#game.ball_vy * Game#game.ball_vy
            ),
            Game#game{
                ball_y = PaddleY - ?BALL_SIZE,
                ball_vx = Speed * math:sin(Angle),
                ball_vy = -Speed * math:cos(Angle)
            };
        false ->
            Game
    end.

bounce_bricks(Game) ->
    bounce_bricks(Game#game.bricks, Game, []).

bounce_bricks([], Game, Acc) ->
    Game#game{bricks = lists:reverse(Acc)};
bounce_bricks([{X, Y, Color} | Rest], Game, Acc) ->
    case aabb_overlap(
        Game#game.ball_x,
        Game#game.ball_y,
        ?BALL_SIZE,
        ?BALL_SIZE,
        X,
        Y,
        ?BRICK_WIDTH,
        ?BRICK_HEIGHT
    ) of
        true ->
            {Vx, Vy} = bounce_from_rect(
                Game#game.ball_x,
                Game#game.ball_y,
                ?BALL_SIZE,
                ?BALL_SIZE,
                Game#game.ball_vx,
                Game#game.ball_vy,
                X,
                Y,
                ?BRICK_WIDTH,
                ?BRICK_HEIGHT
            ),
            Game#game{
                bricks = lists:reverse(Acc, Rest),
                score = Game#game.score + 10,
                ball_vx = Vx,
                ball_vy = Vy
            };
        false ->
            bounce_bricks(Rest, Game, [{X, Y, Color} | Acc])
    end.

bounce_from_rect(Bx, By, Bw, Bh, Vx, Vy, Rx, Ry, Rw, Rh) ->
    OverlapX = min(Bx + Bw, Rx + Rw) - max(Bx, Rx),
    OverlapY = min(By + Bh, Ry + Rh) - max(By, Ry),
    case OverlapX < OverlapY of
        true ->
            {-Vx, Vy};
        false ->
            {Vx, -Vy}
    end.

aabb_overlap(Ax, Ay, Aw, Ah, Bx, By, Bw, Bh) ->
    Ax < Bx + Bw andalso Ax + Aw > Bx andalso
        Ay < By + Bh andalso Ay + Ah > By.

render(Game) ->
    {R, G, B} = clear_color(Game#game.phase),
    ok = gl:clear_color(R, G, B, 1.0),
    ok = gl:clear([color_buffer_bit]),
    ok = gl:use_program(Game#game.program),
    ok = gl:uniform_matrix(f, Game#game.projection_location, mat4_to_gl(Game#game.projection)),
    ok = gl:bind_vertex_array(Game#game.vao),

    draw_rect(
        Game,
        Game#game.paddle_x,
        paddle_y(),
        ?PADDLE_WIDTH,
        ?PADDLE_HEIGHT,
        {0.92, 0.93, 0.96}
    ),
    draw_rect(
        Game,
        Game#game.ball_x,
        Game#game.ball_y,
        ?BALL_SIZE,
        ?BALL_SIZE,
        {0.98, 0.85, 0.35}
    ),
    lists:foreach(
        fun({X, Y, Color}) ->
            draw_rect(Game, X, Y, ?BRICK_WIDTH, ?BRICK_HEIGHT, Color)
        end,
        Game#game.bricks
    ),

    ok = gl:bind_vertex_array(none),
    maybe_update_title(Game),
    Game.

draw_rect(Game, X, Y, Width, Height, {R, G, B}) ->
    Model = model_matrix(X, Y, Width, Height),
    ok = gl:uniform_matrix(f, Game#game.model_location, mat4_to_gl(Model)),
    ok = gl:uniform(f, Game#game.color_location, {R, G, B}),
    ok = gl:draw_arrays(triangle_fan, 0, 4).

model_matrix(X, Y, Width, Height) ->
    Translated = glm_transform:translate(
        identity_mat4(),
        glm:vec3(float, X, Y, 0.0)
    ),
    glm_transform:scale(
        Translated,
        glm:vec3(float, Width, Height, 1.0)
    ).

identity_mat4() ->
    glm:mat4(
        float,
        1.0, 0.0, 0.0, 0.0,
        0.0, 1.0, 0.0, 0.0,
        0.0, 0.0, 1.0, 0.0,
        0.0, 0.0, 0.0, 1.0
    ).

mat4_to_gl(Matrix) ->
    {
        A1, A2, A3, A4,
        B1, B2, B3, B4,
        C1, C2, C3, C4,
        D1, D2, D3, D4
    } = glm:mat4_values(Matrix),
    {
        {A1, A2, A3, A4},
        {B1, B2, B3, B4},
        {C1, C2, C3, C4},
        {D1, D2, D3, D4}
    }.

clear_color(won) ->
    {0.08, 0.22, 0.12};
clear_color(lost) ->
    {0.22, 0.07, 0.08};
clear_color(_) ->
    {0.07, 0.09, 0.14}.

maybe_update_title(Game) ->
    Title = lists:flatten(io_lib:format(
        "Breakout  score ~B  lives ~B~s",
        [Game#game.score, Game#game.lives, phase_suffix(Game#game.phase)]
    )),
    glfw:set_window_title(window:glfw_window(Game#game.ctx), Title).

phase_suffix(ready) ->
    "  (space to serve)";
phase_suffix(won) ->
    "  (you win — space to restart)";
phase_suffix(lost) ->
    "  (game over — space to restart)";
phase_suffix(playing) ->
    "".

generate_bricks() ->
    RowWidth = ?BRICK_COLS * (?BRICK_WIDTH + ?BRICK_PADDING) - ?BRICK_PADDING,
    OffsetLeft = (float(?WIDTH) - RowWidth) / 2.0,
    Colors = [
        {0.90, 0.32, 0.32},
        {0.95, 0.55, 0.22},
        {0.95, 0.80, 0.28},
        {0.38, 0.78, 0.42},
        {0.32, 0.62, 0.90}
    ],
    [
        {
            OffsetLeft + Col * (?BRICK_WIDTH + ?BRICK_PADDING),
            ?BRICK_OFFSET_TOP + Row * (?BRICK_HEIGHT + ?BRICK_PADDING),
            lists:nth(Row + 1, Colors)
        }
     || Row <- lists:seq(0, ?BRICK_ROWS - 1),
        Col <- lists:seq(0, ?BRICK_COLS - 1)
    ].

paddle_y() ->
    float(?HEIGHT) - ?PADDLE_MARGIN - ?PADDLE_HEIGHT.

ball_x_on_paddle(PaddleX) ->
    PaddleX + (?PADDLE_WIDTH - ?BALL_SIZE) / 2.0.

ball_y_on_paddle() ->
    paddle_y() - ?BALL_SIZE.

quad_vertices() ->
    pack_floats([
        0.0, 0.0,
        1.0, 0.0,
        1.0, 1.0,
        0.0, 1.0
    ]).

pack_floats(Values) ->
    << <<Value:32/float-little>> || Value <- Values >>.

cleanup(Resources) ->
    gl:use_program(none),
    gl:bind_vertex_array(none),
    gl:delete_buffers([maps:get(vbo, Resources)]),
    gl:delete_vertex_arrays([maps:get(vao, Resources)]),
    gl:delete_program(maps:get(program, Resources)),
    ok.

assert_shader_compiled(Shader) ->
    case gl:get_shader_compile_status(Shader) of
        {ok, true} ->
            ok;
        {ok, false} ->
            {ok, InfoLog} = gl:get_shader_info_log(Shader, 1024),
            erlang:error({shader_compile_failed, InfoLog})
    end.

assert_program_linked(Program) ->
    case gl:get_program_link_status(Program) of
        {ok, true} ->
            ok;
        {ok, false} ->
            {ok, InfoLog} = gl:get_program_info_log(Program, 1024),
            erlang:error({program_link_failed, InfoLog})
    end.

vertex_shader_source() ->
    [shader_preamble(),
     <<"layout(location = 0) in vec2 a_pos;\n"
       "uniform mat4 u_projection;\n"
       "uniform mat4 u_model;\n"
       "void main() {\n"
       "    gl_Position = u_projection * u_model * vec4(a_pos, 0.0, 1.0);\n"
       "}\n">>].

fragment_shader_source() ->
    [shader_preamble(),
     <<"out vec4 frag_color;\n"
       "uniform vec3 u_color;\n"
       "void main() {\n"
       "    frag_color = vec4(u_color, 1.0);\n"
       "}\n">>].

shader_preamble() ->
    case {?GL_BINDING_API, ?GL_BINDING_VERSION} of
        {gl, {4, 6}} ->
            <<"#version 460 core\n">>;
        {gl, {4, 1}} ->
            <<"#version 410 core\n">>;
        {gl, {3, 3}} ->
            <<"#version 330 core\n">>;
        {gles, {3, 2}} ->
            <<"#version 320 es\nprecision mediump float;\n">>;
        {gles, {3, 1}} ->
            <<"#version 310 es\nprecision mediump float;\n">>;
        {gles, {3, 0}} ->
            <<"#version 300 es\nprecision mediump float;\n">>;
        Other ->
            erlang:error({unsupported_gl_binding, Other})
    end.

frame_dt(LastNs, NowNs) ->
    Dt = (NowNs - LastNs) / 1.0e9,
    case Dt > ?MAX_DT of
        true ->
            ?MAX_DT;
        false when Dt < 0.0 ->
            0.0;
        false ->
            Dt
    end.

max_ticks() ->
    case os:getenv("BREAKOUT_MAX_TICKS") of
        false ->
            infinity;
        Value ->
            case string:to_integer(string:trim(Value)) of
                {Ticks, ""} when Ticks >= 0 ->
                    Ticks;
                _ ->
                    erlang:error({invalid_max_ticks, Value})
            end
    end.

clamp(Value, Min, _Max) when Value < Min ->
    Min;
clamp(Value, _Min, Max) when Value > Max ->
    Max;
clamp(Value, _Min, _Max) ->
    Value.
