%%
%% %CopyrightBegin%
%%
%% Copyright Ericsson AB 2017. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%% 
%% %CopyrightEnd%
%%

-module(iovec_SUITE).

-export([all/0, suite/0]).

-export([integer_lists/1, binary_lists/1, empty_lists/1, empty_binary_lists/1,
         mixed_lists/1, improper_lists/1, illegal_lists/1, cons_bomb/1,
         iolist_to_iovec_idempotence/1, iolist_to_iovec_correctness/1]).

-include_lib("common_test/include/ct.hrl").

suite() ->
    [{ct_hooks,[ts_install_cth]},
     {timetrap, {minutes, 2}}].

all() ->
    [integer_lists, binary_lists, empty_lists, empty_binary_lists, mixed_lists,
     illegal_lists, improper_lists, cons_bomb, iolist_to_iovec_idempotence,
     iolist_to_iovec_correctness].

integer_lists(Config) when is_list(Config) ->
    Variations = gen_variations([I || I <- lists:seq(1, 255)]),

    equivalence_test(fun erlang:iolist_to_iovec/1, Variations),

    ok.

binary_lists(Config) when is_list(Config) ->
    Variations = gen_variations([<<I:8>> || I <- lists:seq(1, 255)]),
    equivalence_test(fun erlang:iolist_to_iovec/1, Variations),
    ok.

empty_lists(Config) when is_list(Config) ->
    Variations = gen_variations([[] || _ <- lists:seq(1, 256)]),
    equivalence_test(fun erlang:iolist_to_iovec/1, Variations),
    [] = erlang:iolist_to_iovec([]),
    ok.

empty_binary_lists(Config) when is_list(Config) ->
    Variations = gen_variations([<<>> || _ <- lists:seq(1, 8192)]),
    equivalence_test(fun erlang:iolist_to_iovec/1, Variations),
    [] = erlang:iolist_to_iovec(Variations),
    ok.

mixed_lists(Config) when is_list(Config) ->
    Variations = gen_variations([<<>>, lists:seq(1, 40), <<12, 45, 78>>]),
    equivalence_test(fun erlang:iolist_to_iovec/1, Variations),
    ok.

illegal_lists(Config) when is_list(Config) ->
    BitStrs = gen_variations(["gurka", <<1:1>>, "gaffel"]),
    BadInts = gen_variations(["gurka", 890, "gaffel"]),
    Atoms = gen_variations([gurka, "gaffel"]),
    BadTails = [["test" | 0], ["gurka", gaffel]],

    Variations =
        BitStrs ++ BadInts ++ Atoms ++ BadTails,

    illegality_test(fun erlang:iolist_to_iovec/1, Variations),

    ok.

improper_lists(Config) when is_list(Config) ->
    Variations = [
        [[[[1 | <<2>>] | <<3>>] | <<4>>] | <<5>>],
        [[<<"test">>, 3] | <<"improper tail">>],
        [1, 2, 3 | <<"improper tail">>]
    ],
    equivalence_test(fun erlang:iolist_to_iovec/1, Variations),
    ok.

cons_bomb(Config) when is_list(Config) ->
    IntBase = gen_variations([I || I <- lists:seq(1, 255)]),
    BinBase = gen_variations([<<I:8>> || I <- lists:seq(1, 255)]),
    MixBase = gen_variations([<<12, 45, 78>>, lists:seq(1, 255)]),

    Rounds =
        case system_mem_size() of
            Mem when Mem >= (16 bsl 30) -> 32;
            Mem when Mem >= (3 bsl 30) -> 28;
            _ -> 20
        end,

    Variations = gen_variations([IntBase, BinBase, MixBase], Rounds),
    equivalence_test(fun erlang:iolist_to_iovec/1, Variations),
    ok.

iolist_to_iovec_idempotence(Config) when is_list(Config) ->
    IntVariations = gen_variations([I || I <- lists:seq(1, 255)]),
    BinVariations = gen_variations([<<I:8>> || I <- lists:seq(1, 255)]),
    MixVariations = gen_variations([<<12, 45, 78>>, lists:seq(1, 255)]),

    Variations = [IntVariations, BinVariations, MixVariations],
    Optimized = erlang:iolist_to_iovec(Variations),

    true = Optimized =:= erlang:iolist_to_iovec(Optimized),
    ok.

iolist_to_iovec_correctness(Config) when is_list(Config) ->
    IntVariations = gen_variations([I || I <- lists:seq(1, 255)]),
    BinVariations = gen_variations([<<I:8>> || I <- lists:seq(1, 255)]),
    MixVariations = gen_variations([<<12, 45, 78>>, lists:seq(1, 255)]),

    Variations = [IntVariations, BinVariations, MixVariations],
    Optimized = erlang:iolist_to_iovec(Variations),

    true = is_iolist_equal(Optimized, Variations),
    ok.

illegality_test(Fun, Variations) ->
    [{'EXIT',{badarg, _}} = (catch Fun(Variation)) || Variation <- Variations].

equivalence_test(Fun, [Head | _] = Variations) ->
    Comparand = Fun(Head),
    [is_iolist_equal(Comparand, Fun(Variation)) || Variation <- Variations],
    ok.

is_iolist_equal(A, B) ->
    iolist_to_binary(A) =:= iolist_to_binary(B).

%% Generates a bunch of lists whose contents will be equal to Base repeated a
%% few times. The lists only differ by their structure, so their reduction to
%% a simpler format should yield the same result.
gen_variations(Base) ->
    gen_variations(Base, 16).
gen_variations(Base, N) ->
    [gen_flat_list(Base, N),
     gen_nested_list(Base, N),
     gen_nasty_list(Base, N)].

gen_flat_list(Base, N) ->
    lists:flatten(gen_nested_list(Base, N)).

gen_nested_list(Base, N) ->
    [Base || _ <- lists:seq(1, N)].

gen_nasty_list(Base, N) ->
    gen_nasty_list_1(gen_nested_list(Base, N), []).
gen_nasty_list_1([], Result) ->
    Result;
gen_nasty_list_1([Head | Base], Result) when is_list(Head) ->
    gen_nasty_list_1(Base, [[Result], [gen_nasty_list_1(Head, [])]]);
gen_nasty_list_1([Head | Base], Result) ->
    gen_nasty_list_1(Base, [[Result], [Head]]).

system_mem_size() ->
    application:ensure_all_started(os_mon),
    {Tot,_Used,_}  = memsup:get_memory_data(),
    Tot.
