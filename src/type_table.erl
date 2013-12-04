-module(type_table).
-export([build/1, check_types/1]).

-define(BASE_TYPES, ["char", "int", "float", "double", "void"]).
-define(SPECIFIER, ["signed", "unsigned", "short", "long"]).
-define(CLANG_BUILTINS, ["__int128_t", "__builtin_va_list", "__uint128_t"]).


build(Dicts) ->
    {Functions, Typedefs, Structs} = Dicts,
    Empty_Tables = {dict:new(), dict:new()}, % { Types, Symbols }
    Tables_With_Functions = build_entries(
			      Empty_Tables,
			      fun build_function_entries/4,
			      Functions,
			      dict:fetch_keys(Functions),
			      Dicts),
    Tables_With_TypeDefs = build_entries(
      Tables_With_Functions,
      fun build_typedef_entries/4,
      Typedefs,
      dict:fetch_keys(Typedefs),
      Dicts),
		{Types, Symbols} = build_entries(
      Tables_With_TypeDefs,
      fun build_struct_entries/4,
      Structs,
      dict:fetch_keys(Structs),
      Dicts),
		{fill_type_table(Types), Symbols}.

check_types(_) -> 
    %% check if every type is resolvable to a base type
    ok.

fill_type_table(Types) ->
	fill_type_table(Types, dict:fetch_keys(Types)).

fill_type_table(Types, []) -> Types;
fill_type_table(Types, [Type|TypeNames]) ->
	[{Kind, [H|T]}] = dict:fetch(Type, Types),
	case Kind of
		base -> fill_type_table(Types, TypeNames);
		struct -> fill_type_table(Types, TypeNames);
		typedef -> fill_type_table(Types, TypeNames);
		_ ->
			case (H=:="*") orelse string:str(H, "[")>0 of
				true ->
					[P|Token] = lists:reverse(string:tokens(Type, " ")),
					NewP = string:sub_string(P, length(H)+1),
					NType = string:strip(string:join(lists:reverse(Token)++[NewP], " ")),
					case dict:is_key(NType, Types) of 
						true -> fill_type_table(Types, TypeNames);
						false -> fill_type_table(dict:append(NType, {Kind, T}, Types), [NType|TypeNames])
					end;
				false -> fill_type_table(Types, TypeNames)
			end
	end.


build_entries(Tables, _, _, [], _) -> Tables;
build_entries(Tables, Builder, Dict, [H|T], Dicts) ->
    [Data] = dict:fetch(H, Dict),
    Tables_With_New_Entry = Builder(Tables, H, Data, Dict),
    build_entries(Tables_With_New_Entry, Builder, Dict, T, Dicts).

build_function_entries({Types, Symbols}, Name, Data, Dicts) ->
    {ReturnType, ArgumentList} = Data,
    Types_With_Return = build_type_entry(Types, Dicts, ReturnType),
    Symbol_With_Return = build_symbol_entry(Symbols, Name, {return, ReturnType}), 
    build_arguments(
      {Types_With_Return, Symbol_With_Return},
      Dicts,
      Name,
      ArgumentList).

build_arguments(Tables, Dicts, FName, Args) -> build_arguments(Tables, Dicts, FName, 0, Args).

build_arguments(Tables, _, _, _, []) -> Tables;
build_arguments({Types, Symbols}, Dicts, FunctionName, Pos, [Arg|T]) ->
    {_, ArgType} = Arg,
    Types_With_Arg = build_type_entry(Types, Dicts, ArgType),
    Symbol_With_Arg = build_symbol_entry(Symbols, FunctionName, {argument, integer_to_list(Pos), ArgType, input}),
    build_arguments({Types_With_Arg, Symbol_With_Arg}, Dicts, FunctionName, Pos+1, T).

build_typedef_entries({Types, Symbols}, Alias, Type, Dicts) ->
    case lists:member(Alias, ?CLANG_BUILTINS) of
	true -> {Types, Symbols};
	false ->
	    NTypes = build_type_entry(Types, Dicts, Type),
	    {dict:append(Alias, {typedef, Type}, dict:erase(Alias, NTypes)), Symbols}
    end.

build_struct_entries({Types, Symbols}, Alias, _, Dict) ->
	[Members] =  dict:fetch(Alias, Dict),
	{dict:append(Alias, {struct, build_fields(Members,[])}, Types), Symbols}.

build_fields([], Fields) -> Fields;
build_fields([{Name, Type}|T], Fields) ->
	build_fields(T, [{field,Name, Type}|Fields]).

count_in_list(L, E) ->
    count_in_list(L,E,0).

count_in_list([], _, Acc) -> Acc;
count_in_list([H|T], E, Acc) ->
    case H=:=E of
	true -> count_in_list(T, E, Acc+1);
	false -> count_in_list(T, E, Acc)
    end.


simplify_specifiers(Specifiers) ->
    case count_in_list(Specifiers, "long") of
	0 ->
	    LSpec = case lists:member("short", Specifiers) of
			true -> ["short"];
			false -> ["none"]
		    end;
	1 -> LSpec = ["long"];
	_ -> LSpec = ["longlong"]
    end,
    case count_in_list(Specifiers, "unsigned") of
	0 -> ["signed"|LSpec];
	_ -> ["unsigned"|LSpec]
    end.


parse_type(Token, Dicts) ->
    parse_type(Token, Dicts, [], none).

parse_type([], Dicts, TypeDef, none) -> parse_type(["int"], Dicts, TypeDef, none);
parse_type([], _, TypeDef, Kind) -> {TypeDef, Kind};
parse_type([E|T], Dicts, TypeDef, Kind) ->
    case E of
	%% special cases
		"struct" ->
			[StructName|TT] = T,
			parse_type(TT, Dicts, [StructName|TypeDef], userdef);
	%% 		"union" ->
	%% 			io:format("TODO Parse Union ~n");
	_ ->
	    %% simple type
	    case lists:member(E, ?BASE_TYPES) of
		true -> parse_type(T, Dicts, [E|simplify_specifiers(TypeDef)], base);
		false -> 
		    case lists:member(E, ?SPECIFIER) of
			true -> parse_type(T, Dicts, [E|TypeDef], none);
			false -> 
			    case ((E=:="*") or lists:member($[, E)) of
				true ->
				    case Kind of
					none -> parse_type(["int"|[E|T]], Dicts, TypeDef, base);
					_ -> parse_type(T, Dicts, [E|TypeDef], Kind)
				    end;
				false ->
				    %% user defined type
				    parse_type(T, Dicts, [E|TypeDef], userdef)
			    end
		    end
	    end
    end.

type_extend(Type) ->
	R = type_extend(Type, []),
	R.

type_extend([], Acc) -> Acc;
type_extend([H|T], Acc) ->
	case [H] of
		"*" -> type_extend(T, Acc++" * ");
		"[" -> type_extend(T, Acc++" [");
		C -> type_extend(T, Acc++C)
	end.


build_type_entry(TypeTable, Dicts, Type) ->
    case dict:is_key(Type, TypeTable) of
	true -> TypeTable;
	false->
	    case parse_type(string:tokens(type_extend(Type), " "), Dicts) of
	    %%case parse_type(string:tokens(Type, " "), Dicts) of
		{Def, base} ->
		    %% io:format("~p -> ~p base~n", [Type, Def]),
		    dict:append(Type, {base, Def}, TypeTable);
		{Def, userdef} ->
		    %% io:format("~p -> ~p userdef~n", [Type, Def]),
		    dict:append(Type, {userdef, Def}, TypeTable);
		_ ->
		    TypeTable
	    end
    end.

build_symbol_entry(SymbolTable, Name, Data) ->
    dict:append(Name, Data, SymbolTable).

