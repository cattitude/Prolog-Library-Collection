:- encoding(utf8).
:- module(
  debug_ext,
  [
    dcg_debug/2,    % +Flag, :Dcg_0
    debug_call/2,   % +Flag, :Goal_0
    debug_dict/2,   % +Flag, +Dict
    debug_phrase/2, % +Flag, :Dcg_0
    format_debug/3, % +Flag, +Out, +Pattern
    format_debug/4, % +Flag, +Out, +Pattern, +Args
    indent_debug/3, % +Mode, +Flag, +Format
    indent_debug/4  % +Mode, +Flag, +Format, +Args
  ]
).
:- reexport(library(debug)).

/** <module> Debug extensions

@author Wouter Beek
@version 2017-2018
*/

:- use_module(library(dcg)).
:- use_module(library(error)).
:- use_module(library(pp)).

:- meta_predicate
    dcg_debug(+, //),
    debug_call(+, 0),
    debug_phrase(+, //).

:- thread_local
   debug_indent/1.

debug_indent(0).





%! dcg_debug(+Flag, :Dcg_0) is det.
%
% Write the first generation of Dcg_0 as a debug message under the
% given Flag.

dcg_debug(Flag, Dcg_0) :-
  debugging(Flag), !,
  once(string_phrase(Dcg_0, String)),
  debug(Flag, String, []).
dcg_debug(_, _).



%! debug_call(+Flag:compound, :Goal_0) is det.

debug_call(Flag, Goal_0) :-
  with_output_to(string(String), Goal_0),
  debug(Flag, "~s", [String]).



%! debug_dict(+Flag:compound, +Dict:dict) is det.

debug_dict(Flag, Dict) :-
  debugging(Flag), !,
  with_output_to(string(String), print_term(Dict)),
  debug(Flag, "~s", [String]).
debug_dict(_, _).



%! debug_phrase(+Flag:compound, :Dcg_0) is det.

debug_phrase(Flag, Dcg_0) :-
  dcg_with_output_to(string(String), Dcg_0),
  debug(Flag, "~s", [String]).



%! format_debug(+Flag:term, +Out:stream, +Pattern:string) is det.
%! format_debug(+Flag:term, +Out:stream, +Pattern:string, +Arguments:list(term)) is det.
%
% Allows a line of text to be written to an output stream and --
% optionally -- to a debug stream as well.
%
% Pattern and Arguments are used to compose a line of text.  The
% newline character is automatically added at the end.
%
% Debug information is displayed by calling `debug(Flag)` (see library
% debug).  Flag can be an atom or a compound term.

format_debug(Flag, Out, Pattern) :-
  format_debug(Flag, Out, Pattern, []).


format_debug(Flag, Out, Pattern, Args) :-
  string_concat(Pattern, "\n", PatternNewline),
  format(Out, PatternNewline, Args),
  debug(Flag, Pattern, Args).



%! indent_debug(+Mode:oneof([-1,0,1]), +Flag:compound, +Format:string) is det.
%! indent_debug(+Mode:oneof([-1,0,1]), +Flag:compound, +Format:string,
%!              +Args:list(term)) is det.

indent_debug(Mode, Flag, Format) :-
  indent_debug(Mode, Flag, Format, []).


indent_debug(Mode, Flag, Format, Args) :-
  debugging(Flag), !,
  must_be(oneof([-1,0,1]), Mode),
  (retract(debug_indent(N1)) -> N2 is max(0, N1 + Mode) ; N2 = Mode),
  assert(debug_indent(N2)),
  format(string(Msg1), Format, Args),
  (Mode =:= -1 -> N = N1 ; N = N2),
  dcg_with_output_to(string(Msg2), msg1(Mode, N, Msg1)),
  debug(Flag, "~s", [Msg2]).
indent_debug(_, _, _, _).

msg1(_, 0, Msg) --> !,
  atom(Msg).
msg1(Diff, 1, Msg) --> !,
  msg_diff1(Diff),
  "─",
  atom(Msg).
msg1(Diff, N1, Msg) -->
  ({N1 =:= 1} -> msg_diff2(Diff), "─" ; "│ "),
  {N2 is N1 - 1},
  msg1(Diff, N2, Msg).

msg_diff1(1) --> !, "┌".
msg_diff1(0) --> !, "─".
msg_diff1(-1) --> "└".

msg_diff2(1) --> !, "├".
msg_diff2(0) --> !, "└".
msg_diff2(-1) --> "└".
