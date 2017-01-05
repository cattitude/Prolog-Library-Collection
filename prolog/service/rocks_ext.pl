:- module(
  rocks_ext,
  [
    call_on_rocks/3,   % +Alias, +Type, :Goal_1
    rocks_ls/0,
    rocks_ls/1,        % +PageOpts
    rocks_merge_set/5, % +Mode, +Key, +Left, +Right, -Result
    rocks_merge_sum/5, % +Mode, +Key, +Left, +Right, -Result
    rocks_open/2,      % +Alias, +Type
    rocks_pull/3,      % +Alias, -Key, -Val
    rocks_rm/1         % +Alias
  ]
).
:- reexport(library(rocksdb)).

/** <module> RocksDB extensions

@author Wouter Beek
@version 2016/08-2016/09, 2017/01
*/

:- use_module(library(apply)).
:- use_module(library(lists)).
:- use_module(library(ordsets)).
:- use_module(library(os/file_ext)).
:- use_module(library(pagination/cli_pagination)).
:- use_module(library(settings)).

:- meta_predicate
    call_on_rocks(+, +, 1).

:- setting(
     index_dir,
     atom,
     '~/Data/index/',
     "Directory in whose subdirectories RocksDB indices are stored."
   ).





%! call_on_rocks(+Alias, +Type, :Goal_1) is det.

call_on_rocks(Alias, Type, Goal_1) :-
  setup_call_cleanup(
    rocks_open(Alias, Type),
    call(Goal_1, Alias),
    rocks_close(Alias)
  ).

type_merge_value(int, rocks_merge_sum, int64).
type_merge_value(set(atom), rocks_merge_set, term).



%! rocks_ls is det.
%! rocks_ls(+PageOpts) is det.

rocks_ls :-
  rocks_ls(_{}).


rocks_ls(PageOpts) :-
  setting(index_dir, Dir),
  create_pagination(
    Subdir,
    directory_subdirectory(Dir, Subdir),
    PageOpts,
    Result
  ),
  cli_pagination_result(Result, pp_aliases).

pp_aliases(Aliases) :-
  maplist(writeln, Aliases).



%! rocks_merge_set(+Mode, +Key, +Left, +Right, -Result) is det.

rocks_merge_set(partial, _, X, Y, Z) :-
  ord_union(X, Y, Z).
rocks_merge_set(full, _, X, Y, Z) :-
  append([X|Y], XY),
  sort(XY, Z).



%! rocks_merge_sum(+Mode, +Key, +Left, +Right, -Result) is det.

rocks_merge_sum(partial, _, X, Y, Z) :-
  Z is X + Y.
rocks_merge_sum(full, _, Initial, Additions, Sum) :-
  sum_list([Initial|Additions], Sum).



%! rocks_open(+Alias, +Type) is det.

rocks_open(Alias, Type) :-
  rocks_dir(Alias, Dir),
  once(type_merge_value(Type, Merge_5, Val)),
  rocks_open(Dir, _, [alias(Alias),key(atom),merge(Merge_5),value(Val)]).



%! rocks_pull(+Alias, -Key, -Val) is nondet.

rocks_pull(Alias, Key, Val) :-
  rocks_enum(Alias, Key, Val),
  rocks_delete(Alias, Key).



%! rocks_rm(+Alias) is det.

rocks_rm(Alias) :-
  % Make sure the RocksDB index is closed before its files are
  % removed.
  catch(rocks_close(Alias), _, true),
  rocks_dir(Alias, Dir),
  delete_directory_and_contents_msg(Dir).





% HELPERS %

%! rocks_dir(+Alias, -Dir) is det.

rocks_dir(Alias, Subdir) :-
  setting(index_dir, Dir),
  directory_file_path(Dir, Alias, Subdir),
  create_directory(Subdir).
