:- encoding(utf8).
:- module(
  http_client2,
  [
    http_call/2,                   % +Uri, :Goal_1
    http_call/3,                   % +Uri, :Goal_1, +Options
    http_download/1,               % +Uri
    http_download/2,               % +Uri, ?File
    http_download/3,               % +Uri, ?File, +Options
    http_head2/2,                  % +Uri, +Options
    http_metadata_content_type/2,  % +Metas, -MediaType
    http_metadata_file_name/2,     % +Metas, -File
    http_metadata_final_uri/2,     % +Metas, -Uri
    http_metadata_last_modified/2, % +Uri, -Time
    http_metadata_link/3,          % +Metas, +Relation, -Uri
    http_metadata_status/2,        % +Metas, -Status
    http_open2/2,                  % +CurrentUri, -In
    http_open2/3,                  % +CurrentUri, -In, +Options
    http_sync/1,                   % +Uri
    http_sync/2,                   % +Uri, ?File
    http_sync/3,                   % +Uri, ?File, +Options
  % DEBUGGING
    curl/0,
    nocurl/0
  ]
).

/** <module> HTTP Client

@author Wouter Beek
@version 2017-2018
*/

:- use_module(library(apply)).
:- use_module(library(debug)).
:- use_module(library(error)).
:- use_module(library(http/http_client), []).
:- use_module(library(http/http_cookie), []).
:- use_module(library(http/http_header)).
:- use_module(library(http/http_json)).
:- use_module(library(http/http_path)).
:- use_module(library(http/json)).
:- use_module(library(lists)).
:- use_module(library(option)).
:- use_module(library(yall)).

:- use_module(library(dcg)).
:- use_module(library(dict)).
:- use_module(library(file_ext)).
:- use_module(library(http/http_generic)).
:- use_module(library(media_type)).
:- use_module(library(stream_ext)).
:- use_module(library(string_ext)).
:- use_module(library(uri_ext)).

:- use_module(http_open_cp, []).

:- meta_predicate
    http_call(+, 1),
    http_call(+, 1, +).

:- multifile
    http:post_data_hook/3,
    http:encoding_filter/3.

http:encoding_filter('x-gzip', In1, In2) :-
  http:encoding_filter(gzip, In1, In2).

:- public
    ssl_verify/5.

ssl_verify(_SSL, _ProblemCertificate, _AllCertificates, _FirstCertificate, _Error).





%! http_accept_value(+MediaTypes:list(compound), -Accept:atom) is det.
%
% Create an atomic HTTP Accept header value out of a given list of
% Media Types (from most to least acceptable).
%
% ```
% Accept = #( media-range [ accept-params ] )
% media-range = ( "*/*"
%               / ( type "/" "*" )
%               / ( type "/" subtype )
%               ) *( OWS ";" OWS parameter )
% parameter = token "=" ( token / quoted-string )
% accept-params  = weight *( accept-ext )
% weight = OWS ";" OWS "q=" qvalue
% accept-ext = OWS ";" OWS token [ "=" ( token / quoted-string ) ]
% ```

http_accept_value(MediaTypes, Accept) :-
  length(MediaTypes, NumMediaTypes),
  Interval is 1.0 / NumMediaTypes,
  atom_phrase(accept_(MediaTypes, Interval, Interval), Accept).

accept_([], _, _) --> !, "".
accept_([H|T], N1, Interval) -->
  media_type(H),
  weight_(N1),
  {N2 is N1 + Interval},
  ({T = []} -> "" ; ", "),
  accept_(T, N2, Interval).

weight_(N) -->
  {format(atom(Atom), ";q=~3f", [N])},
  atom(Atom).



%! http_call(+Uri:atom, :Goal_1) is nondet.
%! http_call(+Uri:atom, :Goal_1, +Options:list(compound)) is nondet.
%
% Uses URIs that appear with the ‘next’ keyword in HTTP Link headers
% to non-deterministically call Goal_1 for all subsequent input
% streams.
%
% Detects cycles in HTTP Link header referals, in which case the
% cyclic_link_header/1 is thrown.
%
% The following call is made: `call(Goal_1, In)'.

http_call(Uri, Goal_1) :-
  http_call(Uri, Goal_1, []).


http_call(FirstUri, Goal_1, Options1) :-
  State = state(FirstUri),
  % Non-deterministically enumerate over URIs that appear in HTTP Link
  % headers with the ‘next’ keyword.
  repeat,
  State = state(CurrentUri),
  merge_options([next(NextUri)], Options1, Options2),
  (   http_open2(CurrentUri, In, Options2)
  ->  (   % There is a next URI: keep the choicepoint open.
          atom(NextUri)
      ->  State = state(CurrentUri),
          % Detect directly cyclic `Link' headers.
          (   CurrentUri == NextUri
          ->  throw(error(http_error(cyclic_link_header,NextUri),http_call/3))
          ;   nb_setarg(1, State, NextUri)
          )
      ;   % There is no next URI: abandon choicepoint.
          !
      ),
      call_cleanup(
        call(Goal_1, In),
        close(In)
      )
  ;   !, fail
  ).



%! http_download(+Uri:atom) is det.
%! http_download(+Uri:atom, +File:atom) is det.
%! http_download(+Uri:atom, -File:atom) is det.
%! http_download(+Uri:atom, +File:atom, +Options:list(compound)) is det.
%! http_download(+Uri:atom, -File:atom, +Options:list(compound)) is det.

http_download(Uri) :-
  http_download(Uri, _).


http_download(Uri, File) :-
  http_download(Uri, File, []).


http_download(Uri, File, Options) :-
  ensure_uri_file_(Uri, File),
  http_download_(Uri, File, Options).



%! http_head2(+Uri:atom, +Options:list(compound)) is det.

http_head2(Uri, Options1) :-
  merge_options([method(head)], Options1, Options2),
  http_open2(Uri, In, Options2),
  close(In).



%! http_metadata_content_type(+Metas:list(dict), -MediaType:compound) is semidet.
%
% We cannot expect that an HTTP `Content-Type' header is present:
%
%   - Some HTTP replies have no content.
%
%   - Some non-empty HTTP replies omit the header (probably
%     incorrectly), e.g., `http://abs.270a.info/sparql'.
%
%   - Some Content-Type headers' values do not follow the grammar for
%     Media Types.

http_metadata_content_type(Metas, MediaType) :-
  Metas = [Meta|_],
  get_dict('content-type', Meta.headers, [ContentType|T]),
  assertion(T == []),
  http_parse_header_value(content_type, ContentType, MediaType).



%! http_metadata_file_name(+Metas:list(dict), -File:atom) is semidet.

http_metadata_file_name(Metas, File) :-
  Metas = [Meta|_],
  dict_get('content-disposition', Meta.headers, [ContentDisposition|T]),
  assertion(T == []),
  split_string(ContentDisposition, ";", " ", ["attachment"|Params]),
  member(Param, Params),
  split_string(Param, "=", "\"", ["filename",File0]), !,
  atom_string(File, File0).



%! http_metadata_final_uri(+Metas:list(dict), -Uri:atom) is det.

http_metadata_final_uri(Metas, Uri) :-
  Metas = [Meta|_],
  _{uri: Uri} :< Meta.



%! http_metadata_last_modified(+Uri:atom, -Time:float) is det.

http_metadata_last_modified(Uri, Time) :-
  http_open_cp:http_open(
    Uri,
    In,
    [header(last_modified,LastModified),method(head),status_code(Status)]
  ),
  Status =:= 200,
  call_cleanup(
    at_end_of_stream(In),
    close(In)
  ),
  parse_time(LastModified, Time).



%! http_metadata_link(+Metas:list(dict), +Relation:atom, -Uri:atom) is semidet.

http_metadata_link(Metas, Relation, Uri) :-
  [Meta|_] = Metas,
  dict_get(link, Meta.headers, Links),
  % This header may appear multiple times.
  atomic_list_concat(Links, ;, Link),
  atom_string(Relation, Relation0),
  split_string(Link, ",", " ", Comps),
  member(Comp, Comps),
  split_string(Comp, ";", "<> ", [Uri0|Params]),
  member(Param, Params),
  split_string(Param, "=", "\"", ["rel",Relation0]), !,
  atom_string(Uri, Uri0).



%! http_metadata_status(+Metas:list(dict), -Success:between(100,599)) is det.

http_metadata_status(Metas, Status) :-
  Metas = [Meta|_],
  Status = Meta.status.



%! http_open2(+CurrentUri:atom, -In:stream) is det.
%! http_open2(+CurrentUri:atom, -In:stream, +Options:list(compound)) is det.
%
% Alternative to http_open/3 in the SWI standard library with the
% following additons:
%
%   * Allows Prolog truth/falsity to be bound to HTTP status codes
%     (e.g., Prolog truth = HTTP status code 201 for creation
%     requests).  For HTTP status codes that bind to neither truth nor
%     falsity, an exception http_status/1 is thrown.
%
%   * If present, returns the URI that appears in the HTTP Link header
%     with the ‘next’ key.  These next URIs must be used in sequent
%     requests in order to retrieve a full result set.
%
%   * Returns full meta-data, including all HTTP headers.
%
%   * Emits detailed, cURL-like debug messages about sent requests and
%     received replies.
%
% @arg Meta A list of dictionaries, each of which describing an
%      HTTP(S) request/reply interaction as well metadata about the
%      stream.
%
% @arg Options The following options are supported:
%
%   * accept(+Accept:term)
%
%     Accept is either a registered file name extension, a Media Type
%     compound term, or a list of Media Type compounds.
%
%   * failure(+Status:between(400,599))
%
%     Status code that is mapped onto Prolog silent failure.  Default
%     is `400'.
%
%   * final_uri(-Uri:atom)
%
%   * metadata(-Metas:list(dict))
%
%   * number_of_hops(+positive_integer)
%
%     The maximum number of consecutive redirects that is followed.
%     The default is 5.
%
%   * number_of_retries(+positive_integer)
%
%     The maximum number of times the same HTTP request is retries upon
%     receiving an HTTP error code (i.e., HTTP status codes 400
%     through 599).  The default is 1.
%
%   * status(-between(100,599))
%
%     Returns the final status code.  When present, options failure/1
%     and success/1 are not processed.
%
%   * success(+Status:between(200,299))
%
%     Status code that is mapped onto Prolog success.  Default is
%     `200'.
%
%   * Other options are passed to http_open/3.

http_open2(CurrentUri, In) :-
  http_open2(CurrentUri, In, []).


http_open2(CurrentUri, In, Options1) :-
  % Allow the next/1 option to be instantiated later.
  ignore(option(next(NextUri), Options1)),
  % Allow the metadata/1 optiont to be instantiated later.
  ignore(option(metadata(Metas), Options1)),
  http_options_(CurrentUri, Options1, State, Options2),
  http_open2_(CurrentUri, In, State, Metas0, Options2),
  reverse(Metas0, Metas),
  % Instantiate the next/1 option.
  ignore(http_metadata_link(Metas, next, NextUri)),
  Metas = [Meta|_],
  _{status: Status, uri: FinalUri} :< Meta,
  ignore(option(final_uri(FinalUri), Options1)),
  (   option(status(Status), Options1)
  ->  true
  ;   http_status_(In, Status, FinalUri, Options1)
  ).

http_status_(In, Status, FinalUri, Options) :-
  option(failure(Failure), Options),
  option(success(Success), Options, 200), !,
  http_status(In, Status, FinalUri, Failure, Success).
http_status_(In, Status, FinalUri, Options) :-
  option(success(Success), Options),
  option(failure(Failure), Options, 400), !,
  http_status(In, Status, FinalUri, Failure, Success).
http_status_(_, _, _, _).

http_options_(Uri, Options1, State, Options3) :-
  (   select_option(accept(Accept), Options1, Options2)
  ->  http_open2_accept_(Accept, Atom)
  ;   Atom = '*',
      Options2 = Options1
  ),
  Options3 = [request_header('Accept'=Atom)|Options2],
  option(number_of_hops(MaxHops), Options3, 5),
  option(number_of_retries(MaxRetries), Options3, 1),
  State = _{
    maximum_number_of_hops: MaxHops,
    maximum_number_of_retries: MaxRetries,
    number_of_retries: 1,
    visited: [Uri]
  }.

http_open2_(Uri, In2, State1, [Meta|Metas], Options1) :-
  (   debugging(http(send_request)),
      option(post(RequestBody), Options1)
  ->  debug(http(send_request), "REQUEST BODY\n~w", [RequestBody])
  ;   true
  ),
  merge_options(
    [
      cert_verify_hook(cert_accept_any),
      raw_headers(HeaderLines),
      redirect(false),
      status_code(Status),
      timeout(60),
      version(Major-Minor)
    ],
    Options1,
    Options2
  ),
  get_time(Start),
  http_open_cp:http_open(Uri, In1, Options2),
  ignore(option(status_code(Status), Options2)),
  get_time(End),
  http_lines_pairs(HeaderLines, HeaderPairs),
  (   memberchk(location-[Location], HeaderPairs)
  ->  State2 = State1.put(_{location: Location})
  ;   State2 = State1
  ),
  dict_pairs(HeadersMeta, HeaderPairs),
  Meta = http{
    headers: HeadersMeta,
    status: Status,
    timestamp: Start-End,
    uri: Uri,
    version: version{major: Major, minor: Minor}
  },
  State3 = State2.put(_{meta: Meta}),
  % Print status codes and reply headers as debug messages.
  % Use curl/0 to show these debug messages.
  (   debugging(http(receive_reply))
  ->  debug(http(receive_reply), "", []),
      http_status_reason(Status, Reason),
      debug(http(receive_reply), "< ~d (~s)", [Status,Reason]),
      maplist(debug_header, HeaderPairs),
      debug(http(receive_reply), "", [])
  ;   true
  ),
  http_open2_(Uri, In1, Status, State3, In2, Metas, Options1).

debug_header(Key-Values) :-
  maplist(debug_header(Key), Values).

debug_header(Key, Value) :-
  debug(http(receive_reply), "< ~a: ~w", [Key,Value]).

% list of Media Types
http_open2_accept_(MediaTypes, Atom) :-
  is_list(MediaTypes), !,
  http_accept_value(MediaTypes, Atom).
% file name extension
http_open2_accept_(Ext, Atom) :-
  atom(Ext), !,
  (   media_type_extension(MediaType, Ext)
  ->  http_open2_accept_([MediaType], Atom)
  ;   existence_error(media_type_extension, Ext)
  ).
% Media Type
http_open2_accept_(MediaType, Atom) :-
  http_open2_accept_([MediaType], Atom).

% succes status code
http_open2_(Uri, In1, Status, State, In2, [], _) :-
  between(200, 299, Status), !,
  http_open2_success_(Uri, In1, State, In2).
% redirect status code
http_open2_(Uri1, In1, Status, State1, In2, Metas, Options) :-
  between(300, 399, Status), !,
  close(In1),
  _{location: Location, visited: Visited1} :< State1,
  uri_resolve(Location, Uri1, Uri2),
  Visited2 = [Uri2|Visited1],
  (   length(Visited2, NumVisited),
      _{maximum_number_of_hops: MaxHops} :< State1,
      NumVisited >= MaxHops
  ->  Metas = [],
      reverse(Visited2, Visited3),
      % Wait until redirect loops have reached the maximum number of
      % hops.  The same URI can sometimes be legitimately requested
      % more than once, e.g., without and with a cookie.
      (   memberchk(Uri2, Visited1)
      ->  throw(error(http_error(redirect_loop,Visited3),http_open2_/7))
      ;   throw(error(http_error(max_redirect,NumVisited,Visited3),http_open2_/7))
      )
  ;   State2 = State1.put(_{visited: Visited2}),
      http_open2_(Uri2, In2, State2, Metas, Options)
  ).
% authentication error status code
http_open2_(_, In, Status, _, In, [], _) :-
  Status =:= 401, !.
% non-authentication error status code
http_open2_(Uri, In1, Status, State1, In2, Metas, Options) :-
  between(400, 599, Status), !,
  _{
    maximum_number_of_retries: MaxRetries,
    number_of_retries: Retries1
  } :< State1,
  Retries2 is Retries1 + 1,
  (   Retries2 >= MaxRetries
  ->  In2 = In1,
      Metas = []
  ;   close(In1),
      State2 = State1.put(_{number_of_retries: Retries2}),
      http_open2_(Uri, In2, State2, Metas, Options)
  ).
% unrecognized status code
http_open2_(_, In, Status, _, _, [], _) :-
  close(In),
  domain_error(http_status, Status).

% Change the input stream encoding based on the value of the
% `Content-Type' header.
http_open2_success_(_, In, State, In) :-
  _{meta: Meta} :< State,
  http_metadata_content_type([Meta], _MediaType), !.
%  (   media_type_encoding(MediaType, Enc)
%  ->  recode_stream(In1, Enc, In2)
%  ;   In2 = In1
%  ).
% If there is no `Content-Type' header, then there MUST be no content
% either.
http_open2_success_(Uri, In, _, In) :-
  (   at_end_of_stream(In)
  ->  true
  ;   print_message(warning, error(http_error(no_content_type,Uri),http_open2_success_/4))
  ).

http_lines_pairs(Lines, GroupedPairs) :-
  findall(
    Key-Value,
    (
      member(Line, Lines),
      % HTTP header parsing may fail, e.g., due to obsolete line
      % folding (where one header is spread over multiple lines).
      phrase(http_parse_header_simple(Key, Value), Line)
    ),
    Pairs
  ),
  keysort(Pairs, SortedPairs),
  group_pairs_by_key(SortedPairs, GroupedPairs).

%! http_parse_header_simple(-Key:atom, -Value:atom)// is semidet.
%
% ```
% header-field = field-name ":" OWS field-value OWS
% field-name = token
% OWS = *( SP | HTAB )
% ```

http_parse_header_simple(Key, Value) -->
  string_without(":", KeyCodes),
  ":",
  {
    atom_codes(Key0, KeyCodes),
    downcase_atom(Key0, Key)
  },
  remainder_as_string(String0),
  {
    string_strip(String0, "\s\t", String),
    atom_string(Value, String)
  }, !.

http:post_data_hook(string(String), Out, HdrExtra) :-
  atom_string(Atom, String),
  http_header:http_post_data(atom(Atom), Out, HdrExtra).
http:post_data_hook(string(MediaType,String), Out, HdrExtra) :-
  atom_string(Atom, String),
  http_header:http_post_data(atom(MediaType,Atom), Out, HdrExtra).



%! http_status(+In:stream, +Status:between(100,599), FinalUri:atom,
%              ?Failure:between(400,599), ?Success:beteen(200,299)) is det.
%
% @arg Failure
%
%      If supplied, maps an HTTP code onto Prolog failure.
%
% @arg Success
%
%      If supplied, maps an HTTP code onto Prolog success.

http_status(In, Status, FinalUri, Failure, Success) :-
  must_be(http_status, Status),
  (   % HTTP failure codes.
      between(400, 599, Status)
  ->  (   number(Failure),
          Status =:= Failure
      ->  close(In),
          fail
      ;   http_status_error(In, Status, FinalUri)
      )
  ;   % HTTP success codes.  The asserion indicates that we do not
      % expect a 1xx or 3xx status code here.
      assertion(between(200, 299, Status))
  ->  (number(Success) -> Status =:= Success ; true)
  ).

http_status_error(In, Status, FinalUri) :-
  call_cleanup(
    read_string(In, 1 000, Content),
    close(In)
  ),
  throw(error(http_error(status,Status,Content,FinalUri),http_status_error/3)).



%! http_sync(+Uri:atom) is det.
%! http_sync(+Uri:atom, +File:atom) is det.
%! http_sync(+Uri:atom, -File:atom) is det.
%! http_sync(+Uri:atom, +File:atom, +Options:list(compound)) is det.
%! http_sync(+Uri:atom, -File:atom, +Options:list(compound)) is det.
%
% Like http_download/[1-3], but does not download File if it already
% exists.

http_sync(Uri) :-
  http_sync(Uri, _).


http_sync(Uri, File) :-
  http_sync(Uri, File, []).


http_sync(Uri, File, Options) :-
  ensure_uri_file_(Uri, File),
  (exists_file(File) -> true ; http_download_(Uri, File, Options)).





% DEBUGGING %

%! curl is det.
%
% Enable detailed, cURL-like debug messages.

curl :-
  debug(http(receive_reply)),
  debug(http(send_request)).



%! nocurl is det.
%
% Disable detailed, cURL-like debug messages.

nocurl :-
  nodebug(http(receive_reply)),
  nodebug(http(send_request)).





% GENERICS %

%! ensure_uri_file_(+Uri:atom, +File:atom) is det.
%! ensure_uri_file_(+Uri:atom, -File:atom) is det.

ensure_uri_file_(_, File) :-
  ground(File), !,
  must_be(atom, File).
ensure_uri_file_(Uri, File) :-
  uri_file_local(Uri, File).



%! http_download_(+Uri:atom, +File:atom, +Options:list(compound)) is det.

http_download_(Uri, File, Options) :-
  file_name_extension(File, tmp, TmpFile),
  write_to_file(TmpFile, http_download_stream_(Uri, Options), [type(binary)]),
  rename_file(TmpFile, File).

http_download_stream_(Uri, Options, Out) :-
  http_call(Uri, {Out}/[In]>>copy_stream_data(In, Out), Options).
