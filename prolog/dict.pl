:- module(
  dict,
  [
    dict_delete_or_default/5, % +Key, +From, +Default, -Value, -To
    dict_get/3,               % ?Key, +Dict, -Value
    dict_get/4,               % +Key, +Dict, +Default, -Value
    dict_inc/2,               % +Key, +Dict
    dict_inc/3,               % +Key, +Dict, -Value
    dict_inc/4,               % +Key, +Dict, +Diff, -Value
    dict_key/2,               % +Dict, ?Key
    dict_pairs/2,             % ?Dict, ?Pairs
    dict_put/3,               % +From1, +From2, -To
    dict_put/4,               % +Key, +From, +Value, -To
    dict_select/3,            % +Select, +From, -To
    dict_tag/2,               % +Dict, ?Tag
    dict_tag/3,               % +From, ?Tag, -To
    merge_dicts/2,            % +Froms, -To
    merge_dicts/3,            % +NewFrom, +OldFrom, -To
    nb_increment_dict/2,      % +Dict, +Key
    nb_increment_dict/3       % +Dict, +Key, -Value
  ]
).

/** <module> Dictionary extension

@author Wouter Beek
@version 2017-2018
*/

:- use_module(library(apply)).
:- use_module(library(lists)).

:- use_module(library(pair_ext)).





%! dict_delete_or_default(+Key:atom, +From:dict, +Default:term, -Value:term, -To:dict) is det.
%
% Either delete the Value for Key from From resulting in To, or
% return the Default value and leave the dictionary unchanged.

dict_delete_or_default(Key, From, _, Value, To) :-
  del_dict(Key, From, Value, To), !.
dict_delete_or_default(_, Dict, Default, Default, Dict).



%! dict_get(?Key:atom, +Dict:dict, -Value:term) is nondet.

dict_get(Key, Dict, Value) :-
  get_dict(Key, Dict, Value).



%! dict_get(+Key:atom, +Dict:dict, +Default:term, -Value:term) is semidet.

dict_get(Key, Dict, _, Value) :-
  get_dict(Key, Dict, Value), !.
dict_get(_, _, Default, Default).



%! dict_inc(+Key:atom, +Dict:dict) is det.
%! dict_inc(+Key:atom, +Dict:dict, -Value:number) is det.
%! dict_inc(+Key:atom, +Dict:dict, +Diff:number, -Value:number) is det.

dict_inc(Key, Dict) :-
  dict_inc(Key, Dict, _).


dict_inc(Key, Dict, Value) :-
  dict_inc(Key, Dict, 1, Value).


dict_inc(Key, Dict, Diff, Value2) :-
  get_dict(Key, Dict, Value1),
  Value2 is Value1 + Diff,
  nb_set_dict(Key, Dict, Value2).



%! dict_key(+Dict:dict, +Key:atom) is semidet.
%! dict_key(+Dict:dict, -Key:atom) is nondet.

dict_key(Dict, Key) :-
  dict_get(Key, Dict, _).



%! dict_pairs(+Dict:dict, +Pairs:list(pair(atom,term))) is semidet.
%! dict_pairs(+Dict:dict, -Pairs:list(pair(atom,term))) is det.
%! dict_pairs(-Dict:dict, +Pairs:list(pair(atom,term))) is det.

dict_pairs(Dict, Pairs):-
  dict_pairs(Dict, _, Pairs).



%! dict_put(+From1:dict, +From2:dict, -To:dict) is det.

dict_put(From1, From2, To) :-
  To = From1.put(From2).



%! dict_put(+Key:atom, +From:dict, +Value:term, -To:dict) is det.

dict_put(Key, From, Value, To) :-
  put_dict(Key, From, Value, To).



%! dict_select(+Select:dict, +From:dict, -To:dict) is det.

dict_select(Select, From, To) :-
  select_dict(Select, From, To).



%! dict_tag(+Dict:dict, +Tag:atom) is semidet.
%! dict_tag(+Dict:dict, -Tag:atom) is det.

dict_tag(Dict, Tag) :-
  dict_pairs(Dict, Tag, _).


%! dict_tag(+From:dict, +Tag:atom, +To:dict) is semidet.
%! dict_tag(+From:dict, +Tag:atom, -To:dict) is det.
%
% Converts between dictionaries that differ only in their outer tag name.

dict_tag(From, Tag, To):-
  dict_pairs(From, _, Pairs),
  dict_pairs(To, Tag, Pairs).



%! merge_dicts(+Dicts:list(dict), -Dict:dict) is det.
%
% A string of applications of merge_dicts/3, where newer dictionaries
% appear later in `Dicts'.

merge_dicts([], []).
merge_dicts([H], H) :- !.
merge_dicts([H1,H2|T1], T2) :-
  merge_dicts(H2, H1, H12),
  merge_dicts([H12|T1], T2).


%! merge_dicts(+NewFrom:dict, +OldFrom:dict, -To:dict) is det.
%
% Merges two dictionaries into one new dictionary, similar to
% merge_options/3 from library(option).
%
% If NewFrom and OldFrom contain the same key then the value from
% NewFrom is used, unless both are dicts, in which case the dicts are
% merged recursively.  If NewFrom and OldFrom have a different tag,
% then the tag from NewFrom is used.

merge_dicts(NewFrom, OldFrom, To):-
  dict_pairs(NewFrom, Tag, NewPairs0),
  dict_pairs(OldFrom, _, OldPairs0),
  maplist(sort(1, @<), [OldPairs0,NewPairs0], [OldPairs,NewPairs]),
  merge_pairs(NewPairs, OldPairs, Pairs),
  dict_pairs(To, Tag, Pairs).



%! nb_increment_dict(+Dict:dict, +Key:atom) is det.
%! nb_increment_dict(+Dict:dict, +Key:atom, -Value:positive_integer) is det.

nb_increment_dict(Dict, Key) :-
  nb_increment_dict(Dict, Key, _).


nb_increment_dict(Dict, Key, N2) :-
  get_dict(Key, Dict, N1),
  N2 is N1 + 1,
  nb_set_dict(Key, Dict, N2).
