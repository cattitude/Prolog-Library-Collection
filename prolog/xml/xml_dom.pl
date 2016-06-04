:- module(
  xml_dom,
  [
    atom_to_xml_dom/2,  % +Atom, -Dom
    atom_to_xml_dom/3,  % +Atom, -Dom, +Opts
    xml_clean_file/1,   % +File
    xml_clean_file/2,   % +File, +Opts
    xml_dom_as_atom//1, % +Dom
    xml_serve_dom/1     % +Dom
  ]
).

/** <module> XML DOM

@author Wouter Beek
@version 2015/07, 2015/10, 2016/03, 2016/05-2016/06
*/

:- use_module(library(http/html_write)).
:- use_module(library(http/http_path)).
:- use_module(library(http/http_request)).
:- use_module(library(memfile)).
:- use_module(library(option)).
:- use_module(library(os/file_ext)).
:- use_module(library(os/open_any2)).
:- use_module(library(semweb/rdf11), []).
:- use_module(library(sgml)).
:- use_module(library(sgml_write)).
:- use_module(library(yall)).





%! atom_to_xml_dom(+Atom, -Dom) is det.
%! atom_to_xml_dom(+Atom, -Dom, +Opts) is det.
%
% Uses option `dialect(xml)` unless option `dialect/1` is explicitly
% specified.  This allows the dialect to be set to `xmlns`.

atom_to_xml_dom(A, Dom) :-
  atom_to_xml_dom(A, Dom, []).


atom_to_xml_dom(A, Dom, Opts1) :-
  merge_options([dialect(xml)], Opts1, Opts2),
  setup_call_cleanup(
    atom_to_memory_file(A, Handle),
    setup_call_cleanup(
      open_memory_file(Handle, read, In),
      load_structure(In, Dom, Opts2),
      close(In)
    ),
    free_memory_file(Handle)
  ).



%! xml_clean_file(+File) is det.
%! xml_clean_file(+File, +Opts) is det.
%
% Inserts newlines in XML files that contain very long lines.
%
% Line feed is code 10.  Carriage return is code 13.

xml_clean_file(File) :-
  xml_clean_file(File, []).


xml_clean_file(File, Opts) :-
  thread_file(TmpFile),
  call_onto_stream(
    File,
    TmpFile,
    [In,MIn,MIn,Out,MOut,MOut]>>xml_clean_stream(In, Out),
    Opts
  ),
  rename_file(TmpFile, File).

xml_clean_stream(In, _) :-
  at_end_of_stream(In), !.
% Add newlines between elements.
xml_clean_stream(In, Out) :-
  peek_string(In, 2, "><"), !,
  get_char(In, '>'), get_char(In, '<'),
  put_char(Out, '>'), put_char(Out, '\n'), put_char(Out, '<'),
  xml_clean_stream(In, Out).
% Replace DOS newlines with Unix newlines.
xml_clean_stream(In, Out) :-
  peek_string(In, 2, "\r\n"), !,
  get_char(In, '\r'), get_char(In, '\n'),
  put_char(Out, '\n'),
  xml_clean_stream(In, Out).
xml_clean_stream(In, Out) :-
  get_code(In, C),
  put_code(Out, C),
  xml_clean_stream(In, Out).



%! xml_dom_as_atom(+Dom)// is det.
% Includes the given DOM inside the generated HTML page.
%
% DOM is either a list or compound term or an atom.

xml_dom_as_atom(Dom) -->
  {rdf11:in_xml_literal(xml, Dom, A)},
  html(\[A]).



%! xml_serve_dom(+Dom) is det.
% Serves the given XML DOM.

xml_serve_dom(Dom) :-
  rdf11:in_xml_literal(xml, Dom, A),
  % The User Agent needs to know the content type and encoding.
  % If the UTF-8 encoding is not given here explicitly,
  % Prolog throws an IO exception on `format(XML)`.
  format("Content-type: application/xml; charset=utf-8~n~n"),
  format(A).
