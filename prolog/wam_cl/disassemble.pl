/*******************************************************************
 *
 * A Common Lisp compiler/interpretor, written in Prolog
 *
 * (xxxxx.pl)
 *
 *
 * Douglas'' Notes:
 *
 * (c) Douglas Miles, 2017
 *
 * The program is a *HUGE* common-lisp compiler/interpreter. 
 *
 *******************************************************************/
:- module(dasm, []).


cl_disassemble(function(Symbol), Code):- !, cl_disassemble((Symbol), Code).
cl_disassemble(Obj, Code):- get_opv(Obj,function,Obj2),!,cl_disassemble(Obj2, Code).
cl_disassemble(StringL,Code):- to_prolog_string_if_needed(StringL,String),!,cl_disassemble(String,Code).
cl_disassemble(Function, Code):- string(Function),downcase_atom(Function,DC),!,cl_disassemble(DC, Code).
cl_disassemble(Function, Prolog):- 
  writeln('#| DISASSEMBLY FOR':Function),
   make_holder(Holder),
   reassembed_clauses(Holder,Function),
  nb_holder_value(Holder,ListOut),
  Prolog = '$OBJ'(claz_prolog,ListOut),
  nop(ListOut==[]-> xlisting(Function) ; true),
  writeln('|#').

reassembed_clauses(Holder,Function):- 
   ignore(((
   (current_predicate(Module:Function/Arity),                                 
    functor(P,Function,Arity),print_reassembed_clause(Holder,Module,P))),
   !, % unless all?
   fail)).

clauses_related(Module,P,Module:P,B,PrintKeyRef):- clause(Module:P,B,PrintKeyRef).
clauses_related(W,P,H,B,PrintKeyRef):-
   H= W:lambda_def(_DefType,H1,H2,_Args,_Body),
   clause(H,B,PrintKeyRef),
  (related_functor(P,H1);related_functor(P,H2)).
clauses_related(_,P,H,B,PrintKeyRef):-
   H= wl:arglist_info(H1,H2,_,_,_),
   clause(H,B,PrintKeyRef),
  (related_functor(P,H1);related_functor(P,H2)).

related_functor(P,Q):- to_related_functor(P,PP),to_related_functor(Q,QQ),QQ=PP,!.
to_related_functor(P,_):- var(P),!,fail.
to_related_functor(P,P):- \+ compound(P),!.
to_related_functor(P,PP):- P=..[F,A],!,(to_related_functor(F,PP);to_related_functor(A,PP)).
to_related_functor(P,PP):- P=..[_,A,B|_Rest],(to_related_functor(A,PP);to_related_functor(B,PP)).

print_reassembed_clause(ExceptFor,Module,P):-
   \+ predicate_property(Module:P,foriegn),
   clauses_related(Module,P,H,B,PrintKeyRef),
   %\+ predicate_property(Module:P,imported_from(_)),
   PC = (H :- B),   
   nb_holder_value(ExceptFor,Printed),
   \+ member(PrintKeyRef,Printed),
   nb_holder_append(ExceptFor,PrintKeyRef),
   print_clause_plain(PC),
   ignore((sub_term(Sub,B),compound(Sub),functor(Sub,F,1),(atom_contains(F,addr);maybe_inline(Sub)),
           print_reassembed_clause(ExceptFor,Module,Sub),fail)).


make_pretty(I,O):- is_user_output,!,shrink_lisp_strings(I,O), pretty1(O),pretty2(O),pretty3(O).
make_pretty(I,O):- I=O, pretty1(O),pretty2(O),pretty3(O).

print_clause_plain(I):-
  current_prolog_flag(color_term, Was),
  make_pretty(I,O),
    setup_call_cleanup(set_prolog_flag(color_term, false),
     fmt9(O),
     set_prolog_flag(color_term, Was)).
  
% print_clause_plain(C):- portray_clause_w_vars(O).


may_debug_var(_,_,V):- nonvar(V),!.
may_debug_var(_,_,V):- variable_name(V,_),!.
may_debug_var(L,_,_):- upcase_atom(L,L),!.
may_debug_var(L,R,V):- atom(L),atom_concat('cl_',LL,L),may_debug_var(LL,R,V).
may_debug_var(L,R,V):- atomic_list_concat([_A1,A2,A3|AS],'_',L),atomic_list_concat([A2,A3|AS],'_',LL),may_debug_var(LL,R,V).
may_debug_var(L,R,V):- debug_var([L,R],V).

may_debug_var(_,V):- nonvar(V),!.
may_debug_var(_,V):- variable_name(V,_),!.
may_debug_var(R,V):- debug_var(R,V).

pretty1(H):- \+ compound(H),!.
pretty1(as_rest(Name, Rest, _)):- may_debug_var(Name,Rest).
pretty1(get_var(Env, Name, Val)):- may_debug_var('Env',Env),may_debug_var(Name,Val).
pretty1(set_var(Env,_Op, Name, Val)):- may_debug_var('Env',Env),may_debug_var(Name,Val).
pretty1(cl_slot_value(_Env, Name, Val)):- may_debug_var(slot,Name,Val).
pretty1(set_place(_Env, SETF, [Name|_], Val, _)):- is_place_write(SETF), atom(Name),var(Val),debug_var([Name,'_New'],Val).
pretty1(Env=[List|_]):- compound(List),var(Env),List=[H|_],compound(H),H=bv(_,_), may_debug_var('Env',Env),
  maplist(pretty1,List).
pretty1(Env=List):- compound(List),var(Env),List=[H|_],compound(H),H=bv(_,_), may_debug_var('Env',Env),
  maplist(pretty1,List).
pretty1(P):- P=..[_,_|List],append(_,[Name, Val|_],List),atom(Name),var(Val),may_debug_var(Name,Val).
pretty1(debug_var(R,V)):- may_debug_var(R,V).
pretty1(bv(R,V)):- may_debug_var(R,V).
pretty1(H):-H=..[_|ARGS],must_maplist_det(pretty1,ARGS).

pretty2(H):- \+ compound(H),!. % may_debug_var(F,'_Call',H).
pretty2(H):-  
 always((functor(H,F,A),
   H=..[F,P1|ARGS],   
   (A>1 -> may_debug_var(F,'_Param',P1) ; true),
   must_maplist_det(pretty2,[P1|ARGS]))),!. 

pretty3(H):-pretty4(H),pretty5(H).

pretty4(H):- \+ compound(H),!. % may_debug_var(F,'_Call',H).
pretty4(H):-  
 ignore(((functor(H,F,_),
  wl:init_args(N,F),integer(N),
   A is N + 1,   
   arg(A,H,R),may_debug_var('KeysNRest',R)))),
   H=..[F,P1|ARGS],  
   must_maplist_det(pretty4,[P1|ARGS]),!. 

pretty5(H):- \+ compound(H),!. % may_debug_var(F,'_Call',H).
pretty5([H | B]):- pretty5(H),pretty5(B),may_debug_var('CAR',H),may_debug_var('CDR',B).
pretty5(H):-  
 always((functor(H,F,A),
   H=..[F,P1|ARGS],   
   arg(A,H,R),may_debug_var(F,'_Ret',R),   
   nop(may_debug_var(F,'_Param',P1)),
   must_maplist_det(pretty5,[P1|ARGS]))),!. 


:- fixup_exports.

      
end_of_file.