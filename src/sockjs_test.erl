-module(sockjs_test).
-export([start/0, dispatcher/0]).

start() ->
    Port = 8080,
    application:start(sockjs),
    application:start(cowboy),
    Dispatch = [{'_', [{'_', sockjs_cowboy_handler,
                        {fun handle/1, fun ws_handle/1}}]}],
    cowboy:start_listener(http, 100,
                          cowboy_tcp_transport, [{port,     Port}],
                          cowboy_http_protocol, [{dispatch, Dispatch}]),
    io:format("~nRunning on port ~p~n~n", [Port]),
    receive
        _ -> ok
    end.

%% --------------------------------------------------------------------------

handle(Req) ->
    {Path0, Req1} = cowboy_http_req:raw_path(Req),
    Path = clean_path(binary_to_list(Path0)),
    case sockjs_filters:handle_req(
           Req1, Path, sockjs_test:dispatcher()) of
        nomatch -> case Path of
                       "config.js" -> config_js(Req1);
                       _           -> static(Req1, Path)
                   end;
        Req2    -> Req2
    end.

ws_handle(Req) ->
    {Path0, Req1} = cowboy_http_req:raw_path(Req),
    Path = clean_path(binary_to_list(Path0)),
    {Receive, _, _, _} = sockjs_filters:dispatch('GET', Path,
                                                 sockjs_test:dispatcher()),
    {Receive, Req1}.

static(Req, Path) ->
    %% TODO unsafe
    LocalPath = filename:join([module_path(), "priv/www", Path]),
    case file:read_file(LocalPath) of
        {ok, Contents} ->
            {ok, Req1} = cowboy_http_req:reply(200, [], Contents, Req),
            Req1;
        {error, _} ->
            {ok, Req1} = cowboy_http_req:reply(404, [], "", Req),
            Req1
    end.

module_path() ->
    {file, Here} = code:is_loaded(?MODULE),
    filename:dirname(filename:dirname(Here)).

config_js(Req) ->
    %% TODO parse the file? Good luck, it's JS not JSON.
    {ok, Req1} = cowboy_http_req:reply(
                   200, [{<<"content-type">>, <<"application/javascript">>}],
                   "var client_opts = {\"url\":\"http://localhost:8080\",\"disabled_transports\":[],\"sockjs_opts\":{\"devel\":true}};", Req),
    Req1.

clean_path("/")         -> "index.html";
clean_path("/" ++ Path) -> Path.

%% --------------------------------------------------------------------------

dispatcher() ->
    [{echo,    fun test_echo/2},
     {close,   fun test_close/2},
     {amplify, fun test_amplify/2}].

test_echo(Conn, {recv, Data}) -> Conn:send(Data);
test_echo(_Conn, _)           -> ok.

test_close(Conn, _) ->
    Conn:close(3000, "Go away!").

test_amplify(Conn, {recv, Data}) ->
    N0 = list_to_integer(binary_to_list(Data)),
    N = if N0 > 0 andalso N0 < 19 -> N0;
           true                   -> 1
        end,
    Conn:send(list_to_binary(string:copies("x", round(math:pow(2, N)))));
test_amplify(_Conn, _) ->
    ok.
