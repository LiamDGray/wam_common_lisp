/*******************************************************************
 *
 * A Common Lisp compiler/interpretor, written in Prolog
 *
 * (lisp_compiler.pl)
 *
 *
 * Douglas'' Notes:
 *
 * (c) Douglas Miles, 2017
 *
 * The program is a *HUGE* common-lisp compiler/interpreter. It is written for YAP/SWI-Prolog (YAP 4x faster).
 *
 * Changes since 2001:
 *
 *  ..............................
 *
 *
 * Neil''s Notes:
 *
 * (c) Neil Smith, 2001
 *
 * This program, and its associated support files, forms a compiler
 * for a subset of the language LISP.  It supports a few simple
 * built-in procedures, listed below.  It also supports both special
 * and lexical variables, and higher-order functions and lexical
 * closures.
 *
 * This compiler was written in LPA Prolog v3.6 under MS Windows.
 * It should run under other Prologs without too much conversion needed,
 * but note the required library modules.
 *
 *
 * Special forms
 *
 * [] and nil are treated as special forms, evaluating to [], and treated as 'false'
 * t is a special form, evaluating to t, and treated as 'true'
 * if, cond
 * progn (and implicit progn in defun and let bodies)
 * quote
 * let
 * setq
 * function
 * lambda
 * defvar, defparameter (both with and without initial values)
 *
 * Built-in procedures (defined in builtin_lisp_functions.pl)
 *
 * cons, first, rest, null
 * eq, equalp
 * plus, minus, times, divide
 * lisp_not, or, and
 * lisp_apply
 *
 * Other procedures are defined in lisp_library.pl
 *
 *******************************************************************/
:- module(comp, []).
:- set_module(class(library)).
:- include('header.pro').
/*******************************************************************
 *
 * Example definitions:
 * second(l) <<== first(rest(l)).
 * list_3(a, b, c) <<== cons(a, cons(b, cons(c, nil))).
 *
 * Example use:
 * ?| - lisp_call([second,[quote, [a,b,c]]], Result).
 * Result = b
 *
 * ?| - second([a,b,c], Result).
 * Result = b
 *
 * ?| - lisp_call([list_3, tom, dick, harry], Result).
 * Result = [tom, dick, harry]
 *
 * ?| - list_3(tom, dick, harry, Result).
 * Result = [tom, dick, harry]
 *
 *******************************************************************/
:- set_module(class(library)).
:- ensure_loaded(utils_for_swi).

:- style_check.


% :- ensure_loaded(builtin_lisp_functions). % Lisp primitives: this directives is at the end of the file
% :- ensure_loaded(lisp_library).	% Functions defined in lisp: this directive is at the end of the file
					% allowing them to be compiled correctly


:- op(1200, xfx, <<== ).	% function definition
:- op(1200,  fx, <<== ).	% functional imperative definition




% debug_var(_A,_Var):-!.
debug_var(X,Y):- notrace(catch(debug_var0(X,Y),_,fail)) -> true ; rtrace(debug_var0(X,Y)).

p_n_atom(Cmpd,UP):- sub_term(Atom,Cmpd),nonvar(Atom),\+ number(Atom), Atom\==[], catch(p_n_atom0(Atom,UP),_,fail),!.
p_n_atom(Cmpd,UP):- term_to_atom(Cmpd,Atom),p_n_atom0(Atom,UP),!.

filter_var_chars([H|X],Y):- \+ char_type(H,prolog_var_start),!,filter_var_chars0([86,118,H|X],Y).
filter_var_chars(X,Y):- filter_var_chars0(X,Y).

filter_var_chars0([],[]).
filter_var_chars0([45|T],[95|Rest]):-!,filter_var_chars0(T,Rest).
filter_var_chars0([H|T],[H|Rest]):-  code_type(H, prolog_identifier_continue),!,filter_var_chars0(T,Rest).
filter_var_chars0([H|T],Rest):- number_codes(H,Codes), filter_var_chars0(T,Mid),append([95, 99|Codes],[95|Mid],Rest).

p_n_atom0(Atom,UP):- atom(Atom),!,name(Atom,[C|Was]),to_upper(C,U),filter_var_chars([U|Was],CS),name(UP,CS).
p_n_atom0(String,UP):- string(String),!,string_to_atom(String,Atom),!,p_n_atom0(Atom,UP).
p_n_atom0([C|S],UP):- !,notrace(catch(atom_codes(Atom,[C|S]),_,fail)),!,p_n_atom0(Atom,UP).

debug_var0(_,NonVar):-nonvar(NonVar),!.
debug_var0([C|S],Var):- notrace(catch(atom_codes(Atom,[C|S]),_,fail)),!,debug_var0(Atom,Var).
debug_var0([AtomI|Rest],Var):-!,maplist(p_n_atom,[AtomI|Rest],UPS),atomic_list_concat(UPS,NAME),debug_var0(NAME,Var),!.
debug_var0(Atom,Var):- p_n_atom(Atom,UP),  
  check_varname(UP),
  add_var_to_env_loco(UP,Var),!.

add_var_to_env_loco(UP,Var):- \+ atom_concat('_',_,UP), var(Var),
  get_var_name(Var,Name),atomic(Name),\+ atom_concat('_',_,Name),
  
  atom_concat(UP,Name,New),add_var_to_env(New,Var).
add_var_to_env_loco(UP,Var):-add_var_to_env(UP,Var).

check_varname(UP):- name(UP,[C|_]),(char_type(C,digit)->throw(check_varname(UP));true).


% Connection to LPA's built-in error handler

'?ERROR?'(Error, Form):-
	lisp_error_description(_, Error, Description),
	!,
	write('LISP ERROR  '),
	write(Description),
	write(Form),
	nl.
'?ERROR?'(Error, Goal):-
	error_hook(Error, Goal).

bvof(E,L):-member(E,L).
env_memb(E,L):-member(E,L).

lisp_error_description(unbound_atom,        100, 'No value found for atom: ').
lisp_error_description(atom_does_not_exist, 101, 'SetQ: Variable does not exist: ').
lisp_error_description(first_not_cons,      102, 'First: This is not a cons cell: ').
lisp_error_description(rest_not_cons,       103, 'Rest: This is not a cons cell: ').

find_incoming_value(Ctx,_Ev,Atom,InValue,Value):-
      debug_var([Atom,'_In'],InValue),
      debug_var([Atom,'_Thru'],Value),
      ignore((member(bv(Atom0,[Value0|Unused]),Ctx.argbindings),
         Atom0==Atom,Value0=InValue,debug_var("__",Unused))).

% The hook into the compiler

lisp_compiler_term_expansion( (FunctionHeadP <<== FunctionBodyP),
		[(Head         :- !,  Code),
                 (Head         :- fail, <<==(FunctionHead , FunctionBody))] ):-
        must_det_l((expand_pterm_to_sterm(FunctionHeadP,FunctionHead),
        expand_pterm_to_sterm(FunctionBodyP,FunctionBody),
	expand_function_head(FunctionHead, Head, ArgBindings, Result),
                    debug_var("RET",Result),
                    debug_var("Env",Env),
	must_compile_body(ctx{head:Head,argbindings:ArgBindings},Env,Result,implicit_progn([FunctionBody]),Body0),
        Body = (Env=[ArgBindings],Body0),
    body_cleanup(Body,Code))).

lisp_compiler_term_expansion( ( <<== FunctionBodyP),
		( :-   Code) ):-
        must_det_l((expand_pterm_to_sterm(FunctionBodyP,FunctionBody),
	must_compile_body(_Cx,toplevel,_Result,implicit_progn([FunctionBody]), Body),
   body_cleanup(Body,Code))).

lisp_compiled_eval(SExpression):- 
  as_sexp(SExpression,Expression),
  lisp_compiled_eval(Expression,Result),
  dbmsg(result(Result)).
                                
lisp_compiled_eval(SExpression,Result):-
  as_sexp(SExpression,Expression),
  dbmsg(lisp_compile(Expression)),
  lisp_compile(Result,Expression,Code),
  dbmsg(Code),
  call(Code),!.


lisp_compile(SExpression):-
  as_sexp(SExpression,Expression),
  dbmsg(lisp_compiled_eval(Expression)),
  lisp_compile(Expression,Code),!,
  dbmsg(Code).

lisp_compile(SExpression,Body):-
   debug_var('_Ignored',Result),
   as_sexp(SExpression,Expression),
   lisp_compile(Result,Expression,Body).

lisp_compile(Result,SExpression,Body):- 
   as_sexp(SExpression,Expression),
   lisp_compile(ctx{head:lisp_compile(),argbindings:[]},toplevel,Result,Expression,Body).

lisp_compile(Ctx,Env,Result,FunctionBody,Body):- 
   compile_forms(Ctx,Env,Result,[FunctionBody],Body).


compile_forms(Ctx,Env,Result,FunctionBody,Code):-
   must_compile_body(Ctx,Env,Result,implicit_progn(FunctionBody), Body),!,
   body_cleanup(Body,Code).


expand_function_head([FunctionName | FormalArgs], Head, ArgBindings, Result):-!,
        freeze(Arg,debug_var(Arg,Val)),
	zip_with(FormalArgs, ActualArgs, [Arg, Val, bv(Arg, [Val|_])]^true, ArgBindings),
	append(ActualArgs, [Result], HeadArgs),
	Head =.. [FunctionName | HeadArgs].
expand_function_head(FunctionName , Head, ArgBindings, Result):-
    expand_function_head([FunctionName], Head, ArgBindings, Result).


% compile_body(Ctx,Env,Result,Function, Body).
% Expands a Lisp-like function body into its Prolog equivalent

must_compile_body(Ctx,Env,Result,Function, Body):-
  must_or_rtrace(compile_body(Ctx,Env,Result,Function, Body)).



/*(defmacro prog (inits &rest forms)
  `(block nil
    (let ,inits
      (tagbody ,@forms))))
*/
compiler_macro_left_right(prog,[Vars|TagBody], [block,[],[let,Vars,[tagbody|TagBody]]]).
% (defmacro unless (test-form &rest forms) `(if (not ,test-form) (progn ,@forms)))
compiler_macro_left_right(unless,[Test|IfFalse] , [if, Test, [], [progn|IfFalse]]).
% (defmacro when (test-form &rest forms) `(if ,test-form (progn ,@forms)))
compiler_macro_left_right( when,[Test|IfTrue]  , [if, Test, [progn|IfTrue], []]).

:- discontiguous(compile_body/5).

compile_body(Ctx,Env,Result,[M|MACROLEFT], Code):- 
  term_variables([M|MACROLEFT],VarsS),
  compiler_macro_left_right(M,MACROLEFT,MACRORIGHT),
  term_variables(MACRORIGHT,VarsE),
  VarsE==VarsS,!,
  must_compile_body(Ctx,Env,Result,MACRORIGHT, Code).

compile_body(Ctx,Env,Result,InstrS,Code):-
  shared_lisp_compiler:plugin_expand_function_body(Ctx,Env,Result,InstrS,Code),!.

compile_body(Cx,Ev,Name,[defmacro,Name,Args|FunctionBody0], CompileBody):- !,
  compile_body(Cx,Ev,Name,[defun,Name,Args|FunctionBody0], CompileBody).
compile_body(_Cx,_Ev,Name,[defun,Name0,Args|FunctionBody0], CompileBody):- 
    combine_setfs(Name0,Name),
    must(maybe_get_docs(defun,Name,FunctionBody0,FunctionBody)),
    FunctionHead=[Name|Args],
    CompileBody = (asserta((Head  :- (fail, <<==(FunctionHead , FunctionBody)))),
                   asserta((Head  :- (!,  Code)))),!,
      expand_function_head(FunctionHead, Head, ArgBindings, Result),
      must_compile_body(ctx{head:Head,argbindings:ArgBindings},Env,Result,implicit_progn(FunctionBody),  Body0),
      debug_var("RET",Result),
      debug_var("FEnv",Env),
      Body = (Env=[ArgBindings],Body0),
      term_attvars(Body,AttVars),
      maplist(del_attr_rev2(freeze),AttVars),
      mize_body(',',Body,Code).

combine_setfs(Name0,Name):-atom(Name0),Name0=Name.
combine_setfs(Name0,Name):-atomic_list_concat(Name0,-,Name).

compile_body(_Cx,_Ev,SelfEval,SelfEval,true):- notrace(is_self_evaluationing_object(SelfEval)),!.
compile_body(_Cx,_Ev, [],nil,true):- !.
compile_body(_Cx,_Ev,Item,[quote, Item],  true):- !.

compile_body(_Cx,_Ev,[],[progn],  true):- !.
compile_body(Ctx,Env,Result,[progn,Forms], Body):- !, must_compile_body(Ctx,Env,Result,Forms, Body).
compile_body(Ctx,Env,Result,[progn|Forms], Body):- !, must_compile_progn(Ctx,Env,Result,Forms, [],Body).
compile_body(Ctx,Env,Result,implicit_progn(Forms), Body):- is_list(Forms),!,must_compile_progn(Ctx,Env,Result,Forms, [],Body).
compile_body(Ctx,Env,Result,implicit_progn(Forms), Body):- !,must_compile_body(Ctx,Env,Result,Forms, Body).



compile_body(Ctx,Env,Result, 's'(Str),  Body):-
  parse_sexpr_untyped(string(Str),Expression),!,
  must_compile_body(Ctx,Env,Result, Expression,  Body).

/*
compile_body(Ctx,Env,Result, List,  Body):-  \+ is_list(List),!,
  expand_pterm_to_sterm(List,PTerm),
  compile_body(Ctx,Env,Result, PTerm,  Body).
*/
compile_body(Ctx,Env,Result,[if, Test, IfTrue], Body):-must_compile_body(Ctx,Env,Result,[if, Test, IfTrue, []],Body).


compile_body(Ctx,Env,Result,[if, [null,Test], IfTrue, IfFalse], Body):-
	!,
   must_compile_body(Ctx,Env,TestResult,Test,  TestBody),
   must_compile_body(Ctx,Env,TrueResult,IfTrue, TrueBody),
   must_compile_body(Ctx,Env,FalseResult,IfFalse, FalseBody),
        debug_var("IF",TestResult),
        Body = (	TestBody,
			( TestResult == []
				-> 	TrueBody,
					Result      = TrueResult
				;  	FalseBody,
					Result      = FalseResult	) ).

compile_body(Ctx,Env,Result,[if, Test, IfTrue, IfFalse], Body):-
	!,
   must_compile_body(Ctx,Env,TestResult,Test,  TestBody),
   must_compile_body(Ctx,Env,TrueResult,IfTrue, TrueBody),
   must_compile_body(Ctx,Env,FalseResult,IfFalse, FalseBody),
        debug_var("IF",TestResult),
        Body = (	TestBody,
			( TestResult \= []
				-> 	TrueBody,
					Result      = TrueResult
				;  	FalseBody,
					Result      = FalseResult	) ).

compile_body(_Cx,_Ev,[],[cond, []], true):- !.
compile_body(Ctx,Env,Result,[cond, [ [Test|ResultForms] |Clauses]], Body):-
	!,
	must_compile_body(Ctx,Env,TestResult,Test,  TestBody),
	must_compile_progn(Ctx,Env,ResultFormsResult,ResultForms, TestResult, ResultFormsBody),
	must_compile_body(Ctx,Env,ClausesResult,[cond, Clauses],  ClausesBody),
	Body = (	TestBody,
			( TestResult \= []
				->	ResultFormsBody,
					Result      = ResultFormsResult
				;	ClausesBody,
					Result      = ClausesResult )	).


expand_function_body_unused_needs_throw(Ctx,Env,Result,[car, IN], Body):- \+ current_prolog_flag(lisp_inline,false),
	!,
        must_compile_body(Ctx,Env,MID,IN, ValueBody),
        Body = (ValueBody,(MID =[Result|_]->true;Result=MID)).

compile_body(Ctx,Env,Result,[cons, IN1,IN2], Body):- \+ current_prolog_flag(lisp_inline,false),
	!,
        must_compile_body(Ctx,Env,MID1,IN1,  ValueBody1),
        must_compile_body(Ctx,Env,MID2,IN2,  ValueBody2),
        Body = (ValueBody1,ValueBody2,Result=[MID1|MID2]).




compile_body(Ctx,Env,Result,[function, [lambda,LambdaArgs| LambdaBody]], Body):-
	!,
	must_compile_body(Ctx,ClosureEnvironment,ClosureResult,implicit_progn(LambdaBody),  ClosureBody),
        debug_var('LArgs',LambdaArgs),
        debug_var('LResult',ClosureResult),
        debug_var('LEnv',ClosureEnvironment),
                     Result = [closure,LambdaArgs,
			[ClosureEnvironment, ClosureResult]^ClosureBody,
			Env],
	Body = true.
compile_body(_Cx,_Ev,[function|Function], [function|Function], true):- !.


compile_body(Ctx,Env,Result,[lambda,LambdaArgs|LambdaBody], Body):-
	!,
	must_compile_body(Ctx,ClosureEnvironment,ClosureResult,implicit_progn(LambdaBody),  ClosureBody),
        debug_var('LArgs',LambdaArgs),
        debug_var('LResult',ClosureResult),
        debug_var('LEnv',ClosureEnvironment),
                     Result = [closure,LambdaArgs,
			[ClosureEnvironment, ClosureResult]^ClosureBody,
			Env],
	Body = true.




normalize_let([],[]).
normalize_let([Decl|NewBindingsIn],[Norm|NewBindings]):-
  must(normalize_let1(Decl,Norm)),
  normalize_let(NewBindingsIn,NewBindings).

normalize_let1([bind, Variable, Form],[bind, Variable, Form]).
normalize_let1([Variable, Form],[bind, Variable, Form]).
normalize_let1(Variable,[bind, Variable, []]).


compile_body(Ctx,Env,Result,[let, NewBindingsIn| BodyForms], Body):-
     must(normalize_let(NewBindingsIn,NewBindings)),!,        
	zip_with(Variables, ValueForms, [Variable, Form, [bind, Variable, Form]]^true, NewBindings),
	expand_arguments(Ctx,ValueForms, ValueBody, Values, Env),
	zip_with(Variables, Values, [Var, Val, bv(Var, [Val|Unused])]^true,Bindings),

   must((debug_var("_U",Unused),
   debug_var("LETENV",BindingsEnvironment),
   ignore((member(VarN,[Variable,Var]),atom(VarN),debug_var([VarN,'_Let'],Val))))), 

	must_compile_body(Ctx,BindingsEnvironment,Result,implicit_progn(BodyForms), BodyFormsBody),
         Body = ( ValueBody,BindingsEnvironment=[Bindings|Env], BodyFormsBody ).

%   zip_with(Xs, Ys, Pred, Zs)
%   is true if Pred(X, Y, Z) is true for all X, Y, Z.

zip_with([], [], _, []).
zip_with([X|Xs], [Y|Ys], Pred, [Z|Zs]):-
	lpa_apply(Pred, [X, Y, Z]),
	zip_with(Xs, Ys, Pred, Zs).

compile_body(Ctx,Env,Result,BodyForms, Body):- compile_assigns(Ctx,Env,Result,BodyForms, Body).

:- dynamic(op_replacement/2).
/*
op_replacement(+,plus).
op_replacement(-,minus).
op_replacement(*,mult).
op_replacement(<,lessThan).
op_replacement(>,greaterThan).
*/

compile_body(Ctx,Env,Result,[Op | FunctionArgs], Body):- op_replacement(Op,Op2), !,
  must_compile_body(Ctx,Env,Result,[Op2 | FunctionArgs],Body).


compile_body(Ctx,Env,Result,[FunctionName | FunctionArgs], Body):- \+ atom(FunctionName),!,
  must_compile_body(Ctx,Env,Result,[funcall,FunctionName | FunctionArgs],Body).

compile_body(Ctx,Env,Result,[FunctionName | FunctionArgs], Body):- FunctionName \==funcall,
  member(bv(Atom0,_),Ctx.argbindings),Atom0==FunctionName,!,
  must_compile_body(Ctx,Env,Result,[funcall,FunctionName | FunctionArgs],Body).

% Non built-in function expands into an explicit function call
compile_body(Ctx,Env,Result,[FunctionName | FunctionArgs], Body):-
      !,
      expand_arguments(Ctx,FunctionArgs, ArgBody, Args, Env),
      append(Args, [Result], ArgsResult),
      debug_var([FunctionName,'_Ret'],Result),
      ExpandedFunction =.. [FunctionName | ArgsResult],
      Body = (	ArgBody,
                      ExpandedFunction	).
   

	expand_arguments(_Ctx,[], true, [], _Environment).
	expand_arguments(Ctx,[Arg|Args], Body, [Result|Results], Env):-
		must_compile_body(Ctx,Env,Result,Arg, ArgBody),
                Body = (ArgBody, ArgsBody),
		expand_arguments(Ctx,Args, ArgsBody, Results, Env).


must_compile_progn(Ctx,Env,Result,Forms, PreviousResult, Body):-
   must_or_rtrace(compile_progn(Ctx,Env,Result,Forms, PreviousResult,Body)).
must_compile_progn1(Ctx,Env,Result,Forms, PreviousResult, Body):-
   must_or_rtrace(compile_progn1(Ctx,Env,Result,Forms, PreviousResult,Body)).

compile_progn(_Cx,_Ev,Result,[], Result,true).
compile_progn(Ctx,Env,Result,[Form | Forms], _PreviousResult, Body):-  !,
	must_compile_body(Ctx,Env,FormResult, Form,FormBody),
	must_compile_progn(Ctx,Env,Result, Forms, FormResult, FormSBody),
        Body = (FormBody,FormSBody).
compile_progn(Ctx,Env,Result, Form , _PreviousResult, Body):-
	must_compile_body(Ctx,Env,Result,Form, Body).


:- set_prolog_flag(double_quotes,string).


tst:is_local_test("
(defun sum_with_map (xs)
  (let (( running_total 0))
    (let ((summer 
            (function 
               (lambda (n)
                (setq running_total (+ running_total n))))))
       (mapcar summer  xs) running_total)))
 "
  ).

tst:is_local_test("(defun accumulate (op seq &optional (init 0)) (if (null seq) init (funcall op (car seq) (accumulate op (cdr seq) init))))").


:- fixup_exports.
