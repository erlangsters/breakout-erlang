%
% THIS IS AI-GENERATED CODE USED AS A PLACEHOLDER.
%
-module(breakout).
-export([start/0]).

-include_lib("gl/include/gl.hrl").
-include_lib("glfw/include/glfw.hrl").

%% Game constants
-define(WIDTH, 800).
-define(HEIGHT, 600).
-define(PADDLE_WIDTH, 100).
-define(PADDLE_HEIGHT, 20).
-define(BALL_SIZE, 15).
-define(BRICK_WIDTH, 80).
-define(BRICK_HEIGHT, 30).
-define(BRICK_ROWS, 5).
-define(BRICK_COLS, 10).

%% Shaders
-define(VERTEX_SHADER_SRC, """
#version 460 core
layout(location = 0) in vec2 aPos;
uniform mat4 projection;
uniform mat4 model;
void main() {
    gl_Position = projection * model * vec4(aPos, 0.0, 1.0);
}
""").

-define(FRAGMENT_SHADER_SRC, """
#version 460 core
out vec4 FragColor;
uniform vec3 color;
void main() {
    FragColor = vec4(color, 1.0);
}
""").

%% Game state record
-record(game_state, {
    window,
    shader_program,
    vao,
    vbo,
    projection,
    paddle_pos = 0.0,
    ball_pos = {0.0, 0.0},
    ball_vel = {0.0, 0.0},
    bricks = [],
    lives = 3,
    score = 0,
    game_over = false,
    game_won = false
}).

start() ->
    %% Initialize GLFW
    glfw:init(),
    {ok, Window} = glfw:create_window(?WIDTH, ?HEIGHT, "Breakout"),

    %% Set up EGL
    Display = egl:get_display(default_display),
    {ok, _} = egl:initialize(Display),
    egl:bind_api(opengl_api),

    ConfigAttribs = [
        {surface_type, [window_bit]},
        {renderable_type, [opengl_bit]}
    ],
    {ok, [Config|_]} = egl:choose_config(Display, ConfigAttribs),

    ContextAttribs = [{context_major_version, 3}],
    {ok, Context} = egl:create_context(Display, Config, no_context, ContextAttribs),

    WindowHandle = glfw:window_egl_handle(Window),
    {ok, Surface} = egl:create_window_surface(Display, Config, WindowHandle, []),
    ok = egl:make_current(Display, Surface, Surface, Context),

    %% Set up OpenGL
    gl:viewport(0, 0, ?WIDTH, ?HEIGHT),

    %% Compile shaders
    {ok, VertexShader} = gl:create_shader(vertex_shader),
    gl:shader_source(VertexShader, [?VERTEX_SHADER_SRC]),
    gl:compile_shader(VertexShader),

    {ok, FragmentShader} = gl:create_shader(fragment_shader),
    gl:shader_source(FragmentShader, [?FRAGMENT_SHADER_SRC]),
    gl:compile_shader(FragmentShader),

    {ok, ShaderProgram} = gl:create_program(),
    gl:attach_shader(ShaderProgram, VertexShader),
    gl:attach_shader(ShaderProgram, FragmentShader),
    gl:link_program(ShaderProgram),

    gl:delete_shader(VertexShader),
    gl:delete_shader(FragmentShader),

    %% Set up vertex data
    {ok, [Vao]} = gl:gen_vertex_arrays(1),
    {ok, [Vbo]} = gl:gen_buffers(1),

    gl:bind_vertex_array(Vao),
    gl:bind_buffer(array_buffer, Vbo),

    %% Simple quad vertices (x, y)
    Vertices = [
        -0.5, -0.5,
         0.5, -0.5,
         0.5,  0.5,
        -0.5,  0.5
    ],
    VerticesBin = << <<X:32/float-little>> || X <- Vertices >>,
    gl:buffer_data(array_buffer, length(Vertices) * 4, VerticesBin, static_draw),

    gl:vertex_attrib_pointer(0, 2, float, false, 2 * 4, 0),
    gl:enable_vertex_attrib_array(0),

    gl:bind_buffer(array_buffer, 0),
    gl:bind_vertex_array(0),

    %% Create projection matrix
    Projection = create_ortho_matrix(0.0, ?WIDTH, ?HEIGHT, 0.0, -1.0, 1.0),

    %% Initialize game state
    InitialState = #game_state{
        window = Window,
        shader_program = ShaderProgram,
        vao = Vao,
        vbo = Vbo,
        projection = Projection,
        ball_pos = {?WIDTH / 2, ?HEIGHT / 2},
        ball_vel = {200.0, -200.0},
        bricks = generate_bricks()
    },

    %% Set up input handlers
    glfw:set_key_handler(Window, self()),

    %% Start game loop
    game_loop(Display, Surface, InitialState),

    %% Clean up
    glfw:destroy_window(Window),
    glfw:terminate(),
    ok.

game_loop(Display, Surface, State) ->
    case glfw:window_should_close(State#game_state.window) of
        true -> ok;
        false ->
            %% Process input
            handle_input(State),

            %% Update game state
            NewState = update_game(State),

            %% Render
            render_game(NewState),
            egl:swap_buffers(Display, Surface),

            %% Handle events
            glfw:poll_events(),
            handle_events(State#game_state.window),

            %% Continue loop
            timer:sleep(16),  % ~60 FPS
            game_loop(Display, Surface, NewState)
    end.

handle_input(State) ->
    Window = State#game_state.window,
    case glfw:get_key(Window, ?GLFW_KEY_LEFT) of
        ?GLFW_PRESS ->
            NewPos = max(State#game_state.paddle_pos - 10.0, 0.0),
            State#game_state{paddle_pos = NewPos};
        _ ->
            case glfw:get_key(Window, ?GLFW_KEY_RIGHT) of
                ?GLFW_PRESS ->
                    NewPos = min(State#game_state.paddle_pos + 10.0,
                                ?WIDTH - ?PADDLE_WIDTH),
                    State#game_state{paddle_pos = NewPos};
                _ -> State
            end
    end.

update_game(State) when State#game_state.game_over; State#game_state.game_won ->
    State;
update_game(State) ->
    {BallX, BallY} = State#game_state.ball_pos,
    {VelX, VelY} = State#game_state.ball_vel,

    %% Update ball position
    NewBallX = BallX + VelX * 0.016,  % 16ms frame time
    NewBallY = BallY + VelY * 0.016,

    %% Check collisions with walls
    {NewVelX, NewVelY} = case {NewBallX, NewBallY} of
        {X, _} when X < 0 -> {-VelX, VelY};
        {X, _} when X > ?WIDTH - ?BALL_SIZE -> {-VelX, VelY};
        {_, Y} when Y < 0 -> {VelX, -VelY};
        {_, Y} when Y > ?HEIGHT ->
            %% Ball fell out of screen
            NewLives = State#game_state.lives - 1,
            case NewLives of
                0 -> State#game_state{game_over = true};
                _ -> State#game_state{
                    ball_pos = {?WIDTH / 2, ?HEIGHT / 2},
                    ball_vel = {200.0, -200.0},
                    lives = NewLives
                }
            end;
        _ -> {VelX, VelY}
    end,

    %% Check collision with paddle
    PaddleLeft = State#game_state.paddle_pos,
    PaddleRight = PaddleLeft + ?PADDLE_WIDTH,
    PaddleTop = ?HEIGHT - ?PADDLE_HEIGHT,

    case NewBallY + ?BALL_SIZE >= PaddleTop andalso
         NewBallX + ?BALL_SIZE >= PaddleLeft andalso
         NewBallX <= PaddleRight of
        true ->
            %% Calculate reflection angle based on where ball hits paddle
            HitPos = (NewBallX + ?BALL_SIZE/2 - PaddleLeft) / ?PADDLE_WIDTH,
            Angle = (HitPos - 0.5) * 1.5,  % -0.75 to 0.75 radians
            Speed = math:sqrt(VelX*VelX + VelY*VelY),
            NewVelX2 = Speed * math:sin(Angle),
            NewVelY2 = -Speed * math:cos(Angle),
            {NewVelX3, NewVelY3} = {NewVelX2, NewVelY2};
        false ->
            {NewVelX3, NewVelY3} = {NewVelX, NewVelY}
    end,

    %% Check collision with bricks
    {NewBricks, NewScore, {FinalVelX, FinalVelY}} =
        check_brick_collisions(State#game_state.bricks,
                              State#game_state.score,
                              {NewBallX, NewBallY},
                              {NewVelX3, NewVelY3}),

    %% Check if all bricks are destroyed
    GameWon = NewBricks =:= [],

    State#game_state{
        ball_pos = {NewBallX, NewBallY},
        ball_vel = {FinalVelX, FinalVelY},
        bricks = NewBricks,
        score = NewScore,
        game_won = GameWon
    }.

check_brick_collisions(Bricks, Score, BallPos, BallVel) ->
    {BX, BY} = BallPos,
    {VX, VY} = BallVel,
    check_brick_collisions(Bricks, Score, BallPos, BallVel, [], 0).

check_brick_collisions([], Score, _, Vel, NewBricks, Hits) ->
    {lists:reverse(NewBricks), Score, Vel};
check_brick_collisions([{X, Y, Active}|Rest], Score, {BX, BY}, {VX, VY}, Acc, Hits) ->
    case Active andalso
         BX + ?BALL_SIZE >= X andalso BX <= X + ?BRICK_WIDTH andalso
         BY + ?BALL_SIZE >= Y andalso BY <= Y + ?BRICK_HEIGHT of
        true ->
            %% Collision detected
            %% Simple reflection - reverse Y velocity
            check_brick_collisions(Rest, Score + 10, {BX, BY}, {VX, -VY},
                                 [{X, Y, false}|Acc], Hits + 1);
        false ->
            check_brick_collisions(Rest, Score, {BX, BY}, {VX, VY},
                                 [{X, Y, Active}|Acc], Hits)
    end.

render_game(State) ->
    gl:clear_color(0.0, 0.0, 0.0, 1.0),
    gl:clear([color_buffer_bit]),

    gl:use_program(State#game_state.shader_program),
    gl:uniform_matrix4fv(gl:get_uniform_location(State#game_state.shader_program, "projection"),
                        1, false, State#game_state.projection),

    gl:bind_vertex_array(State#game_state.vao),

    %% Draw paddle
    Model = create_model_matrix(State#game_state.paddle_pos,
                              ?HEIGHT - ?PADDLE_HEIGHT,
                              ?PADDLE_WIDTH, ?PADDLE_HEIGHT),
    gl:uniform_matrix4fv(gl:get_uniform_location(State#game_state.shader_program, "model"),
                        1, false, Model),
    gl:uniform3f(gl:get_uniform_location(State#game_state.shader_program, "color"),
                1.0, 1.0, 1.0),
    gl:draw_arrays(triangle_fan, 0, 4),

    %% Draw ball
    {BallX, BallY} = State#game_state.ball_pos,
    ModelBall = create_model_matrix(BallX, BallY, ?BALL_SIZE, ?BALL_SIZE),
    gl:uniform_matrix4fv(gl:get_uniform_location(State#game_state.shader_program, "model"),
                        1, false, ModelBall),
    gl:uniform3f(gl:get_uniform_location(State#game_state.shader_program, "color"),
                1.0, 0.0, 0.0),
    gl:draw_arrays(triangle_fan, 0, 4),

    %% Draw bricks
    lists:foreach(fun({X, Y, Active}) ->
        case Active of
            true ->
                ModelBrick = create_model_matrix(X, Y, ?BRICK_WIDTH, ?BRICK_HEIGHT),
                gl:uniform_matrix4fv(gl:get_uniform_location(State#game_state.shader_program, "model"),
                                    1, false, ModelBrick),
                gl:uniform3f(gl:get_uniform_location(State#game_state.shader_program, "color"),
                            0.0, 0.0, 1.0),
                gl:draw_arrays(triangle_fan, 0, 4);
            false -> ok
        end
    end, State#game_state.bricks),

    %% Draw game over or win message
    if
        State#game_state.game_over ->
            %% Would need text rendering for proper message
            ok;
        State#game_state.game_won ->
            %% Would need text rendering for proper message
            ok;
        true -> ok
    end,

    gl:bind_vertex_array(0).

%% Helper functions
generate_bricks() ->
    Padding = 5,
    OffsetTop = 50,
    OffsetLeft = (?WIDTH - (?BRICK_COLS * (?BRICK_WIDTH + Padding))) / 2,

    [
        {OffsetLeft + (Col * (?BRICK_WIDTH + Padding)),
         OffsetTop + (Row * (?BRICK_HEIGHT + Padding)),
         true}
        || Row <- lists:seq(0, ?BRICK_ROWS-1),
           Col <- lists:seq(0, ?BRICK_COLS-1)
    ].

create_model_matrix(X, Y, Width, Height) ->
    [
        Width, 0.0, 0.0, X + Width/2,
        0.0, Height, 0.0, Y + Height/2,
        0.0, 0.0, 1.0, 0.0,
        0.0, 0.0, 0.0, 1.0
    ].

create_ortho_matrix(Left, Right, Bottom, Top, Near, Far) ->
    [
        2.0/(Right-Left), 0.0, 0.0, -(Right+Left)/(Right-Left),
        0.0, 2.0/(Top-Bottom), 0.0, -(Top+Bottom)/(Top-Bottom),
        0.0, 0.0, -2.0/(Far-Near), -(Far+Near)/(Far-Near),
        0.0, 0.0, 0.0, 1.0
    ].

handle_events(Window) ->
    receive
        #glfw_key{window=Window, key=?GLFW_KEY_ESCAPE, action=?GLFW_PRESS} ->
            glfw:set_window_should_close(Window, true);
        _ ->
            ok
    after 0 ->
        ok
    end.
