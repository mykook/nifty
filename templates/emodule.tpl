-module({{module}}).
-export([{% with fn=functions|fetch_keys %}{% for name in fn %}
	{{name}}/{{ functions|fetch:name|getNth:2|length }},{% endfor %}{% endwith %}
	get_types/0
	]).

-define(TYPES, {{types}}).

-on_load(init/0).

init() ->
	ok = erlang:load_nif("{{module}}_nif", 0).

{% with fn=functions|fetch_keys %}{% for name in fn %}
{{name}}({% with arguments=symbols|fetch:name %}{% for argument in arguments %}{% if argument|is_argument %}_{% if not forloop.last %},{%endif%}{% endif %}{% endfor %}{% endwith %}) ->
	exit(nif_library_not_loaded).
{% endfor %}{% endwith %}

%%% defines
{% with type_keys=types|fetch_keys %}{% for type in type_keys %}{% with kind=types|fetch:type|getNth:1 %}{% if kind=="struct" %}
-record({{type}}, {
	{% with fields=types|fetch:type|getNth:2|reversed %}{% for _, name, t in fields %}{{name}}{% if not forloop.last %},{% endif %}{% endfor %}{% endwith %}
	}).
{% endif %}{% endwith%}{% endfor %}{% endwith %}

%%% static
get_types() -> ?TYPES.
